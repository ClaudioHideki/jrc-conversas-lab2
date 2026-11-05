module JrcBackoffice::ProtectedContractAttachment
  extend ActiveSupport::Concern
  included do
    validate :reject_relinking_contract_version
    # ActiveStorage may save the same association twice inside its owner's
    # transaction. A save with no changed attributes cannot relink a file.
    before_update :preserve_backoffice_document_file, if: :has_changes_to_save?
    before_destroy :preserve_backoffice_document_file
  end

  private

  def reject_relinking_contract_version
    return unless blob_id

    if JrcBackoffice::PrivateBlob.protected?(blob_id) && !JrcBackoffice::SignatureAcceptance.permits_attachment?(self)
      errors.add(:blob, 'must be accessed through the scoped Backoffice API')
    end
    return unless record_type == JrcBackoffice::PrivateBlob::DOCUMENT_TYPE

    existing = self.class.where(record_type: record_type, record_id: record_id).where.not(id: id).exists?
    errors.add(:record, 'document versions have one immutable file') if name != 'file' || existing
  end

  def preserve_backoffice_document_file
    if attribute_in_database('record_type') == 'JrcCrm::Contract' && attribute_in_database('name') == 'signed_document' &&
       JrcBackoffice::SignatureAcceptance.exists?(contract_id: attribute_in_database('record_id'))
      raise ActiveRecord::ReadOnlyRecord, 'Accepted signed contract files are immutable'
    end
    return unless attribute_in_database('record_type') == JrcBackoffice::PrivateBlob::DOCUMENT_TYPE

    raise ActiveRecord::ReadOnlyRecord, 'Document version files are immutable'
  end
end
