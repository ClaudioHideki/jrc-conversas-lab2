require 'sidekiq/api'

class JrcFlows::OwnershipQueues
  def self.each_matching(scope)
    scanned=0
    [*Sidekiq::Queue.all, Sidekiq::ScheduledSet.new, Sidekiq::RetrySet.new].each do |queue|
      queue.each do |job|
        scanned+=1
        raise JrcFlows::NativeOwnership::NotDrained, 'FLOW_QUEUE_SCAN_BOUND' if scanned>10_000

        payload=job.item['args']&.first
        next unless payload.is_a?(Hash)

        name=payload['job_class']
        args=payload['arguments'] || []
        match=case name
              when 'JrcFlows::DispatchJob'
                conversation=Conversation.find_by(account_id: args[0], id: args[1])
                conversation && scope.host_origin==JrcFlows::OwnershipGuard.local_origin &&
                  conversation.account_id==scope.account_id && conversation.inbox_id==scope.inbox_id
              when 'JrcFlows::ResumeJob', 'JrcFlows::WorkflowTurnJob',
                   'JrcRelationship::PlaybookFlowWebhookJob', 'JrcRelationship::PlaybookFlowResumeJob'
                run=JrcFlowRun.find_by(id: args[0])
                run && scope.host_origin==JrcFlows::OwnershipGuard.local_origin &&
                  run.account_id==scope.account_id && run.conversation.inbox_id==scope.inbox_id
              when 'JrcFlows::RemoteResumeJob'
                session=JrcFlowRemoteSession.find_by(id: args[0])
                session && remote_matches?(scope, session.connection, session.inbox_id)
              when 'JrcFlows::RemoteEventJob'
                event=JrcFlowRemoteEvent.find_by(id: args[0])
                event && remote_matches?(scope, event.connection, JrcFlows::OwnershipEntrypoints.event_inbox(event))
              when 'JrcFlows::NativeResponderWebhookJob'
                scope.host_origin==JrcFlows::OwnershipGuard.local_origin && args[0].to_i==scope.account_id && args[1].to_i==scope.inbox_id
              when 'AgentBots::WebhookJob'
                metadata=args.last.is_a?(Hash) ? args.last.with_indifferent_access : {}
                unless metadata['native_account_id'] && metadata['native_inbox_id']
                  raise JrcFlows::NativeOwnership::NotDrained,
                        'FLOW_NATIVE_JOB_PROVENANCE_REQUIRED'
                end

                same=scope.host_origin==JrcFlows::OwnershipGuard.local_origin &&
                     metadata['native_account_id'].to_i==scope.account_id && metadata['native_inbox_id'].to_i==scope.inbox_id
                trusted=same && metadata['native_epoch_id'] && metadata['native_epoch_id'].to_i==scope.current_epoch_id &&
                        JrcFlowOwnershipEpoch.where(
                  id: scope.current_epoch_id, scope_id: scope.id, broker_agent_bot_id: metadata['native_bot_id']
                ).exists?
                same && !trusted
              when 'SendReplyJob'
                message=Message.find_by(id: args[0])
                message && (message.content_attributes.to_h['jrc_flow_run_id'] || JrcFlows::NativeResponders.legacy_message?(message)) &&
                  scope.host_origin==JrcFlows::OwnershipGuard.local_origin && message.account_id==scope.account_id &&
                  message.conversation.inbox_id==scope.inbox_id
              else
                false
              end
        yield job if match
      end
    end
  end

  def self.remote_matches?(scope, connection, inbox_id)
    JrcFlows::OwnershipGuard.origin(connection.base_url)==scope.host_origin && connection.remote_account_id==scope.account_id &&
      (inbox_id ? inbox_id.to_i==scope.inbox_id : Array(connection.inbox_ids).include?(scope.inbox_id))
  end

  def self.cancel!(scope) = each_matching(scope) { |job| job.delete }

  def self.count(scope)
    result=0
    each_matching(scope) { result+=1 }
    result
  end
end
