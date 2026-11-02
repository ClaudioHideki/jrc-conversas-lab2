# A fixed provider configuration revision, not the account's mutable default.
# Historical deliveries must reference this ID rather than resolving that default again.
class JrcBackoffice::SignatureConnection < ApplicationRecord
  self.table_name = 'jrc_backoffice_signature_connections'
  CONFIGURATION = %w[account_id integration_id created_by_id public_id provider environment integration_key impersonated_user_id
                     external_account_id encrypted_credentials credentials_purpose revision enabled created_at].freeze
  self.filter_attributes += %i[encrypted_credentials credentials_purpose]
  attr_readonly(*CONFIGURATION)
  belongs_to :account
  belongs_to :integration, class_name: 'JrcBackoffice::SignatureIntegration'
  belongs_to :created_by, class_name: 'User'
  validates :public_id, uniqueness: true, presence: true
  validates :provider, :environment, :encrypted_credentials, :credentials_purpose, presence: true
  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :integration_id }
  validate { errors.add(:integration, 'must belong to account') unless integration&.account_id == account_id }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Signature connection snapshots are immutable' }

  def self.capture!(integration, actor:)
    attributes = integration.attributes.slice('account_id', 'provider', 'environment', 'integration_key', 'impersonated_user_id',
                                              'external_account_id', 'encrypted_credentials', 'revision', 'enabled',
                                              'authorization_checked_at', 'connect_checked_at')
    existing = exists?(integration_id: integration.id)
    create!(attributes.merge(integration: integration, created_by: actor,
                             public_id: existing ? SecureRandom.uuid : integration.public_id,
                             credentials_purpose: "docusign:integration:#{integration.public_id}:revision:#{integration.revision}"))
  end

  def credentials
    JrcBackoffice::SignatureSecrets.new.decrypt(account_id: account_id, purpose: credentials_purpose, ciphertext: encrypted_credentials)
  end

  def current_for_new_delivery?
    current = integration.reload
    keys = %w[provider environment integration_key impersonated_user_id external_account_id encrypted_credentials revision enabled]
    current.enabled? && current.attributes.slice(*keys) == attributes.slice(*keys)
  end

  def delivery_ready?
    enabled? && authorization_checked_at.present? && connect_checked_at.present?
  end

  def serializable_hash(_options = nil)
    attributes.slice('id', 'provider', 'environment', 'revision', 'created_at')
  end
end
