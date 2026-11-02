class JrcBackoffice::SignatureIntegration < ApplicationRecord
  self.table_name = 'jrc_backoffice_signature_integrations'
  self.filter_attributes += [:encrypted_credentials]
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  attr_readonly :account_id, :public_id, :created_by_id
  validates :account_id, :public_id, uniqueness: true
  validates :encrypted_credentials, presence: true
  validates :environment, inclusion: { in: %w[demo production] }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :integration_key, :impersonated_user_id, :external_account_id, :public_id, format: { with: UUID }
  before_validation(on: :create) { self.public_id ||= SecureRandom.uuid }
  before_update :invalidate_verification
  validate(on: :create) do
    errors.add(:created_by, 'must belong to account') unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end

  def credentials
    JrcBackoffice::SignatureSecrets.new.decrypt(account_id: account_id, purpose: secret_purpose, ciphertext: encrypted_credentials)
  end

  def credentials=(value)
    self.public_id ||= SecureRandom.uuid
    self.encrypted_credentials = JrcBackoffice::SignatureSecrets.new.encrypt(account_id: account_id, purpose: secret_purpose, data: value)
  end

  def authorization_current?
    enabled? && authorization_checked_at.present?
  end

  def delivery_ready?
    authorization_current? && connect_checked_at.present?
  end

  def name
    'DocuSign'
  end

  def serializable_hash(_options = nil)
    { 'provider' => name, 'configured' => persisted?, 'environment' => environment, 'enabled' => enabled?,
      'authorization_checked' => authorization_checked_at.present?, 'connect_checked' => connect_checked_at.present?,
      'delivery_ready' => delivery_ready? }
  end

  private

  def secret_purpose
    "docusign:integration:#{public_id}:revision:#{revision}"
  end

  def invalidate_verification
    fields = %w[environment integration_key impersonated_user_id external_account_id encrypted_credentials revision enabled]
    return unless fields.any? { |field| will_save_change_to_attribute?(field) }

    self.authorization_checked_at = nil
    self.connect_checked_at = nil
  end
end
