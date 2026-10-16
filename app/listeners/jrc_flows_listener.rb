class JrcFlowsListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return if message.private? || message.activity? || message.content_attributes.to_h['jrc_flow_run_id']

    if message.outgoing? && message.sender_type == 'User'
      stop_runs(message.conversation, 'Atendente enviou uma mensagem.')
    elsif message.incoming?
      dispatch(message.conversation, 'message_created', "message:#{message.id}", message.id)
    end
  end

  def conversation_created(event)
    conversation = event.data[:conversation]
    dispatch(conversation, 'conversation_created', "created:#{conversation.id}")
  end

  def conversation_opened(event)
    return if event.data[:performed_by].is_a?(JrcFlowRun)

    conversation = event.data[:conversation]
    dispatch(conversation, 'conversation_opened', "opened:#{conversation.id}:#{event.timestamp.to_f}")
  end

  def conversation_resolved(event)
    conversation = event.data[:conversation]
    stop_runs(conversation, 'Conversa resolvida.')
    JrcFlowRun.where(conversation: conversation).update_all(reset_at: Time.current)
    return if event.data[:performed_by].is_a?(JrcFlowRun)

    dispatch(conversation, 'conversation_resolved', "resolved:#{conversation.id}:#{event.timestamp.to_f}")
  end

  def conversation_updated(event)
    conversation = event.data[:conversation]
    return if event.data[:performed_by].is_a?(JrcFlowRun)

    changes = event.data[:changed_attributes].to_h.with_indifferent_access
    if changes.key?(:assignee_id) || changes.key?(:team_id) || changes.key?(:assignee_agent_bot_id)
      conversation.reload
      JrcFlowRun.live.where(conversation: conversation).find_each do |run|
        if conversation.assignee_agent_bot_id.present? ||
           (run.settings.fetch('pause_on_agent', true) && conversation.assignee_id.present?) ||
           (run.settings.fetch('pause_on_team', false) && conversation.team_id.present?)
          stop_runs(conversation, 'Atendimento atribuído.')
          break
        end
      end
    end
    before_labels, after_labels = changes[:label_list]
    return unless before_labels.is_a?(Array) && after_labels.is_a?(Array)

    (after_labels - before_labels).each do |label|
      dispatch(conversation, 'label_added', "label:#{conversation.id}:#{event.timestamp.to_f}:#{label}", nil, label)
    end
  end

  private

  def dispatch(conversation, name, key, message_id = nil, label = nil)
    return unless JrcFlows::Access.enabled?(conversation.account)

    JrcFlows::DispatchJob.perform_later(conversation.account_id, conversation.id, name, key, message_id, label)
  end

  def stop_runs(conversation, reason)
    conversation.with_lock do
      JrcFlowRun.live.where(conversation: conversation).update_all(status: 'paused', error: reason, finished_at: Time.current, wake_at: nil)
    end
  end
end

JrcFlowsListener.prepend(JrcFlows::OwnershipEntrypoints::Listener)
