# frozen_string_literal: true

# A Service Desk work queue, not a voice queue and not an access grant.
class JrcServiceDesk::Queue < JrcServiceDesk::NamedUnitRecord
  belongs_to :team, class_name: '::Team', optional: true
  belongs_to :current_policy_version, class_name: 'JrcServiceDesk::QueuePolicyVersion', optional: true
  has_many :policy_versions, class_name: 'JrcServiceDesk::QueuePolicyVersion', dependent: :restrict_with_error
  validate :independent_ola_settings
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error

  validate :team_account_is_consistent
  validate :used_queue_team_is_stable, on: :update
  validates :distribution_mode, inclusion: { in: %w[manual round_robin least_load skill priority_sla] }
  validate :required_skills_are_explicit
  validates :ola_budget_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :ola_settings_are_explicit
  validate :ola_escalation_is_scoped

  private

  def ola_escalation_is_scoped
    policy = JrcServiceDesk::ClockEscalationPolicy.new(ola_escalation_policy)
    JrcServiceDesk::ClockAutomationAuthority.verify!(policy, account: account, unit: unit)
    policy.thresholds.each do |row|
      Array(row['notification_member_ids']).each do |id|
        member = account.account_users.find(id)
        recipient_context = JrcServiceDesk::OperationalContext.new(account: account, user: member.user, account_user: member)
        unless recipient_context.unit_allowed?(unit) && recipient_context.capability?(:sla_view)
          errors.add(:ola_escalation_policy,
                     'recipient must be authorized in this unit')
        end
      end
      target = JrcServiceDesk::Queue.find_by(account_id: account_id, unit_id: unit_id, id: row['queue_id'], active: true) if row['queue_id']
      errors.add(:ola_escalation_policy, 'requires an active queue in this unit') if row['queue_id'] && !target
      if row['team_id'] && (!Team.exists?(account_id: account_id, id: row['team_id']) || target&.team_id != row['team_id'])
        errors.add(:ola_escalation_policy, 'team must match the scoped queue')
      end
    end
  rescue ArgumentError, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    errors.add(:ola_escalation_policy, 'requires an explicit supported policy')
  end

  def independent_ola_settings
    unless ola_targets.is_a?(Hash) && (ola_targets.keys - %w[first_response update resolution]).empty? &&
           ola_targets.values.all? { |n| n.is_a?(Integer) && n.positive? && n <= 31_536_000 }
      errors.add(:ola_targets, 'requires supported positive internal budgets')
    end
    return if ola_targets.blank?

    errors.add(:ola_time_basis, 'must select a time basis') unless %w[calendar business].include?(ola_time_basis)
    if ola_time_basis == 'business'
      JrcServiceDesk::SnapshotCalendar.new(timezone: ola_calendar.fetch('timezone'), conditions: ola_calendar.fetch('conditions'))
    end
  rescue KeyError, ArgumentError, JrcServiceDesk::LifecycleDependencyError
    errors.add(:ola_calendar, 'requires an explicit valid calendar snapshot')
  end

  def ola_settings_are_explicit
    return unless ola_budget_seconds

    errors.add(:ola_time_basis, 'must explicitly select calendar or business') unless %w[calendar business].include?(ola_time_basis)
  end

  def required_skills_are_explicit
    errors.add(:required_skills, 'must contain unique skill codes') unless JrcServiceDesk::SkillCodes.valid?(required_skills)
  end

  def team_account_is_consistent
    validate_account_reference(:team)
  end

  def used_queue_team_is_stable
    return unless will_save_change_to_team_id? && tickets.exists?

    errors.add(:team, 'cannot change while tickets reference the queue')
  end
end
