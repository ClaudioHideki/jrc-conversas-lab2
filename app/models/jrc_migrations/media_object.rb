class JrcMigrations::MediaObject < ApplicationRecord
  self.table_name = 'jrc_migration_media_objects'
  STATUSES = %w[reserved verifying verification_required planned attached recovering cleanup_required cleaned kept].freeze
  belongs_to :account
  belongs_to :batch, class_name: 'JrcMigrations::Batch'
  belongs_to :item, class_name: 'JrcMigrations::Item'
  belongs_to :blob, class_name: 'ActiveStorage::Blob', optional: true
  attr_readonly :account_id, :batch_id, :item_id, :generation, :service_name, :storage_key, :source_sha256, :byte_size, :storage_identity
  validates :status, inclusion: { in: STATUSES }
  validates :storage_key, format: { with: /\A[a-z0-9]{28}\z/ }
  validates :source_sha256, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :storage_identity, presence: true, on: :create
  validates :storage_identity, format: { with: /\A[a-f0-9]{64}\z/ }, allow_nil: true
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1.megabyte }
  validate :same_source

  def public_projection
    { id: id, status: status, generation: generation, byte_size: byte_size, error_code: error_code,
      scan_state: blob&.metadata&.fetch('service_desk_scan_state', 'unavailable') || 'unavailable',
      scannable: status == 'attached' && blob_id.present?, recoverable: %w[planned cleanup_required recovering].include?(status) }
  end

  private

  def same_source
    errors.add(:item, :invalid) unless item && item.account_id == account_id && item.batch_id == batch_id
    errors.add(:batch, :invalid) unless batch && batch.account_id == account_id
  end
end
