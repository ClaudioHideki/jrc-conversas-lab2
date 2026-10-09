# frozen_string_literal: true

class JrcServiceDesk::CatalogueFields
  KEYS = %w[key label type required options].freeze
  TYPES = %w[text integer boolean select].freeze
  RESERVED = %w[__proto__ constructor prototype].freeze

  def initialize(fields)
    @fields = fields
  end

  def valid?
    @fields.is_a?(Array) && @fields.size <= 50 && @fields.all? { |field| valid_field?(field) }
  end

  def duplicate_keys?
    @fields.is_a?(Array) && @fields.all?(Hash) && @fields.pluck('key').uniq.size != @fields.size
  end

  private

  def valid_field?(field)
    return false unless field.is_a?(Hash) && (field.keys - KEYS).empty?

    valid_key?(field['key']) && valid_text?(field['label']) && TYPES.include?(field['type']) &&
      [true, false].include?(field['required']) && valid_options?(field)
  end

  def valid_key?(key)
    key.is_a?(String) && key.match?(/\A[a-zA-Z0-9_.-]{1,80}\z/) && RESERVED.exclude?(key)
  end

  def valid_text?(value)
    value.is_a?(String) && value.size.between?(1, 255)
  end

  def valid_options?(field)
    return true unless field['type'] == 'select'

    options = field['options']
    options.is_a?(Array) && options.any? && options.all? { |value| valid_text?(value) }
  end
end
