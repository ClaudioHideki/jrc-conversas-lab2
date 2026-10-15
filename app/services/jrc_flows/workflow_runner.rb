class JrcFlows::WorkflowRunner
  def initialize(run)
    @run = run
    @flow = run.flow
    @conversation = run.conversation
  end

  def perform(message: nil)
    payload = claim(message)
    return @run unless payload

    engine = JrcFlows::WorkflowEngine.new(@flow, guard: ->(node) { checkpoint(node) })
    result = engine.perform(payload.stringify_keys)
    response = JrcFlows::WorkflowResponse.normalize(result[:output])
    apply(response, payload.fetch(:message_id))
    @run
  rescue StandardError => e
    @conversation.with_lock do
      @run.reload
      if @run.status == 'running'
        reason = e.is_a?(JrcFlows::WorkflowEngine::Error) ? e.message : 'Falha no workflow JRC. Consulte os nós e suas configurações.'
        @run.update!(status: 'failed', error: reason.first(240), finished_at: Time.current, wake_at: nil)
      end
    end
    Rails.logger.warn("JRC workflow run=#{@run.id} failed: #{e.class}")
    @run
  end

  private

  def checkpoint(node)
    @conversation.with_lock do
      @run.reload
      return false unless @run.status == 'running' && allowed?

      @run.variables['_workflow_inflight']['at'] = Time.current.iso8601
      @run.trace = (@run.trace + [{ node_id: node['id'], label: node['name'], type: node['type'], at: Time.current.iso8601 }]).last(200)
      @run.save!
      true
    end
  end

  def claim(message)
    @conversation.with_lock do
      @run.reload
      return unless %w[running waiting].include?(@run.status)
      return pause! unless allowed?

      inflight = @run.variables['_workflow_inflight']
      if inflight
        if Time.iso8601(inflight['at']) < 2.minutes.ago
          @run.update!(status: 'failed',
                       error: 'Execução interrompida; resultado de integrações incerto. Confira o histórico antes de tentar novamente.',
                       finished_at: Time.current)
        elsif message
          JrcFlows::WorkflowTurnJob.set(wait: 3.seconds).perform_later(@run.id, message.id)
        end
        return
      end
      if message
        return if message.id <= @run.last_message_id

        # Process queued customer turns in order, even if workers receive events out of order.
        message = next_message
        return unless message

        @run.last_message_id = message.id
        @run.variables['message'] = message.content.to_s.first(10_000)
      elsif @run.status == 'waiting'
        return
      end
      raise JrcFlows::WorkflowEngine::Error, 'Limite de 200 turnos atingido. Encerre esta conversa para iniciar outra sessão.' if @run.steps >= 200

      id = "jrc-#{@run.account_id}-#{@run.id}-#{@run.last_message_id}"
      @run.variables['_workflow_inflight'] = { 'id' => id, 'at' => Time.current.iso8601 }
      @run.steps += 1
      @run.trace = (@run.trace + [{ node_id: 'workflow', label: 'Mensagem recebida', type: 'workflow', at: Time.current.iso8601 }]).last(200)
      @run.update!(status: 'running', wake_at: nil, node_id: 'workflow')
      { event_type: 'MESSAGE', mensagem: @run.variables['message'], message_id: id,
        tenant_id: "jrc-#{@run.account_id}", conversation_id: "jrc-#{@run.account_id}-#{@conversation.id}-#{@run.id}",
        telefone: @conversation.contact.phone_number.to_s, origem: 'JRC_CONVERSAS',
        canal: @conversation.inbox.channel_type.delete_prefix('Channel::').upcase,
        environment: @run.settings.fetch('environment', 'HML'), human_active: false }
    end
  end

  def apply(response, message_id)
    previous_actor = Current.executed_by
    @conversation.with_lock do
      @run.reload
      return unless @run.status == 'running' && @run.variables.dig('_workflow_inflight', 'id') == message_id
      return pause! unless allowed?

      Current.executed_by = @run
      actions = JrcFlows::Actions.new(@run)
      team = handoff_team(response) if response['handoff']
      response.fetch('messages').each { |text| actions.execute('message', 'text' => text) } unless response['ignore']
      if team
        actions.execute('note', 'text' => response['summary'].to_s.first(10_000)) if response['summary'].present?
        actions.execute('assign', 'team_id' => team.id)
        @run.variables['_workflow_handoff_team'] = team.id
      elsif response['close']
        actions.execute('status', 'status' => 'resolved')
      end
      @run.variables.delete('_workflow_inflight')
      done = team.present? || response['close']
      @run.update!(status: done ? 'completed' : 'waiting', finished_at: done ? Time.current : nil, wake_at: nil)
    end
    pending = next_message
    JrcFlows::WorkflowTurnJob.perform_later(@run.id, pending.id) if @run.status == 'waiting' && pending
  ensure
    Current.executed_by = previous_actor
  end

  def next_message
    @conversation.messages.incoming.where(private: false).where('id > ?', @run.last_message_id).order(:id).first
  end

  def handoff_team(response)
    key = { 'SUPORTE' => 'workflow_support_team_id', 'FINANCEIRO' => 'workflow_financial_team_id',
            'COMERCIAL' => 'workflow_commercial_team_id' }[response['destination'].to_s.upcase]
    id = @run.settings[key].presence || @run.settings['workflow_team_id']
    @run.account.teams.find(id)
  end

  def allowed?
    @conversation.reload
    @flow.reload.status == 'active' && @flow.lock_version == @run.settings['_flow_version'] && JrcFlows::Access.enabled?(@run.account) &&
      @run.account.account_users.exists?(user_id: @flow.created_by_id, role: 'administrator') &&
      @conversation.assignee_agent_bot_id.nil? && !JrcFlows::Access.inbox_bot_owned?(@conversation) &&
      !(@run.settings.fetch('pause_on_agent', true) && @conversation.assignee_id.present?) &&
      !(@run.settings.fetch('pause_on_team', false) && @conversation.team_id.present?) &&
      !@conversation.messages.outgoing.where(sender_type: 'User', private: false).where('created_at > ?', @run.created_at).exists?
  end

  def pause!
    @run.update!(status: 'paused', error: 'Fluxo pausado, alterado ou atendimento assumido por uma pessoa.', finished_at: Time.current)
    nil
  end
end

JrcFlows::WorkflowRunner.prepend(JrcFlows::OwnershipEntrypoints::WorkflowRunner)
