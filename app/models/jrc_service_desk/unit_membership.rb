# frozen_string_literal: true

# Only an operational scope grant. There are deliberately no roles/permissions here.
class JrcServiceDesk::UnitMembership < JrcServiceDesk::UnitRecord
  belongs_to :account_user, class_name: '::AccountUser', optional: false

  validates :account_user_id, uniqueness: { scope: %i[account_id unit_id] }
  validates :active, inclusion: { in: [true, false] }
  validate :account_user_is_consistent
  validates :availability, inclusion: { in: %w[available paused unavailable] }
  validates :capacity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }, allow_nil: true
  validate :skills_are_explicit

  protected

  def ownership_columns
    super + [:account_user_id]
  end

  def account_user_is_consistent
    validate_account_reference(:account_user)
  end

  def skills_are_explicit
    errors.add(:skills, 'must contain unique skill codes') unless JrcServiceDesk::SkillCodes.valid?(skills)
  end
end
