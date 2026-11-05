class JrcHumanAssignment::DispatchJob < ApplicationJob
  queue_as :default
  BATCH_SIZE = 100

  def perform(account_id, after_id = 0, after_requested_at = nil)
    account = Account.find_by(id: account_id)
    return unless account&.active? && JrcHumanAssignment::Policy.enabled?(account)

    scope = account.conversations.open.where(assignee_id: nil, assignee_agent_bot_id: nil)
                   .where.not(auto_assignment_requested_at: nil)
                   .where(inbox_id: JrcHumanAssignment::Policy.enabled_inbox_ids(account))
    # Accept old queued jobs carrying only an ID; recovery starts a fresh scan.
    if after_requested_at
      scope = scope.where('(auto_assignment_requested_at, id) > (?, ?)', Time.iso8601(after_requested_at), after_id)
    elsif after_id.positive?
      scope = scope.where('id > ?', after_id)
    end
    batch = scope.reorder(auto_assignment_requested_at: :asc, id: :asc).limit(BATCH_SIZE).to_a
    cursor = batch.last && [batch.last.id, batch.last.auto_assignment_requested_at.iso8601(6)]
    batch.each do |conversation|
      JrcHumanAssignment::Dispatch.new(conversation).perform
    end
    self.class.perform_later(account.id, *cursor) if batch.size == BATCH_SIZE
  end
end
