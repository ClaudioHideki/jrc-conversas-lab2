# frozen_string_literal: true

# Fixed model/argument boundary. Never call the qualification-wide legacy job
# for a single consent or retry: that would also execute unselected siblings.
class JrcContactCenter::EndingDestinationJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(account_id, attempt_id)
    account = Account.find(JrcServiceDesk::Input.id(account_id))
    identifier = JrcServiceDesk::Input.id(attempt_id)
    # Current account/source rights are checked by the actual executor. A
    # revoked grant records a terminal refusal instead of silently retaining
    # work which might later acquire authority after reactivation.
    JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: account, attempt_id: identifier).call
  end
end
