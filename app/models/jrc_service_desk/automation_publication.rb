# frozen_string_literal: true

# Immutable composition of native lifecycle, rules, queue OLA and notifications.
# Execution continues to read the existing engines and their immutable versions.
class JrcServiceDesk::AutomationPublication < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :published_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :service, class_name: 'JrcServiceDesk::Service', optional: true
  validates :kind, inclusion: { in: %w[lifecycle operational] }
  validates :code, format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}\z/ }
  validates :name, length: { in: 1..255 }
  validates :description, length: { maximum: 4000 }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[account_id unit_id kind code] }
  validates :enabled, inclusion: { in: [true, false] }
  validate do
    validate_unit_reference(:service) if service
    validate_unit_reference(:published_by_membership)
    validate_actor_reference(:published_by_membership)
    errors.add(:digest, 'does not match publication') unless digest == expected_digest
  end

  def expected_digest
    JrcServiceDesk::CanonicalJson.digest(attributes.slice('kind', 'code', 'name', 'description', 'service_id', 'version', 'enabled', 'definition', 'native_versions'))
  end
end
