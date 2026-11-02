class JrcHumanAssignment::DispatchJob < ApplicationJob
  queue_as :default
  BATCH_SIZE = 100

  def perform(account_id, after_id = 0)
    account = Account.find_by(id: account_id)
    return unless account&.active? && JrcHumanAssignment::Policy.enabled?(account)

    batch = account.conversations.open.where(assignee_id: nil, assignee_agent_bot_id: nil)
                   .where.not(auto_assignment_requested_at: nil)
                   .where(inbox_id: JrcHumanAssignment::Policy.for(account)[:inbox_ids])
                   .where.not(team_id: nil).where('id > ?', after_id).reorder(id: :asc).limit(BATCH_SIZE).to_a
    batch.each do |conversation|
      JrcHumanAssignment::Dispatch.new(conversation).perform
    end
    self.class.perform_later(account.id, batch.last.id) if batch.size == BATCH_SIZE
  end
end
