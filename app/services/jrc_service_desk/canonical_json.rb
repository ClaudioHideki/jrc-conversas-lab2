# frozen_string_literal: true

require 'json'
require 'digest'

# Pure validation and canonicalization, not an evaluator or serializer for public APIs.
module JrcServiceDesk::CanonicalJson
  MAX_BYTES = 131_072
  MAX_DEPTH = 24

  module_function

  def dump(value)
    encoded = JSON.generate(normalize(value))
    raise ArgumentError, 'JSON payload is too large' if encoded.bytesize > MAX_BYTES

    encoded
  rescue JSON::GeneratorError, EncodingError
    raise ArgumentError, 'Invalid JSON payload'
  end

  def digest(value)
    Digest::SHA256.hexdigest(dump(value))
  end

  def normalize(value, depth = 0)
    raise ArgumentError, 'JSON payload is too deep' if depth > MAX_DEPTH

    case value
    when Hash
      pairs = value.map do |key, item|
        raise ArgumentError, 'JSON keys must be strings or symbols' unless key.is_a?(String) || key.is_a?(Symbol)

        [key.to_s, normalize(item, depth + 1)]
      end
      raise ArgumentError, 'Duplicate normalized JSON keys' unless pairs.map(&:first).uniq.size == pairs.size

      pairs.sort_by(&:first).to_h
    when Array
      value.map { |item| normalize(item, depth + 1) }
    when String, Integer, TrueClass, FalseClass, NilClass
      value
    when Float
      raise ArgumentError, 'JSON numbers must be finite' unless value.finite?

      value
    else
      raise ArgumentError, 'Unsupported JSON value'
    end
  end
end
