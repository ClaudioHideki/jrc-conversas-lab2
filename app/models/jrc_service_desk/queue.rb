# frozen_string_literal: true

# A Service Desk work queue, not a voice queue and not an access grant.
class JrcServiceDesk::Queue < JrcServiceDesk::NamedUnitRecord
  belongs_to :team, class_name: '::Team', optional: true
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
      target = JrcServiceDesk::Queue.find_by(account_id: account_id, unit_id: unit_id, id: row['queue_id'], active: true) if row['queue_id']
      errors.add(:ola_escalation_policy, 'requires an active queue in this unit') if row['queue_id'] && !target
      if row['team_id'] && (!Team.exists?(account_id: account_id, id: row['team_id']) || target&.team_id != row['team_id'])
        errors.add(:ola_escalation_policy, 'team must match the scoped queue')
      end
    end
  rescue ArgumentError, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    errors.add(:ola_escalation_policy, 'requires an explicit supported policy')
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
