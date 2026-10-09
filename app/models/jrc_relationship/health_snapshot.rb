class JrcRelationship::HealthSnapshot < ApplicationRecord
  self.table_name = 'jrc_relationship_health_snapshots'
  belongs_to :account
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  belongs_to :viewer, class_name: 'User'
  validates :band, :fingerprint, :calculated_at, :config_scope_key, :config_version, presence: true
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  def readonly?
    persisted?
  end
  validate do
    errors.add(:assignment, 'wrong account') if assignment.account_id != account_id
    errors.add(:viewer, 'wrong account') unless account.users.exists?(viewer_id)
  end
end
