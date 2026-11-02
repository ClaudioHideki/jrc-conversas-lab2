# Immutable admission, separate from the append-only provider/outcome history.
# A durable row or queued job is never evidence that an envelope was sent.
class JrcBackoffice::SignatureDelivery < ApplicationRecord
  self.table_name = 'jrc_backoffice_signature_deliveries'
  self.filter_attributes += [:source_snapshot]
  encrypts :source_snapshot, support_unencrypted_data: false
  belongs_to :account
  belongs_to :contract, class_name: 'JrcCrm::Contract'
  belongs_to :backoffice_request, class_name: 'JrcCrm::BackofficeRequest'
  belongs_to :contract_version, class_name: 'JrcBackoffice::ContractVersion'
  belongs_to :signer_roster, class_name: 'JrcBackoffice::SignerRoster'
  belongs_to :authority_proposal, class_name: 'JrcBackoffice::AuthorityProposal'
  belongs_to :connection, class_name: 'JrcBackoffice::SignatureConnection'
  belongs_to :created_by, class_name: 'User'
  has_many :events, class_name: 'JrcBackoffice::SignatureDeliveryEvent', foreign_key: :delivery_id, inverse_of: :delivery,
                    dependent: :restrict_with_exception
  validates :contract_version_id, :transaction_id, uniqueness: true
  validates :transaction_id, format: { with: JrcBackoffice::SignatureIntegration::UUID }
  validates :idempotency_key, presence: true, uniqueness: { scope: %i[account_id created_by_id] }
  validates :source_digest, :input_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :consistent_source
  validate :creator_belongs_to_account
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Signature admissions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Signature admissions are immutable' }

  def snapshot
    JSON.parse(source_snapshot)
  end

  def state
    kind = events.order(id: :desc).pick(:kind)
    kind ? JrcBackoffice::SignatureDeliveryEvent::STATES.fetch(kind) : 'prepared'
  end

  def external_id
    events.where.not(external_id: nil).pick(:external_id)
  end

  def serializable_hash(_options = nil)
    slice('id', 'backoffice_request_id', 'contract_id', 'contract_version_id', 'signer_roster_id', 'authority_proposal_id',
          'connection_id', 'created_at').merge('state' => state, 'external_id' => external_id,
                                               'provider' => snapshot.fetch('provider'), 'environment' => snapshot.fetch('environment'))
  end

  private

  def consistent_source
    data = snapshot
    refs = %w[account_id contract_id backoffice_request_id contract_version_id signer_roster_id authority_proposal_id connection_id]
    valid = source_snapshot.bytesize <= 512.kilobytes && data.values_at(*refs) == attributes.values_at(*refs) && data['format_version'] == 1 &&
            JrcBackoffice::Signatures::DeliverySnapshot.digest(data) == source_digest && matching_configuration?(data)
    errors.add(:source_snapshot, 'must preserve the exact admission') unless valid
  rescue JSON::ParserError, TypeError
    errors.add(:source_snapshot, 'must be a sealed admission')
  end

  def matching_configuration?(data)
    fields = %w[provider environment external_account_id]
    data.values_at(*fields) == connection.attributes.values_at(*fields)
  end

  def creator_belongs_to_account
    errors.add(:created_by, 'must belong to account') unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end
end
