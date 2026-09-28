# frozen_string_literal: true

# Only an operational scope grant. There are deliberately no roles/permissions here.
class JrcServiceDesk::UnitMembership < JrcServiceDesk::UnitRecord
  belongs_to :account_user, class_name: '::AccountUser', optional: false

  validates :account_user_id, uniqueness: { scope: %i[account_id unit_id] }
  validates :active, inclusion: { in: [true, false] }
  validate :account_user_is_consistent

  protected

  def ownership_columns
    super + [:account_user_id]
  end

  def account_user_is_consistent
    validate_account_reference(:account_user)
  end
end
