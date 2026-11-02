# frozen_string_literal: true

class JrcServiceDesk::Incident < JrcServiceDesk::UnitRecord
  STATUSES = JrcServiceDesk::IncidentWorkflow::STATUSES
  belongs_to :created_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :primary_ticket, class_name: 'JrcServiceDesk::Ticket', optional: true
  belongs_to :owner_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :service, class_name: 'JrcServiceDesk::Service', optional: true
  belongs_to :category, class_name: 'JrcServiceDesk::Category', optional: true
  has_many :incident_entries, class_name: 'JrcServiceDesk::IncidentEntry', dependent: :restrict_with_error
  has_many :resource_links, class_name: 'JrcServiceDesk::CaseResourceLink', dependent: :restrict_with_error
  has_many :case_links, class_name: 'JrcServiceDesk::CaseLink', dependent: :restrict_with_error
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error
  validates :title, presence: true, length: { maximum: 255 }
  validates :severity, inclusion: { in: %w[low normal high critical] }
  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true
  validates :resource_kind, inclusion: { in: %w[incident problem] }
  validates :idempotency_key, presence: true, uniqueness: { scope: %i[account_id unit_id created_by_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :references_are_consistent
  validate do
    JrcServiceDesk::CaseInput.call({ 'details' => details })
    errors.add(:resolved_at, 'cannot precede the start') if resolved_at && started_at && resolved_at < started_at
    errors.add(:closed_at, 'cannot precede resolution') if closed_at && resolved_at && closed_at < resolved_at
  rescue ArgumentError
    errors.add(:details, 'invalid analysis fields')
  end

  private

  def references_are_consistent
    %i[created_by_membership primary_ticket owner_membership service category].each { |key| validate_unit_reference(key) }
  end

  protected

  def ownership_columns
    super + %i[resource_kind created_by_membership_id idempotency_key request_fingerprint]
  end
end
