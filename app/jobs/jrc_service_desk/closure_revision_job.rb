# frozen_string_literal: true

# Only authenticated native identity IDs and an audited key are serialized.
# resume rechecks current capabilities, policy versions, unit and each ticket.
class JrcServiceDesk::ClosureRevisionJob < ApplicationJob
  queue_as :default

  def perform(account_id, account_user_id, user_id, unit_id, batch_id)
    account = Account.find(account_id)
    membership = AccountUser.find_by!(id: account_user_id, account_id: account.id, user_id: user_id)
    context = { account: account, account_user: membership, user: membership.user }
    JrcServiceDesk::ClosureRevisionService.new(user_context: context).resume(unit_id: unit_id, idempotency_key: batch_id)
  end
end
