require 'openssl'
require 'base64'

class JrcBackoffice::Docusign::ConnectVerifier
  def self.valid?(raw_body:, signatures:, keys:)
    return false unless bounded_body?(raw_body) && bounded_array?(signatures) && bounded_array?(keys)

    keys.any? do |key|
      next false unless bounded_key?(key)

      expected = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', key, raw_body))
      signature_matches?(signatures, expected)
    end
  end

  def self.signature_matches?(signatures, expected)
    signatures.any? { |signature| signature.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(expected, signature) }
  end

  def self.bounded_body?(value)
    value.is_a?(String) && value.bytesize.between?(1, 2.megabytes)
  end

  def self.bounded_array?(value)
    value.is_a?(Array) && value.size.between?(1, 5)
  end

  def self.bounded_key?(value)
    value.is_a?(String) && value.bytesize.between?(32, 256)
  end
  private_class_method :bounded_body?, :bounded_array?, :bounded_key?, :signature_matches?
end
