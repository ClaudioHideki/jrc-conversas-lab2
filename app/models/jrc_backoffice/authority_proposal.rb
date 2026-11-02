# A sealed proposal of representation evidence. It grants no powers by itself;
# the single native Central must approve this exact live context.
class JrcBackoffice::AuthorityProposal < ApplicationRecord
  self.table_name = 'jrc_backoffice_authority_proposals'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  belongs_to :account
  belongs_to :contract_version, class_name: 'JrcBackoffice::ContractVersion'
  belongs_to :signer_roster, class_name: 'JrcBackoffice::SignerRoster'
  belongs_to :contract, class_name: 'JrcCrm::Contract'
  belongs_to :backoffice_request, class_name: 'JrcCrm::BackofficeRequest'
  belongs_to :created_by, class_name: 'User'
  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :contract_version_id }
  validates :idempotency_key, presence: true, uniqueness: { scope: :backoffice_request_id }
  validates :change_reason, presence: true, length: { maximum: 2000 }
  validates :source_digest, :input_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :consistent_source
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Authority proposals are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Authority proposals are immutable' }

  def snapshot
    JSON.parse(source_snapshot)
  end

  def business_unit_id
    signer_roster.snapshot.fetch('business_unit_id')
  end

  def issuer_company_id
    signer_roster.snapshot.fetch('issuer').fetch('id')
  end

  def business_unit
    account.jrc_crm_business_units.find(business_unit_id)
  end

  def title
    "#{contract.contract_number} · v#{contract_version.number} · #{backoffice_request.request_number}"
  end

  def serializable_hash(_options = nil)
    slice('id', 'revision', 'contract_version_id', 'signer_roster_id', 'backoffice_request_id', 'created_by_id',
          'source_digest', 'change_reason', 'created_at').merge('proofs' => snapshot.fetch('proofs'))
  end

  private

  def consistent_source
    data = snapshot
    valid = valid_format?(data) && matching_origin?(data) &&
            JrcBackoffice::AuthoritySource.digest(data) == source_digest && AccountUser.exists?(account_id: account_id, user_id: created_by_id)
    errors.add(:source_snapshot, 'must preserve the exact version, people and representation proposal') unless valid
  rescue JSON::ParserError, KeyError, TypeError
    errors.add(:source_snapshot, 'must be an exact representation proposal')
  end

  def valid_format?(data)
    source_snapshot.bytesize <= 256.kilobytes && data.is_a?(Hash) && data['format_version'] == 1 &&
      JrcBackoffice::AuthorityProofs.normalize(data.fetch('proofs'), signer_roster.snapshot) == data['proofs']
  end

  def matching_origin?(data)
    return false unless contract_version && signer_roster

    origin = [account_id, contract_id, backoffice_request_id, signer_roster_id, contract_version_id]
    expected = [contract_version.account_id, contract_version.contract_id, contract_version.backoffice_request_id,
                contract_version.signer_roster_id, contract_version.id]
    fields = %w[account_id contract_id backoffice_request_id signer_roster_id contract_version_id]
    origin == expected && data.values_at(*fields) == origin && signer_roster.account_id == account_id && matching_digests?(data)
  end

  def matching_digests?(data)
    data['version_digest'] == contract_version.source_digest && data['pdf_sha256'] == contract_version.pdf_sha256 &&
      data['roster_digest'] == signer_roster.source_digest
  end
end
