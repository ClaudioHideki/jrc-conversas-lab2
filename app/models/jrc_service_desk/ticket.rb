# frozen_string_literal: true

class JrcServiceDesk::Ticket < JrcServiceDesk::UnitRecord
    include JrcRelationship::SignalDispatch
  include JrcCustomers::OperationalCompanyLink
  belongs_to :requester, class_name: '::Contact', optional: false
  belongs_to :status, class_name: 'JrcServiceDesk::TicketStatus', optional: false
  belongs_to :priority, class_name: 'JrcServiceDesk::Priority', optional: false
  belongs_to :category, class_name: 'JrcServiceDesk::Category', optional: true
  belongs_to :queue, class_name: 'JrcServiceDesk::Queue', optional: true
  belongs_to :team, class_name: '::Team', optional: true
  belongs_to :assignee_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :created_by_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false

  belongs_to :service, class_name: 'JrcServiceDesk::Service', optional: true
  belongs_to :lifecycle_policy_version, class_name: 'JrcServiceDesk::LifecyclePolicyVersion', optional: true
  has_many :lifecycle_transitions, class_name: 'JrcServiceDesk::LifecycleTransition', dependent: :restrict_with_error
  has_many :sla_cycles, class_name: 'JrcServiceDesk::SlaCycle', dependent: :restrict_with_error
  has_many :lifecycle_pauses, class_name: 'JrcServiceDesk::LifecyclePause', dependent: :restrict_with_error
  validate :lifecycle_binding_integrity

  has_many :ticket_events, class_name: 'JrcServiceDesk::TicketEvent', dependent: :restrict_with_error
  has_many :ticket_notes, class_name: 'JrcServiceDesk::TicketNote', dependent: :restrict_with_error
  has_many :sla_snapshots, class_name: 'JrcServiceDesk::SlaSnapshot', dependent: :restrict_with_error
  has_many :sla_milestones, class_name: 'JrcServiceDesk::SlaMilestone', dependent: :restrict_with_error
  has_many :ticket_conversations, class_name: 'JrcServiceDesk::TicketConversation', dependent: :restrict_with_error

  validates :title, presence: true, length: { maximum: 255 }
  validates :origin_channel, presence: true, length: { maximum: 80 }
  validates :opened_at, presence: true
  validates :idempotency_key, presence: true, length: { maximum: 120 },
                               uniqueness: { scope: %i[account_id unit_id created_by_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :references_are_consistent
  validate :queue_team_is_consistent
  validate :initial_status_required, on: :create

  # No duplicated operator_company_id column, no fallback unit, no Project relation.
  def operator_company
    unit&.operator_company
  end

  def operator_company_id
    unit&.operator_company_id
  end

  def assignee_account_user
    assignee_membership&.account_user
  end

  def latest_sla_snapshot
    sla_snapshots.order(version: :desc).first
  end

  protected

  def ownership_columns
    super + %i[service_id created_by_membership_id idempotency_key request_fingerprint origin_channel opened_at]
  end

  private

  def lifecycle_binding_integrity
    validate_unit_reference(:service)
    validate_unit_reference(:lifecycle_policy_version)
    validate_active_reference(:service)
    if lifecycle_policy_version_id_in_database && will_save_change_to_lifecycle_policy_version_id?
      errors.add(:lifecycle_policy_version_id, 'cannot replace the historical version')
    end
    return unless lifecycle_policy_version
    scoped_service = lifecycle_policy_version.lifecycle_policy.service_id
    errors.add(:lifecycle_policy_version, 'service scope does not match') if scoped_service && scoped_service != service_id
  end

  def references_are_consistent
    %i[requester team].each { |name| validate_account_reference(name) }
    %i[status priority category queue assignee_membership created_by_membership].each do |name|
      validate_unit_reference(name)
      validate_active_reference(name)
    end
  end

  def queue_team_is_consistent
    return unless queue&.team_id

    errors.add(:team, 'must match the selected queue') unless team_id == queue.team_id
  end

  def initial_status_required
    return if status&.initial? && status&.active? && status&.phase == 'open'

    errors.add(:status, 'must be an explicitly configured active initial status')
  end
end
