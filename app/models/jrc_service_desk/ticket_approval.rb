# frozen_string_literal: true

class JrcServiceDesk::TicketApproval < JrcServiceDesk::TicketRecord
  STATUSES = %w[pending approved rejected returned].freeze
  scope :pending, -> { where(status: 'pending') }
  belongs_to :requested_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :approver_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :approver_team, class_name: '::Team', optional: true
  belongs_to :decided_by_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :escalated_by_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :deadline_rule_version, class_name: 'JrcServiceDesk::OperationalRuleVersion', optional: true
  attr_accessor :authorized_escalation
  validates :title, presence: true, length: { maximum: 255 }
  validates :due_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :comment, presence: true, if: -> { %w[rejected returned].include?(status) }
  validates :idempotency_key, presence: true, uniqueness: { scope: %i[account_id unit_id ticket_id requested_by_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :references_are_consistent
  validate :target_is_explicit
  validate :history_is_append_only
  validate :request_is_immutable, on: :update

  private

  def references_are_consistent
    %i[requested_by_membership approver_membership decided_by_membership escalated_by_membership].each { |key| validate_unit_reference(key) }
    validate_account_reference(:approver_team)
    validate_unit_reference(:deadline_rule_version)
    errors.add(:deadline_rule_version, 'has the wrong rule family') if deadline_rule_version && deadline_rule_version.kind != 'approval_deadline'
  end

  def request_is_immutable
    immutable = %w[title description requested_by_membership_id idempotency_key request_fingerprint deadline_rule_version_id]
    immutable += %w[due_at approver_membership_id approver_team_id approver_role approver_custom_role_id] unless authorized_escalation
    immutable.each do |key|
      errors.add(key, 'is immutable') if will_save_change_to_attribute?(key)
    end
    errors.add(:status, 'has already been decided') if status_in_database != 'pending' && changed?
  end

  def target_is_explicit
    values = [approver_membership_id, approver_team_id, approver_role, approver_custom_role_id].compact
    errors.add(:approver_membership, 'requires exactly one explicit person, team or role') unless values.size == 1
    errors.add(:approver_role, 'is unsupported') if approver_role && %w[agent administrator].exclude?(approver_role)
    return unless approver_custom_role_id

    valid = defined?(CustomRole) && CustomRole.exists?(account_id: account_id, id: approver_custom_role_id)
    errors.add(:approver_custom_role_id, 'must belong to this account') unless valid
  end

  def history_is_append_only
    original = persisted? ? history_in_database : []
    valid = history.is_a?(Array) && history.size <= 1000 && history.first(original.size) == original
    errors.add(:history, 'must preserve all prior decisions and escalations') unless valid
  end
end
