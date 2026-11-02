class JrcBackoffice::ContractVersion < ApplicationRecord
  self.table_name = 'jrc_backoffice_contract_versions'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  belongs_to :account
  belongs_to :backoffice_request, class_name: 'JrcCrm::BackofficeRequest'
  belongs_to :contract, class_name: 'JrcCrm::Contract'
  belongs_to :created_by, class_name: 'User'
  belongs_to :pdf_blob, class_name: 'ActiveStorage::Blob'
  validates :number, :source_format_version, numericality: { only_integer: true, greater_than: 0 }
  validates :number, uniqueness: { scope: :contract_id }
  validates :idempotency_key, presence: true, uniqueness: { scope: :contract_id }
  validates :source_digest, :pdf_sha256, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :change_reason, presence: true, length: { maximum: 2000 }
  validate :consistent_origin
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Contract versions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Contract versions are immutable' }
  after_rollback(on: :create) { self.class.clean_uncommitted_pdf(pdf_blob) }

  def self.clean_uncommitted_pdf(blob)
    return unless blob && blob.metadata['jrc_contract_generated'] == true
    return if uncached { exists?(pdf_blob_id: blob.id) }
    return if blob.attachments.exists?

    if ActiveStorage::Blob.uncached { ActiveStorage::Blob.exists?(id: blob.id) }
      blob.purge
    else
      # Rollback restores a blob's new-record flag; native purge then skips
      # storage deletion. No persisted blob means the FK forbids a new owner.
      blob.service.delete(blob.key)
    end
  rescue StandardError => e
    # A failed existence check retains the PDF on uncertain database outcomes.
    # Cleanup errors must never replace the original failed operation.
    Rails.logger.warn("backoffice_contract_blob_cleanup_pending class=#{e.class.name}")
  end

  def snapshot
    JSON.parse(source_snapshot)
  end

  def serializable_hash(_options = nil)
    slice('id', 'contract_id', 'backoffice_request_id', 'number', 'source_format_version', 'source_digest',
          'pdf_sha256', 'change_reason', 'change_paths', 'created_by_id', 'created_at')
  end

  private

  def consistent_origin
    errors.add(:contract, 'must match the account and request') unless matching_origin?
    errors.add(:created_by, 'must belong to account') unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end

  def matching_origin?
    contract && backoffice_request && contract.account_id == account_id && backoffice_request.account_id == account_id &&
      backoffice_request.contract_id == contract_id && backoffice_request.sales_order_id == contract.sales_order_id
  end
end
