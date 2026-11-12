class JrcRelationship::RetentionState < ApplicationRecord
  self.table_name = 'jrc_relationship_retention_states'
  belongs_to :account
  validates :customer_key, :observed_at, :facts, presence: true
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Retention observations are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Retention observations are immutable' }
end
