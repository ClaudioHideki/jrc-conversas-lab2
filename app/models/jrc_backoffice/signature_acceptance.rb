require 'openssl'

# An exact private-blob reference grant, not a generic attachment bypass.
class JrcBackoffice::SignatureAcceptance < ApplicationRecord
  self.table_name = 'jrc_backoffice_signature_acceptances'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  belongs_to :account
  belongs_to :contract, class_name: 'JrcCrm::Contract'
  belongs_to :bundle, class_name: 'JrcBackoffice::SignatureArtifactBundle'
  belongs_to :signed_blob, class_name: 'ActiveStorage::Blob'
  belongs_to :accepted_by, class_name: 'User'
  validates :contract_id, :bundle_id, uniqueness: true
  validates :source_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :consistent_source
  before_validation(on: :update) { raise ActiveRecord::ReadOnlyRecord, 'Signature acceptances are immutable' }
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Signature acceptances are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Signature acceptances are immutable' }

  def self.digest(data)
    key = Rails.application.key_generator.generate_key('jrc-signature-acceptance-v1', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, JrcServiceDesk::CanonicalJson.dump(data))
  end

  def snapshot
    JSON.parse(source_snapshot)
  end

  def integrity?
    data = snapshot
    refs = %w[account_id contract_id bundle_id signed_blob_id accepted_by_id]
    data.is_a?(Hash) && data['format_version'] == 1 && data.values_at(*refs) == attributes.values_at(*refs) &&
      self.class.digest(data) == source_digest && matching_source?(data)
  rescue JSON::ParserError, TypeError, KeyError
    false
  end

  def self.permits_attachment?(attachment)
    return false unless attachment.record_type == 'JrcCrm::Contract' && attachment.name == 'signed_document'

    receipt = find_by(contract_id: attachment.record_id, signed_blob_id: attachment.blob_id)
    return false unless receipt&.integrity?

    JrcBackoffice::Signatures::EvidenceState.new(receipt.bundle).call.fetch(:state) == 'verified' &&
      JrcBackoffice::Signatures::EvidenceState.current_source?(receipt.contract, receipt.bundle)
  end

  private

  def matching_source?(data)
    return false unless bundle && contract

    expected = [account_id, account_id, contract_id, signed_blob_id, data.fetch('bundle_digest'), data.fetch('signed_sha256')]
    observed = [bundle.account_id, contract.account_id, bundle.delivery.contract_id,
                bundle.signed_document.file.blob.id, bundle.source_digest, bundle.signed_document.sha256]
    observed == expected
  end

  def consistent_source
    valid = source_snapshot&.bytesize.to_i <= 16.kilobytes && integrity?
    errors.add(:source_snapshot, 'must preserve the exact signed contract and private file') unless valid
  end
end
