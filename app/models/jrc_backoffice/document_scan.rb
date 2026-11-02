# A technical observation of exact bytes, never identity/representation approval.
class JrcBackoffice::DocumentScan < ApplicationRecord
  self.table_name = 'jrc_backoffice_document_scans'
  belongs_to :account
  belongs_to :document_version, class_name: 'JrcBackoffice::DocumentVersion'
  belongs_to :source_blob, class_name: 'ActiveStorage::Blob'
  validates :attempt, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :document_version_id }
  validates :state, inclusion: { in: %w[clean infected unavailable checksum_mismatch] }
  validates :expected_sha256, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :observed_sha256, format: { with: /\A[a-f0-9]{64}\z/ }, allow_nil: true
  validates :scanner_adapter, inclusion: { in: ['clamav-instream-v1'] }
  validate :consistent_source
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Document security observations are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Document security observations are immutable' }

  def clean?
    state == 'clean' && observed_sha256 == expected_sha256
  end

  private

  def consistent_source
    errors.add(:document_version, 'must match the account and exact attachment') unless matching_source?
    errors.add(:observed_sha256, 'must match the expected checksum') if state == 'clean' && observed_sha256 != expected_sha256
  end

  def matching_source?
    return false unless document_version && document_version.account_id == account_id && document_version.sha256 == expected_sha256

    document_version.file.attached? && document_version.file.blob.id == source_blob_id
  end
end
