class JrcFlows::Runner
  def initialize(run)
    @run = run
    @flow = run.flow
    @conversation = run.conversation
    @account = run.account
  end

  # Consistent lock order serializes incoming messages, timers and human takeover.
  def perform(message: nil, wake_version: nil)
    JrcRelationship::PlaybookFlowContinuation.perform(@run, message: message) do |authorized_message|
      perform_native(message: authorized_message || message, wake_version: wake_version)
    end
  end

  private

  def perform_native(message: nil, wake_version: nil)
    previous_actor = Current.executed_by
    return JrcFlows::WorkflowRunner.new(@run).perform(message: message) if @flow.engine == 'workflow'

    @conversation.with_lock do
      @run.with_lock do
        begin
          JrcFlowRun.transaction(requires_new: true) { perform_locked(message, wake_version) }
        rescue StandardError => e
          trace = @run.trace
          @run.reload.update!(status: 'failed', trace: trace, error: JrcRelationship::PlaybookFlowContinuation.error_message(@run, e),
                              finished_at: Time.current, wake_at: nil)
          Rails.logger.warn("JRC Flows run=#{@run.id} failed: #{e.class}")
        end
      end
    end
    @run
  ensure
    # Keep the actor until the outer transaction's after_commit callbacks finish.
    Current.executed_by = previous_actor
  end

  def perform_locked(message, wake_version)
    return unless %w[running waiting delayed].include?(@run.status)
    return pause!('Fluxo desativado ou responsável sem acesso.') unless authorized?
    return pause!('Atendimento assumido por pessoa ou outro robô.') if human_owned?
    return if message && message.id <= @run.last_message_id
    return if wake_version && (wake_version != @run.wake_version || @run.wake_at.nil? || @run.wake_at > Time.current)
    return if !message && wake_version.nil? && @run.status != 'running'

    Current.executed_by = @run
    if message
      @run.last_message_id = message.id
      @run.variables['message'] = message.content.to_s.first(10_000)
      if @run.status == 'delayed'
        return pause!('Sequência interrompida: cliente respondeu.') if @run.settings.fetch('stop_on_reply', true)

        @run.save!
        return
      end
      consume_input if @run.status == 'waiting'
    elsif wake_version
      advance!(@run.status == 'waiting' ? 'timeout' : 'next')
    end
    @run.status = 'running'
    @run.wake_at = nil
    @run.wake_version += 1
    execute
  end

  def authorized?
    @flow.reload.status == 'active' && @flow.lock_version == @run.settings['_flow_version'] && JrcFlows::Access.enabled?(@account.reload) &&
      @account.account_users.exists?(user_id: @flow.created_by_id, role: 'administrator')
  end

  def human_owned?
    @conversation.assignee_agent_bot_id.present? || JrcFlows::Access.inbox_bot_owned?(@conversation) ||
      (@run.settings.fetch('pause_on_agent', true) && @conversation.assignee_id.present?) ||
      (@run.settings.fetch('pause_on_team', false) && @conversation.team_id.present?) ||
      @conversation.messages.outgoing.where(sender_type: 'User', private: false).where('created_at > ?', @run.created_at).exists?
  end

  def pause!(reason)
    @run.update!(status: 'paused', error: reason, wake_at: nil, finished_at: Time.current)
  end

  def node
    @run.graph.fetch('nodes').find { |item| item['id'] == @run.node_id }
  end

  def evaluator
    JrcFlows::Evaluator.new(@run.variables)
  end

  def advance!(port = 'next')
    edge = @run.graph.fetch('edges').find { |item| item['source'] == @run.node_id && item['port'] == port }
    @run.node_id = edge&.fetch('target')
  end

  def consume_input
    data = node.fetch('data')
    @run.variables[data.fetch('variable')] = @run.variables['message']
    advance!
  end

  def execute
    while (current = authorized_node)
      @run.steps += 1
      raise 'Limite de execução excedido.' if @run.steps > 200

      @run.trace = (@run.trace + [{ node_id: current['id'], label: current['label'], type: current['type'], at: Time.current.iso8601 }]).last(200)
      type, data = current.values_at('type', 'data')
      case type
      when 'input' then return wait!(data.fetch('timeout').to_i, 'waiting')
      when 'delay' then return wait!(data.fetch('seconds').to_i, 'delayed')
      when 'condition', 'switch'
        advance!(evaluator.port(current))
        next
      when 'end'
        @run.node_id = nil
        break
      when 'start'
        # The trigger is checked by DispatchJob.
      else
        result = JrcFlows::Actions.new(@run).execute(type, data)
        return if result == JrcRelationship::PlaybookFlowWebhookJournal::PENDING && JrcRelationship::PlaybookFlowContinuation.managed?(@run)
        if JrcFlows::Definition::TERMINAL.include?(type)
          @run.node_id = nil
          break
        end
      end
      advance!
    end
    @run.update!(status: 'completed', finished_at: Time.current, wake_at: nil, node_id: nil)
  end

  def authorized_node
    current = node
    JrcRelationship::PlaybookFlowContinuation.authorize_node!(@run, current) if current
    current
  end

  def wait!(seconds, status)
    @run.update!(status: status, wake_at: seconds.seconds.from_now)
    return if JrcRelationship::PlaybookFlowContinuation.managed?(@run)

    JrcRelationship::PlaybookFlowContinuation.resume_job(@run).set(wait_until: @run.wake_at).perform_later(@run.id, @run.wake_version)
  end
end
