# frozen_string_literal: true

# Native unit grants and audit-only administrative actors; neither stores roles or capabilities.
class JrcServiceDesk::UnitMembership < JrcServiceDesk::UnitRecord
  belongs_to :account_user, class_name: '::AccountUser', optional: false
  belongs_to :team, class_name: '::Team', optional: true
  belongs_to :queue, class_name: 'JrcServiceDesk::Queue', optional: true

  scope :operational, -> { where(administrative_actor: false) }

  validates :account_user_id, uniqueness: { scope: %i[account_id unit_id administrative_actor] }
  validates :administrative_actor, inclusion: { in: [true, false] }
  validate :administrative_actor_is_audit_only
  validates :active, inclusion: { in: [true, false] }
  validate :account_user_is_consistent
  validates :availability, inclusion: { in: %w[available paused unavailable] }
  validates :capacity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }, allow_nil: true
  validate :skills_are_explicit
  validates :manual_assignment_enabled, :restricted_supervision, inclusion: { in: [true, false] }
  validate :operational_domain_is_consistent
  validate :supervision_is_explicit

  protected

  def ownership_columns
    super + %i[account_user_id administrative_actor]
  end

  def account_user_is_consistent
    validate_account_reference(:account_user)
  end

  def administrative_actor_is_audit_only
    return unless administrative_actor?

    errors.add(:administrative_actor, 'cannot grant operational availability or capacity') unless active == false && availability == 'unavailable' && capacity.nil? && skills == []
    return unless new_record?

    native = account_user && JrcServiceDesk::OperationalContext.new(account: account, user: account_user.user, account_user: account_user)
    errors.add(:administrative_actor, 'requires the current native Account administrator') unless native&.administrator? && native.native_operator?
  end

  def skills_are_explicit
    errors.add(:skills, 'must contain unique skill codes') unless JrcServiceDesk::SkillCodes.valid?(skills)
  end

  def operational_domain_is_consistent
    validate_account_reference(:team)
    validate_unit_reference(:queue)
    errors.add(:team, 'must match the selected queue') if queue && queue.team_id != team_id
    return unless administrative_actor? && (team_id || queue_id || restricted_supervision? || supervision_grants != [])

    errors.add(:administrative_actor, 'cannot be configured as an operational member')
  end

  def supervision_is_explicit
    normalized = JrcServiceDesk::SupervisionAccess.normalize(supervision_grants)
    errors.add(:supervision_grants, 'require restricted supervision') if normalized.any? && !restricted_supervision?
    normalized.each do |grant|
      target = JrcServiceDesk::Queue.find_by(account_id: account_id, unit_id: unit_id, id: grant['queue_id'], active: true)
      unless target&.team_id == grant['team_id'] && Team.exists?(account_id: account_id, id: grant['team_id'])
        errors.add(:supervision_grants, 'require an active queue and its exact team in this unit')
      end
    end
  rescue ArgumentError, KeyError
    errors.add(:supervision_grants, 'require explicit queues, teams and supported permissions')
  end
end
