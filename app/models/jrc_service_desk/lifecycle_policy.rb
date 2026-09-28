# frozen_string_literal: true

class JrcServiceDesk::LifecyclePolicy < JrcServiceDesk::UnitRecord
  belongs_to :service, class_name: 'JrcServiceDesk::Service', optional: true
  belongs_to :current_version, class_name: 'JrcServiceDesk::LifecyclePolicyVersion', optional: true
  has_many :versions, class_name: 'JrcServiceDesk::LifecyclePolicyVersion', dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 255 }
  validates :enabled, inclusion: { in: [true, false] }
  validates :service_id, uniqueness: { scope: %i[account_id unit_id] }
  validate :scope_integrity

  protected

  def ownership_columns
    super + [:service_id]
  end

  private

  def scope_integrity
    validate_unit_reference(:service)
    return unless current_version
    validate_unit_reference(:current_version)
    errors.add(:current_version, 'must belong to this policy') unless current_version.lifecycle_policy_id == id
  end
end
