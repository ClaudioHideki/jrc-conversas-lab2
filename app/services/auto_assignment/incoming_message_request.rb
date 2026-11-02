class AutoAssignment::IncomingMessageRequest
  pattr_initialize [:message!]

  def perform
    return unless message.incoming? && !message.private?
    return if message.content_attributes.to_h['jrc_flow_run_id']

    conversation = Conversation.find_by(account_id: message.account_id, inbox_id: message.inbox_id, id: message.conversation_id)
    return unless conversation

    mode = record_request(conversation)
    case mode
    when :human
      JrcHumanAssignment::DispatchJob.perform_later(conversation.account_id)
    when :v2
      AutoAssignment::AssignmentJob.enqueue_for_inbox(conversation.inbox_id)
    when :legacy
      AutoAssignment::IncomingAssignmentJob.perform_later(conversation.account_id, conversation.id)
    end
  end

  private

  def record_request(conversation)
    conversation.account.with_lock do
      conversation.with_lock do
        next unless conversation.open? && conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil?

        inbox = conversation.inbox.reload
        next unless AutoAssignment::Eligibility.new(inbox: inbox).configuration_reason.nil?

        conversation.update!(auto_assignment_requested_at: Time.current)
        if JrcHumanAssignment::Policy.enabled_for?(inbox.account, inbox.id)
          :human
        else
          inbox.auto_assignment_v2_enabled? ? :v2 : :legacy
        end
      end
    end
  end
end
