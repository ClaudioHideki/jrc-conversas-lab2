# frozen_string_literal: true

# State precondition only: the token never confers access or scope.
class JrcContactCenter::ConfigurationRevision
  def self.token(record)
    Digest::SHA256.hexdigest([record.class.name, canonical(record.attributes)].to_json)
  end

  def self.check!(record, expected)
    check_token!(token(record), expected)
  end

  def self.check_token!(actual, expected)
    unless expected.is_a?(String) && expected.present?
      raise JrcContactCenter::OperationError.new('configuration_revision_required', status: :precondition_required)
    end
    return if ActiveSupport::SecurityUtils.secure_compare(actual, expected)

    raise JrcContactCenter::OperationError.new('stale_configuration_revision', status: :conflict)
  end

  def self.canonical(value)
    case value
    when Hash
      value.stringify_keys.sort.to_h.transform_values { |entry| canonical(entry) }
    when Array
      value.map { |entry| canonical(entry) }
    when Time, ActiveSupport::TimeWithZone
      value.utc.iso8601(6)
    else
      value
    end
  end
  private_class_method :canonical
end
