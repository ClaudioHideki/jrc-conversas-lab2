# frozen_string_literal: true

# An additional intersection with the same native corporate record scope, never a new grant.
class JrcContactCenter::QualificationFormVisibility
  def self.authorize!(row, account:, member:)
    raise ActiveRecord::RecordNotFound unless row.account_id == account.id && member.account_id == account.id

    native = JrcContactCenter::OrganizationalScope.new(account: account, account_user: member)
    native.records(JrcContactCenter::QualificationForm.where(account: account), unit_column: :unit_id, queue_column: :queue_id).find(row.id)
  end
end
