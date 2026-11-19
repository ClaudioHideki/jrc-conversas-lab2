# frozen_string_literal: true

class JrcContactCenter::DeferredPauseInput
  FIELDS = %i[command_id expected_state_version expected_request_revision reason_code queue_id justification].freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  def self.call(attributes)
    new.call(attributes)
  end

  def call(attributes)
    valid = attributes.is_a?(Hash) && (attributes.keys - FIELDS).empty?
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid

    values = attributes.slice(*FIELDS)
    validate_identity!(values)
    validate_revision!(values[:expected_request_revision])
    values[:reason_code] = bounded_string(values[:reason_code], 100)
    values[:justification] = bounded_string(values.fetch(:justification, ''), 1000, empty: true)
    values[:queue_id] = queue_id(values[:queue_id])
    values
  end

  private

  def validate_identity!(values)
    command = values[:command_id]
    version = values[:expected_state_version]
    valid = command.is_a?(String) && UUID.match?(command) &&
            version.is_a?(String) && version.length <= 100 && /\A\d+\z/.match?(version)
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid
  end

  def validate_revision!(revision)
    valid = revision.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(revision)
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid
  end

  def bounded_string(value, maximum, empty: false)
    valid = value.is_a?(String) && value.length <= maximum && !value.include?("\0") && (empty || value.strip.present?)
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid

    value.strip
  end

  def queue_id(value)
    return if value.nil? || value == ''

    valid = [String, Integer].any? { |type| value.is_a?(type) } && /\A[1-9]\d{0,18}\z/.match?(value.to_s)
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid && value.to_i <= 9_223_372_036_854_775_807

    value.to_s
  end
end
