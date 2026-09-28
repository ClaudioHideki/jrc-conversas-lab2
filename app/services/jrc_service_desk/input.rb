# frozen_string_literal: true

# Strict IDs and allowlists: Rails' permissive to_i casting is not authorization.
module JrcServiceDesk::Input
  module_function

  def id(value)
    return value if value.is_a?(Integer) && value.positive? && value <= 9_223_372_036_854_775_807
    if value.is_a?(String) && value.match?(/\A[1-9][0-9]{0,18}\z/)
      parsed = Integer(value, 10)
      return parsed if parsed <= 9_223_372_036_854_775_807
    end
    raise ArgumentError, 'Invalid identifier'
  end

  def version(value)
    return value if value.is_a?(Integer) && value >= 0
    return Integer(value, 10) if value.is_a?(String) && value.match?(/\A(?:0|[1-9][0-9]{0,9})\z/)

    raise ArgumentError, 'Invalid record version'
  end

  def attributes(value, allowed)
    raise ArgumentError, 'Expected an attribute hash' unless value.is_a?(Hash)

    normalized = value.each_with_object({}) do |(key, item), result|
      raise ArgumentError, 'Invalid attribute key' unless key.is_a?(String) || key.is_a?(Symbol)
      raise ArgumentError, 'Duplicate attribute key' if result.key?(key.to_s)

      result[key.to_s] = item
    end
    raise ArgumentError, 'Unsupported attributes' if (normalized.keys - allowed.map(&:to_s)).any?

    normalized
  end

  def request_key(value)
    unless value.is_a?(String) && value.bytesize <= 120 && !value.strip.empty? && !value.match?(/[\x00-\x1f\x7f]/)
      raise ArgumentError, 'Invalid idempotency key'
    end
    value
  end
end
