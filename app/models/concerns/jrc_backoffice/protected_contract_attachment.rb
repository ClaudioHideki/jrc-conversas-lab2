module JrcBackoffice::ProtectedContractAttachment
  extend ActiveSupport::Concern
  included do
    validate :reject_relinking_contract_version
    before_update :preserve_backoffice_document_file
    before_destroy :preserve_backoffice_document_file
  end

  private

  def reject_relinking_contract_version
    return unless blob_id

    errors.add(:blob, 'must be accessed through the scoped Backoffice API') if JrcBackoffice::PrivateBlob.protected?(blob_id)
    return unless record_type == JrcBackoffice::PrivateBlob::DOCUMENT_TYPE

    existing = self.class.where(record_type: record_type, record_id: record_id).where.not(id: id).exists?
    errors.add(:record, 'document versions have one immutable file') if name != 'file' || existing
  end

  def preserve_backoffice_document_file
    return unless attribute_in_database('record_type') == JrcBackoffice::PrivateBlob::DOCUMENT_TYPE

    raise ActiveRecord::ReadOnlyRecord, 'Document version files are immutable'
  end
end
