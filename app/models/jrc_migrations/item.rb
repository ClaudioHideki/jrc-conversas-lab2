class JrcMigrations::Item < ApplicationRecord
  self.table_name = 'jrc_migration_items'
  belongs_to :account
  belongs_to :batch, class_name: 'JrcMigrations::Batch'
  attr_readonly :account_id, :batch_id, :legacy_id, :raw_data, :normalized_data, :source_digest
end
