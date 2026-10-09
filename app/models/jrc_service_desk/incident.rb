# frozen_string_literal: true

class JrcServiceDesk::Incident < JrcServiceDesk::UnitRecord
  STATUSES = %w[open investigating monitoring resolved].freeze
  belongs_to :created_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :primary_ticket, class_name: 'JrcServiceDesk::Ticket', optional: true
  belongs_to :owner_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error
  validates :title, presence: true, length: { maximum: 255 }
  validates :severity, inclusion: { in: %w[low normal high critical] }
  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true
  validates :resource_kind, inclusion: { in: %w[incident problem] }
  validates :idempotency_key, presence: true, uniqueness: { scope: %i[account_id unit_id created_by_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :references_are_consistent

  private

  def references_are_consistent
    %i[created_by_membership primary_ticket owner_membership].each { |key| validate_unit_reference(key) }
  end

  protected

  def ownership_columns
    super + %i[resource_kind created_by_membership_id idempotency_key request_fingerprint]
  end
end
