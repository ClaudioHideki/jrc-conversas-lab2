class JrcFlows::Delivery
  def initialize(message)
    @message = message
    # A newly created conversation may still carry a dirty, callback-assigned display_id.
    # Delivery locks persisted state without modifying the caller's association.
    @conversation = Conversation.find(message.conversation_id)
  end

  def perform(&)
    claimed = with_managed_sources do
      @conversation.with_lock { claim! }
    end
    return unless claimed

    # Claim is committed before external I/O. Uncertain sends are never retried automatically.
    with_managed_sources do
      @conversation.with_lock { dispatch!(&) }
    end
  rescue StandardError => e
    Rails.logger.warn("JRC Flows delivery=#{@message.id} failed: #{e.class}")
    mark!('unknown', failed: true)
  end

  private

  def claim!
    @message.reload
    return false unless @message.content_attributes['jrc_flow_delivery'] == 'queued'

    unless allowed?
      mark!('cancelled', failed: true)
      return false
    end
    mark!('dispatching')
    true
  end

  def dispatch!
    unless allowed?
      mark!('cancelled', failed: true)
      return
    end
    yield
    @message.reload
    mark!(@message.failed? ? 'failed' : 'channel_processed')
  end

  def with_managed_sources(&)
    run = JrcFlowRun.find_by(id: @message.content_attributes['jrc_flow_run_id'])
    return yield unless run && JrcRelationship::PlaybookFlowContinuation.managed?(run)

    JrcRelationship::PlaybookFlowContinuation.with_sources(run, &)
  rescue JrcRelationship::PlaybookFlowSourceDenied
    mark!('cancelled', failed: true)
    false
  end

  def eligible_run
    run = JrcFlowRun.find_by(id: @message.content_attributes['jrc_flow_run_id'],
                             account_id: @message.account_id, conversation_id: @conversation.id)
    return unless run && %w[running waiting delayed completed].include?(run.status)
    return unless JrcRelationship::PlaybookFlowContinuation.delivery_allowed?(run)

    run
  end

  def allowed?
    run = eligible_run
    return false unless run

    return false if JrcFlows::Access.inbox_bot_owned?(@conversation)
    return false unless run.flow.status == 'active' && run.flow.lock_version == run.settings['_flow_version']
    return false unless JrcFlows::Access.enabled?(run.account) && run.account.account_users.exists?(user_id: run.flow.created_by_id,
                                                                                                    role: 'administrator')
    return false if @conversation.messages.outgoing.where(sender_type: 'User', private: false).where('id > ?', @message.id).exists?

    # A handoff performed by this exact flow may precede delivery of its last message.
    final = run.graph['nodes'].find { |node| node['id'] == run.trace.last&.fetch('node_id', nil) }
    own_assignment = run.status == 'completed' && final&.fetch('type') == 'assign' &&
                     (final['data']['agent_id'].blank? || final['data']['agent_id'].to_i == @conversation.assignee_id) &&
                     (final['data']['team_id'].blank? || final['data']['team_id'].to_i == @conversation.team_id)
    own_assignment ||= run.status == 'completed' && run.flow.engine == 'workflow' &&
                       run.variables['_workflow_handoff_team'].present? && run.variables['_workflow_handoff_team'] == @conversation.team_id
    if @conversation.assignee_agent_bot_id.present?
      return run.status == 'completed' && final&.fetch('type') == 'nico' &&
             JrcNico::Delegation.exists?(conversation: @conversation, user_id: delegation_actor_id(run),
                                         agent_bot_id: @conversation.assignee_agent_bot_id, status: 'active')
    end
    return false if run.settings.fetch('pause_on_agent', true) && @conversation.assignee_id.present? && !own_assignment
    return false if run.settings.fetch('pause_on_team', false) && @conversation.team_id.present? && !own_assignment

    true
  end

  def delegation_actor_id(run)
    return run.flow.created_by_id unless JrcRelationship::PlaybookFlowContinuation.managed?(run)

    JrcRelationship::PlaybookFlowRunContext.new(run).authorize!.reference.context.user.id
  end

  def mark!(state, failed: false)
    attrs = @message.reload.content_attributes.to_h.merge('jrc_flow_delivery' => state)
    attrs['external_error'] = 'Flow: envio cancelado ou resultado de entrega não confirmado.' if failed
    @message.update!(content_attributes: attrs, **(failed ? { status: :failed } : {}))
  end
end
