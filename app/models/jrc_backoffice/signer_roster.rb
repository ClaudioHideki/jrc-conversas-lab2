# An immutable proposal of who must sign. It is neither proof of powers nor an
# authorization to send. The exact roster will be pinned by a contract version.
class JrcBackoffice::SignerRoster < ApplicationRecord
  self.table_name = 'jrc_backoffice_signer_rosters'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  belongs_to :account
  belongs_to :contract, class_name: 'JrcCrm::Contract'
  belongs_to :backoffice_request, class_name: 'JrcCrm::BackofficeRequest'
  belongs_to :created_by, class_name: 'User'
  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[contract_id backoffice_request_id] }
  validates :idempotency_key, presence: true, uniqueness: { scope: :backoffice_request_id }
  validates :customer_mode, :issuer_mode, inclusion: { in: %w[single joint] }
  validates :change_reason, presence: true, length: { maximum: 2000 }
  validates :source_digest, :input_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :consistent_origin
  validate :consistent_snapshot
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Signer rosters are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Signer rosters are immutable' }

  def snapshot
    JSON.parse(source_snapshot)
  end

  # Server-side document source, distinct from the masked operational DTO.
  def version_snapshot
    { 'id' => id, 'revision' => revision, 'source_digest' => source_digest, 'source' => snapshot }
  end

  def serializable_hash(_options = nil)
    slice('id', 'contract_id', 'backoffice_request_id', 'revision', 'customer_mode', 'issuer_mode',
          'change_reason', 'source_digest', 'created_by_id', 'created_at').merge(
            'signers' => snapshot.fetch('signers').map do |person|
              person.slice('key', 'position', 'party', 'contact_id', 'company_id', 'name', 'email', 'required', 'personal_tax_identifier_masked')
            end
          )
  end

  private

  def consistent_origin
    errors.add(:contract, 'must match the account and request') unless matching_origin?
    errors.add(:created_by, 'must belong to account') unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end

  def matching_origin?
    return false unless contract && backoffice_request

    [contract.account_id, backoffice_request.account_id, backoffice_request.contract_id, backoffice_request.sales_order_id] ==
      [account_id, account_id, contract_id, contract.sales_order_id]
  end

  def consistent_snapshot
    data = snapshot
    raise TypeError unless data.is_a?(Hash)

    expected = [account_id, contract_id, backoffice_request_id, customer_mode, issuer_mode]
    actual = data.values_at('account_id', 'contract_id', 'backoffice_request_id', 'customer_mode', 'issuer_mode')
    JrcBackoffice::SignerSelection.call(data['signers'], { 'customer' => customer_mode, 'issuer' => issuer_mode })
    valid = source_snapshot.bytesize <= 256.kilobytes && actual == expected && data['format_version'] == 1 &&
            JrcBackoffice::SignerRosterSource.digest(data) == source_digest
    errors.add(:source_snapshot, 'must preserve the exact signing proposal') unless valid
  rescue JSON::ParserError, TypeError, ArgumentError
    errors.add(:source_snapshot, 'must be a signing proposal')
  end
end
