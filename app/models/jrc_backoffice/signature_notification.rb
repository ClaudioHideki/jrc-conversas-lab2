class JrcBackoffice::SignatureNotification < ApplicationRecord
  self.table_name = 'jrc_backoffice_signature_notifications'
  self.filter_attributes += [:encrypted_payload]
  belongs_to :account
  belongs_to :integration, class_name: 'JrcBackoffice::SignatureIntegration'
  validates :body_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :envelope_id, format: { with: JrcBackoffice::SignatureIntegration::UUID }
  validates :encrypted_payload, :event_type, :provider_generated_at, presence: true
  validates :state, inclusion: { in: %w[received processed ignored failed] }
  validate { errors.add(:integration, 'must belong to account') unless integration&.account_id == account_id }
  attr_readonly :account_id, :integration_id, :integration_revision, :body_sha256, :event_type, :envelope_id,
                :encrypted_payload, :provider_generated_at

  def payload
    JrcBackoffice::SignatureSecrets.new.decrypt(account_id: account_id, purpose: secret_purpose, ciphertext: encrypted_payload)
  end

  def payload=(value)
    self.encrypted_payload = JrcBackoffice::SignatureSecrets.new.encrypt(account_id: account_id, purpose: secret_purpose, data: value)
  end

  # Notification metadata is operational evidence; the envelope payload is never a public DTO.
  def serializable_hash(_options = nil)
    attributes.slice('id', 'event_type', 'state', 'created_at', 'provider_generated_at')
  end

  private

  def secret_purpose
    "docusign:notification:#{integration_id}:#{integration_revision}:#{body_sha256}"
  end
end
