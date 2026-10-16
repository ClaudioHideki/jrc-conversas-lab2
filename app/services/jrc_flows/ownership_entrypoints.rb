module JrcFlows::OwnershipEntrypoints
  def self.local(run, path, reference, &)
    return unless run

    JrcFlows::OwnershipGuard.with_local(run.account_id, run.conversation.inbox_id, path: path, reference: reference, &)
  rescue JrcFlows::OwnershipGuard::Closed
    nil
  end

  module Listener
    private

    def dispatch(conversation, name, key, message_id = nil, label = nil)
      JrcFlows::OwnershipGuard.with_local(conversation.account_id, conversation.inbox_id, path: 'listener', reference: "listener:#{key}") { super }
    rescue JrcFlows::OwnershipGuard::Closed
      nil
    end
  end

  module Dispatch
    def perform(account_id, conversation_id, event_name, event_key, *rest)
      conversation=Conversation.find_by(account_id: account_id, id: conversation_id)
      return unless conversation

      JrcFlows::OwnershipGuard.with_local(account_id, conversation.inbox_id, path: 'dispatch', reference: "dispatch:#{event_key}") { super }
    rescue JrcFlows::OwnershipGuard::Closed
      nil
    end
  end

  module Resume
    def perform(run_id, wake_version = nil)
      run=JrcFlowRun.find_by(id: run_id)
      JrcFlows::OwnershipEntrypoints.local(run, 'resume', "run:#{run_id}:wake:#{wake_version}") { super }
    end
  end

  module WorkflowTurn
    def perform(run_id, message_id)
      run=JrcFlowRun.find_by(id: run_id)
      JrcFlows::OwnershipEntrypoints.local(run, 'workflow-turn', "run:#{run_id}:message:#{message_id}") { super }
    end
  end

  module PlaybookResume
    def perform(run_id, wake_version)
      run = JrcFlowRun.find_by(id: run_id)
      JrcFlows::OwnershipEntrypoints.local(run, 'resume', "playbook-resume:#{run_id}:#{wake_version}") { super }
    end
  end

  module Runner
    def perform(message: nil, wake_version: nil)
      JrcFlows::OwnershipEntrypoints.local(@run, 'runner', "run:#{@run.id}:wake:#{wake_version}:message:#{message&.id}") { super }
    end
  end

  module WorkflowRunner
    def perform(message: nil)
      JrcFlows::OwnershipEntrypoints.local(@run, 'workflow-runner', "workflow:#{@run.id}:message:#{message&.id || @run.last_message_id}") { super }
    end
  end

  module Recovery
    def perform
      return unless ENV['JRC_FLOWS_ENABLED']=='true'

      JrcFlow.active.where("settings ->> 'trigger' = ?", 'schedule').where('next_run_at <= ?', Time.current).find_each do |flow|
        flow.with_lock do
          next unless flow.status=='active' && flow.next_run_at && flow.next_run_at<=Time.current

          scheduled_at=flow.next_run_at.to_i
          admitted=false
          flow.account.conversations.where(display_id: Array(flow.settings['conversation_ids']),
                                           inbox_id: Array(flow.settings['inbox_ids'])).find_each do |conversation|
            next unless JrcFlows::OwnershipGuard.allowed_local?(conversation.account_id, conversation.inbox_id)

            admitted=true
            begin
              JrcFlows::OwnershipGuard.with_local(
                conversation.account_id, conversation.inbox_id, path: 'recovery',
                reference: "schedule:#{flow.id}:#{scheduled_at}:#{conversation.id}"
              ) do
                JrcFlows::DispatchJob.perform_later(flow.account_id, conversation.id, 'schedule', "schedule:#{scheduled_at}:#{conversation.id}", nil,
                                                    nil, flow.id)
              end
            rescue JrcFlows::OwnershipGuard::Closed
              next
            end
          end
          flow.update_columns(next_run_at: flow.settings['interval_minutes'].to_i.minutes.from_now) if admitted
        end
      end
      JrcFlowRun.where(status: %w[waiting delayed]).where('wake_at <= ?', Time.current).find_each do |run|
        next unless JrcFlows::OwnershipGuard.allowed_local?(run.account_id, run.conversation.inbox_id)

        JrcFlows::OwnershipEntrypoints.local(run, 'recovery', "recover:#{run.id}:#{run.wake_version}") do
          JrcFlows::ResumeJob.perform_later(run.id, run.wake_version)
        end
      end
      JrcFlowRun.where(status: 'waiting').where('settings ? :key', key: JrcRelationship::PlaybookFlowWebhookJournal::KEY).find_each do |run|
        next unless JrcRelationship::PlaybookFlowContinuation.managed?(run)
        next unless JrcFlows::OwnershipGuard.allowed_local?(run.account_id, run.conversation.inbox_id)

        JrcFlows::OwnershipEntrypoints.local(run, 'recovery', "recover-webhook:#{run.id}") do
          JrcRelationship::PlaybookFlowWebhookDelivery.recover(run)
        end
      end
      JrcFlowRun.where(status: 'running').where('created_at < ?', 2.minutes.ago).find_each do |run|
        next unless JrcFlows::OwnershipGuard.allowed_local?(run.account_id, run.conversation.inbox_id)

        JrcFlows::OwnershipEntrypoints.local(run, 'recovery', "recover:#{run.id}:running") { JrcFlows::ResumeJob.perform_later(run.id) }
      end
    end
  end

  def self.event_inbox(event)
    payload=event.payload.to_h
    conversation=payload['conversation'] || payload
    (conversation['inbox_id'] || payload['inbox_id']).presence
  end

  module RemoteEvent
    def perform(event_id)
      event=JrcFlowRemoteEvent.find_by(id: event_id, status: 'queued')
      return unless event

      JrcFlows::OwnershipGuard.with_remote(
        event.connection, JrcFlows::OwnershipEntrypoints.event_inbox(event), path: 'remote-event', reference: "remote-event:#{event_id}"
      ) do
        super
      end
    rescue JrcFlows::OwnershipGuard::Closed
      nil
    end
  end

  module RemoteResume
    def perform(session_id)
      session=JrcFlowRemoteSession.find_by(id: session_id)
      return unless session

      JrcFlows::OwnershipGuard.with_remote(
        session.connection, session.inbox_id, path: 'remote-resume', reference: "remote-session:#{session_id}:wake:#{session.wake_at&.to_i}"
      ) do
        super
      end
    rescue JrcFlows::OwnershipGuard::Closed
      nil
    end
  end

  module RemoteRecovery
    def perform
      return unless JrcFlows::Access.external_beta?

      JrcFlowRemoteEvent.where(status: 'queued').where('created_at < ?', 30.seconds.ago).limit(100).each do |event|
        next unless JrcFlows::OwnershipGuard.allowed_remote?(event.connection, JrcFlows::OwnershipEntrypoints.event_inbox(event))

        JrcFlows::RemoteEventJob.perform_later(event.id)
      end
      JrcFlowRemoteEvent.where(status: 'running').where('claimed_at < ?', 10.minutes.ago).find_each do |event|
        next unless JrcFlows::OwnershipGuard.allowed_remote?(event.connection, JrcFlows::OwnershipEntrypoints.event_inbox(event))

        event.update!(status: 'failed', error: 'Execução interrompida; verifique efeitos externos antes de repetir.')
      end
      JrcFlowRemoteSession.where(status: 'running').where('claimed_at < ?', 3.minutes.ago).find_each do |session|
        next unless JrcFlows::OwnershipGuard.allowed_remote?(session.connection, session.inbox_id)

        session.update!(status: 'failed', error: 'Execução interrompida; resultado externo incerto.', wake_at: nil)
      end
      JrcFlowRemoteSession.where(status: %w[waiting delayed]).where('wake_at <= ?', Time.current).limit(100).each do |session|
        next unless JrcFlows::OwnershipGuard.allowed_remote?(session.connection, session.inbox_id)

        JrcFlows::RemoteResumeJob.perform_later(session.id)
      end
      # Tombstones for fenced scopes and all independent effect intents remain.
      JrcFlowRemoteEvent.where(status: %w[completed failed]).where('created_at < ?', 7.days.ago).limit(1000).each do |event|
        next unless JrcFlows::OwnershipGuard.allowed_remote?(event.connection, JrcFlows::OwnershipEntrypoints.event_inbox(event))

        event.delete
      end
    end
  end

  module RemoteRunner
    def receive(payload)
      data=payload['conversation'] || payload
      iid=(data['inbox_id'] || payload['inbox_id']).presence
      JrcFlows::OwnershipGuard.with_remote(
        @connection, iid, path: 'remote-runner', reference: "remote:#{@connection.id}:event:#{payload['event']}:#{payload['id'] || data['id']}"
      ) do
        super
      end
    rescue JrcFlows::OwnershipGuard::Closed
      nil
    end

    def resume(session)
      JrcFlows::OwnershipGuard.with_remote(
        @connection, session.inbox_id, path: 'remote-runner',
        reference: "remote:#{@connection.id}:session:#{session.id}:wake:#{session.wake_at&.to_i}"
      ) do
        super
      end
    rescue JrcFlows::OwnershipGuard::Closed
      nil
    end

    private

    def guard!
      JrcFlows::OwnershipGuard.checkpoint!
      super
      JrcFlows::OwnershipGuard.checkpoint!
    end

    def checkpoint(node)
      Thread.current[:jrc_flow_ownership][:node]=node['id'] if Thread.current[:jrc_flow_ownership]
      super
    end
  end
end
