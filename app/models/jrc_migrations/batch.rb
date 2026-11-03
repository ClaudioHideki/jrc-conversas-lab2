class JrcMigrations::Batch < ApplicationRecord
  self.table_name = 'jrc_migration_batches'
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  belongs_to :accepted_by, class_name: 'User', optional: true
  has_many :items, class_name: 'JrcMigrations::Item', inverse_of: :batch, dependent: :restrict_with_exception
  has_many :events, class_name: 'JrcMigrations::Event', inverse_of: :batch, dependent: :restrict_with_exception
  attr_readonly :account_id, :source, :domain, :version, :field_mapping, :source_digest, :file_name, :created_by_id
end
