class AutoAssignment::IncomingAssignmentJob < ApplicationJob
  queue_as :default

  def perform(account_id, conversation_id)
    account = Account.find_by(id: account_id)
    return unless account

    account.with_lock do
      conversation = account.conversations.find_by(id: conversation_id)
      next unless conversation

      conversation.with_lock do
        next unless conversation.auto_assignment_requested_at.present?

        allowed_ids = conversation.inbox.member_ids_with_assignment_capacity
        allowed_ids &= conversation.team.members.ids if conversation.team_id.present?
        AutoAssignment::AgentAssignmentService.new(conversation: conversation, allowed_agent_ids: allowed_ids).perform
      end
    end
  end
end
