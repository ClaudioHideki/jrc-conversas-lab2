require 'openssl'

class JrcBackoffice::SignatureArtifactBundle < ApplicationRecord
  self.table_name = 'jrc_backoffice_signature_artifact_bundles'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  belongs_to :account
  belongs_to :delivery, class_name: 'JrcBackoffice::SignatureDelivery'
  belongs_to :contract_version, class_name: 'JrcBackoffice::ContractVersion'
  belongs_to :signed_document, class_name: 'JrcBackoffice::DocumentVersion'
  belongs_to :certificate_document, class_name: 'JrcBackoffice::DocumentVersion'
  belongs_to :captured_by, class_name: 'User'
  validates :delivery_id, :contract_version_id, uniqueness: true
  validates :source_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :consistent_source
  validate(on: :create) do
    errors.add(:captured_by, 'must belong to account') unless AccountUser.exists?(account_id: account_id, user_id: captured_by_id)
  end
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Signature artifact bundles are immutable' }
  before_validation(on: :update) { raise ActiveRecord::ReadOnlyRecord, 'Signature artifact bundles are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Signature artifact bundles are immutable' }

  def self.digest(data)
    key = Rails.application.key_generator.generate_key('jrc-signature-artifact-bundle-v1', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, JrcServiceDesk::CanonicalJson.dump(data))
  end

  def snapshot
    JSON.parse(source_snapshot)
  end

  def integrity?
    data = snapshot
    refs = %w[account_id delivery_id contract_version_id signed_document_id certificate_document_id captured_by_id]
    data.is_a?(Hash) && data['format_version'] == 1 && data.values_at(*refs) == attributes.values_at(*refs) &&
      self.class.digest(data) == source_digest && matching_binding?(data) && matching_files?(data)
  rescue JSON::ParserError, TypeError, KeyError
    false
  end

  def serializable_hash(_options = nil)
    slice('id', 'delivery_id', 'contract_version_id', 'signed_document_id', 'certificate_document_id', 'captured_by_id', 'created_at')
  end

  private

  def consistent_source
    return if source_snapshot&.bytesize.to_i <= 256.kilobytes && integrity?

    errors.add(:source_snapshot,
               'must preserve the exact private evidence binding')
  end

  def matching_binding?(data)
    expected = delivery && JrcBackoffice::Signatures::EvidenceObservation.binding_data(delivery)
    delivery && contract_version && delivery.account_id == account_id && contract_version.account_id == account_id &&
      delivery.contract_version_id == contract_version_id && data.fetch('binding') == expected
  end

  def matching_files?(data)
    { 'signed_document' => signed_document, 'certificate' => certificate_document }.all? do |kind, version|
      matching_file?(version, data.fetch('artifacts').fetch(kind))
    end
  end

  def matching_file?(version, file)
    return false unless version && version.account_id == account_id && version.backoffice_request_id == delivery.backoffice_request_id
    return false unless version.file.attached?

    expected = file.values_at('document_version_id', 'sha256', 'blob_id', 'byte_size')
    expected == [version.id, version.sha256, version.file.blob.id, version.file.blob.byte_size]
  end
end
