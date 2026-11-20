# frozen_string_literal: true

class JrcContactCenter::AudioAssetAttributes
  KEYS = %w[name description purpose folder_id].freeze

  def self.parse(value)
    values = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio' unless values.is_a?(Hash)

    values = values.stringify_keys
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio' unless (values.keys - KEYS).empty?

    validate_text!(values)

    values['name'] = values['name'].strip if values.key?('name')
    values
  end

  def self.validate_text!(values)
    text = values.slice('name', 'description', 'purpose').all? do |key, item|
      item.is_a?(String) || (key != 'name' && item.nil?)
    end
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio' unless text
  end
  private_class_method :validate_text!
end
