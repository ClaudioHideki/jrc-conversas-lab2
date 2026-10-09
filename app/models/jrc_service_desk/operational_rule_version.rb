# frozen_string_literal: true

class JrcServiceDesk::OperationalRuleVersion < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly

  belongs_to :published_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  validates :kind, inclusion: { in: JrcServiceDesk::OperationalRuleContract::KINDS }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[account_id unit_id kind] }
  validates :enabled, inclusion: { in: [true, false] }
  validate :configuration_contract
  validate :publisher_scope

  def self.current(account_id:, unit_id:, kind:)
    where(account_id: account_id, unit_id: unit_id, kind: kind).order(version: :desc).first
  end

  def expected_digest
    JrcServiceDesk::CanonicalJson.digest('kind' => kind, 'enabled' => enabled, 'definition' => definition)
  end

  private

  def publisher_scope
    validate_unit_reference(:published_by_membership)
    validate_active_reference(:published_by_membership)
  end

  def configuration_contract
    JrcServiceDesk::OperationalRuleContract.validate!(kind, definition)
    errors.add(:digest, 'does not match the published configuration') unless digest == expected_digest
  rescue ArgumentError, KeyError
    errors.add(:definition, 'has invalid or incomplete operational rules')
  end
end
