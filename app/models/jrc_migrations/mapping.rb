class JrcMigrations::Mapping < ApplicationRecord
  self.table_name = 'jrc_migration_mappings'
  belongs_to :account
  belongs_to :batch, class_name: 'JrcMigrations::Batch'
  belongs_to :accepted_by, class_name: 'User', optional: true
  attr_readonly :account_id, :source, :domain, :legacy_id, :target_id
end
