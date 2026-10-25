# frozen_string_literal: true

class JrcServiceDesk::QueuePolicyVersion < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :queue, class_name: 'JrcServiceDesk::Queue'
  belongs_to :published_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :queue_id }
  validates :digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate do
    validate_unit_reference(:queue)
    validate_actor_reference(:published_by_membership)
    errors.add(:digest, 'must match the immutable definition') unless digest == JrcServiceDesk::CanonicalJson.digest(definition)
  end
end
