class JrcRelationship::RetentionCoverage < ApplicationRecord
  self.table_name = 'jrc_relationship_retention_coverages'
  belongs_to :account
  validates :account_id, uniqueness: true
  validates :started_at, presence: true
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Retention coverage cannot be backdated' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Retention coverage is immutable' }
end
