class JrcRelationship::ConfigurationVersion < ApplicationRecord
  self.table_name = 'jrc_relationship_configuration_versions'
  belongs_to :account
  belongs_to :configuration, class_name: 'JrcRelationship::Configuration'
  belongs_to :actor, class_name: 'User', optional: true
  validates :version, uniqueness: { scope: :configuration_id }, numericality: { only_integer: true, greater_than: 0 }
  validate do
    errors.add(:configuration, 'must belong to account') if configuration && configuration.account_id != account_id
    errors.add(:actor, 'must belong to account') if actor && !account.users.exists?(actor.id)
  end

  def readonly?
    persisted?
  end
end
