class JrcFlows::NativeCredentialStore
  class Unavailable < StandardError; end
  PURPOSES = %w[OUTBOUND PENDING_CALLBACK CONFIGURATION_OUTBOUND SESSION_BEARER INSTALLATION_CALLBACK INSTALLATION_GRANT INSTALLATION_TRANSFER
                RENEW_CALLBACK INSTALLATION_REVOKE].freeze

  def self.for_application
    new(key: Rails.application.key_generator.generate_key('jrc-flow-native-credential-v1', 32))
  end

  def initialize(key:)
    raise Unavailable, 'FLOW_NATIVE_CREDENTIAL_UNAVAILABLE' unless key.is_a?(String) && key.bytesize == 32

    @encryptor = ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
  end

  def inspect
    '#<JrcFlows::NativeCredentialStore [FILTERED]>'
  end

  def encrypt(account_id:, record_id:, revision:, purpose:, token:)
    validate!(account_id, record_id, revision, purpose)
    raise Unavailable, 'FLOW_NATIVE_CREDENTIAL_UNAVAILABLE' unless token.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(token)

    @encryptor.encrypt_and_sign(token, purpose: context(account_id, record_id, revision, purpose))
  end

  def decrypt(account_id:, record_id:, revision:, purpose:, ciphertext:)
    validate!(account_id, record_id, revision, purpose)
    token = @encryptor.decrypt_and_verify(ciphertext, purpose: context(account_id, record_id, revision, purpose))
    raise Unavailable, 'FLOW_NATIVE_CREDENTIAL_UNAVAILABLE' unless token.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(token)

    token
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
    raise Unavailable, 'FLOW_NATIVE_CREDENTIAL_UNAVAILABLE'
  end

  private

  def validate!(account_id, record_id, revision, purpose)
    valid = [account_id, record_id, revision].all? { |value| value.is_a?(Integer) && value.positive? && value <= 9_007_199_254_740_991 }
    raise Unavailable, 'FLOW_NATIVE_CREDENTIAL_UNAVAILABLE' unless valid && PURPOSES.include?(purpose)
  end

  def context(account_id, record_id, revision, purpose)
    "jrc-flow-native:v1:account:#{account_id}:record:#{record_id}:revision:#{revision}:#{purpose}"
  end
end
