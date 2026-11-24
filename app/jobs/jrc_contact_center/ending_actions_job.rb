# frozen_string_literal: true

# One committed native qualification, bounded by its immutable rule catalogue.
# Each destination/attempt owns its transaction and result; no batch transaction
# can undo an earlier success or borrow the event/configuration manager's role.
class JrcContactCenter::EndingActionsJob < ApplicationJob
  queue_as :default

  def perform(account_id, qualification_id)
    account = Account.find(account_id)
    return unless account.active? && account.feature_enabled?('jrc_contact_center')

    attempts = JrcContactCenter::EndingActions::InitialProjectAttempts.new(account: account, qualification_id: qualification_id).call
    attempts.each do |attempt|
      JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: attempt.id).call
    end
    attempts.length
  end
end
