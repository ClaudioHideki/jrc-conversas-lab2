require 'openssl'

class JrcBackoffice::Docusign::Credentials
  def self.prepare(stored:, attributes:)
    data = stored.deep_dup
    key = attributes['private_key']
    if key.present?
      raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID') unless key.is_a?(String) && key.bytesize <= 16.kilobytes

      data['private_key'] = key.strip
    end
    data['connect_hmac_keys'] = attributes['connect_hmac_keys'] if attributes['connect_hmac_keys'].present?
    validate!(data)
    data
  end

  def self.validate!(data)
    key = OpenSSL::PKey::RSA.new(data['private_key'].to_s)
    return if key.private? && key.n.num_bits >= 2048 && valid_hmac_keys?(data['connect_hmac_keys'])

    raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID')
  rescue OpenSSL::PKey::PKeyError
    raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID')
  end

  def self.valid_hmac_keys?(keys)
    keys.is_a?(Array) && keys.size.between?(1, 5) && keys.all? { |value| value.is_a?(String) && value.bytesize.between?(32, 256) }
  end
  private_class_method :validate!, :valid_hmac_keys?
end
