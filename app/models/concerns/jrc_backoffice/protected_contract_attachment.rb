module JrcBackoffice::ProtectedContractAttachment
  extend ActiveSupport::Concern
  included do
    validate :reject_relinking_contract_version
  end

  private

  def reject_relinking_contract_version
    return unless blob_id && JrcBackoffice::ContractVersion.exists?(pdf_blob_id: blob_id)

    errors.add(:blob, 'must be accessed through the scoped Backoffice contract API')
  end
end
