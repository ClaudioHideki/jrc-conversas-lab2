class JrcBackoffice::SignatureSecrets
  def initialize
    key = Rails.application.key_generator.generate_key('jrc-backoffice-signature-secrets-v1', 32)
    @encryptor = ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
  end

  def encrypt(account_id:, purpose:, data:)
    @encryptor.encrypt_and_sign(data, purpose: context(account_id, purpose))
  end

  def decrypt(account_id:, purpose:, ciphertext:)
    value = @encryptor.decrypt_and_verify(ciphertext, purpose: context(account_id, purpose))
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'CREDENTIAL_UNAVAILABLE') unless value.is_a?(Hash)

    value
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'CREDENTIAL_UNAVAILABLE')
  end

  def inspect
    '#<JrcBackoffice::SignatureSecrets [FILTERED]>'
  end

  private

  def context(account_id, purpose)
    raise ArgumentError, 'Invalid signature secret context' unless account_id.is_a?(Integer) && account_id.positive? && purpose.present?

    "jrc-signatures:v1:account:#{account_id}:#{purpose}"
  end
end
