# frozen_string_literal: true

# Native local change/asset records, distinct from incidents and CRM products.
class JrcServiceDesk::OperationalResource < JrcServiceDesk::UnitRecord
  STATES = { 'change' => %w[requested planned approved in_progress completed cancelled],
             'asset' => %w[active inactive retired] }.transform_values(&:freeze).freeze
  belongs_to :created_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :owner_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  belongs_to :approval, class_name: 'JrcServiceDesk::TicketApproval', optional: true
  has_many :resource_ticket_links, class_name: 'JrcServiceDesk::ResourceTicketLink', dependent: :restrict_with_error
  has_many :tickets, through: :resource_ticket_links, class_name: 'JrcServiceDesk::Ticket'
  validates :name, presence: true, length: { maximum: 255 }
  validates :code, length: { maximum: 80 }, uniqueness: { scope: %i[account_id unit_id resource_kind] }, allow_nil: true
  validates :resource_kind, inclusion: { in: STATES.keys }
  validates :priority, inclusion: { in: %w[low normal high critical] }
  validates :idempotency_key, presence: true, uniqueness: { scope: %i[account_id unit_id created_by_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :operational_integrity
  validate :history_is_append_only

  protected

  def ownership_columns
    super + %i[resource_kind created_by_membership_id idempotency_key request_fingerprint code]
  end

  private

  def operational_integrity
    %i[created_by_membership owner_membership approval].each { |key| validate_unit_reference(key) }
    validate_account_reference(:company)
    errors.add(:state, 'must match the resource kind') unless STATES.fetch(resource_kind, []).include?(state)
    errors.add(:details, 'must be an explicit object') unless details.is_a?(Hash)
    errors.add(:approval, 'is only valid for a change') if approval && resource_kind != 'change'
    validate_planned_window
    validate_change_approval
  end

  def validate_planned_window
    invalid_window = planned_end_at && (!planned_start_at || planned_end_at <= planned_start_at)
    errors.add(:planned_end_at, 'must follow the explicit start') if invalid_window
    return unless planned_window_required?

    errors.add(:planned_start_at, 'requires an explicit planned window') unless planned_start_at && planned_end_at
  end

  def planned_window_required?
    resource_kind == 'change' && %w[planned approved in_progress completed].include?(state)
  end

  def validate_change_approval
    return unless resource_kind == 'change' && %w[approved in_progress completed].include?(state)

    errors.add(:approval, 'requires an approved native decision') unless approval&.status == 'approved'
  end

  def history_is_append_only
    original = persisted? ? history_in_database : []
    valid = history.is_a?(Array) && history.size <= 1000 && history.first(original.size) == original
    errors.add(:history, 'must preserve prior operations') unless valid
  end
end
