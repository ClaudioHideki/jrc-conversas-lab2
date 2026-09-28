# frozen_string_literal: true

class JrcServiceDesk::LifecyclePolicyVersion < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :lifecycle_policy, class_name: 'JrcServiceDesk::LifecyclePolicy', optional: false
  belongs_to :actor_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :lifecycle_policy_id }
  validates :digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :valid_definition

  def expected_digest
    JrcServiceDesk::CanonicalJson.digest('definition' => definition, 'status_phases' => status_phases, 'publication' => publication)
  end

  def rules
    JrcServiceDesk::LifecycleRules.new(definition)
  end

  private

  def valid_definition
    validate_unit_reference(:lifecycle_policy)
    validate_unit_reference(:actor_membership)
    validate_active_reference(:actor_membership)
    rules
    raise ArgumentError unless publication.is_a?(Hash) && publication.keys.sort == %w[enabled name service_id].sort && [true, false].include?(publication['enabled']) && publication['name'].is_a?(String)
    raise ArgumentError unless status_phases.is_a?(Hash) && status_phases.any? && status_phases.values.all? { |v| JrcServiceDesk::LifecycleRules::PHASES.include?(v) }
    errors.add(:digest, 'does not match immutable policy') unless digest == expected_digest
  rescue ArgumentError, KeyError
    errors.add(:definition, 'must be a complete supported lifecycle policy')
  end
end
