# A value object for the existing AgentStateManager, not a second agent registry.
class JrcContactCenter::PauseReasonDefinition
  FIELDS = %w[code name category description active minimum_minutes default_minutes maximum_minutes unit_ids custom_role_ids].freeze
  OPTIONAL_FIELDS = %w[justification_required approval_required time_alert_enabled].freeze
  ALL_FIELDS = (FIELDS + OPTIONAL_FIELDS).freeze
  TIMES = %w[minimum_minutes default_minutes maximum_minutes].freeze

  class Invalid < JrcContactCenter::OperationError
    attr_reader :fields

    def initialize(fields)
      @fields = fields
      super('invalid_pause_catalog')
    end
  end

  def self.applicable?(entry, member:, unit_ids:)
    (entry.fetch('unit_ids').empty? || entry.fetch('unit_ids').intersect?(unit_ids)) &&
      (entry.fetch('custom_role_ids').empty? || entry.fetch('custom_role_ids').include?(member.custom_role_id))
  end

  def initialize(account:)
    @account = account
  end

  def call(input, verify_references: true)
    raise Invalid, ['entries'] unless input.is_a?(Hash)

    row = input.deep_stringify_keys
    raise Invalid, ['entries'] if (row.keys - ALL_FIELDS).any?

    validate_text!(row)
    validate_times!(row)
    row['description'] ||= ''
    TIMES.each { |field| row[field] = nil unless row.key?(field) }
    row['unit_ids'] = identifiers(row.fetch('unit_ids', []), JrcContactCenter::Unit.where(account: @account), 'unit_ids', verify_references)
    row['custom_role_ids'] = identifiers(row.fetch('custom_role_ids', []), CustomRole.where(account: @account), 'custom_role_ids', verify_references)
    row.slice(*ALL_FIELDS)
  end

  private

  def validate_text!(row)
    required = { 'code' => 64, 'name' => 100, 'category' => 60 }
    invalid = required.filter_map do |field, maximum|
      field unless row[field].is_a?(String) && row[field].strip.length.between?(1, maximum)
    end
    raise Invalid, invalid if invalid.any?

    validate_labels!(row)
  end

  def validate_labels!(row)
    raise Invalid, ['code'] unless row['code'].match?(/\A[a-z0-9][a-z0-9_.-]{0,63}\z/)
    raise Invalid, ['active'] unless [true, false].include?(row['active'])

    validate_flags!(row)

    description = row.fetch('description', '')
    raise Invalid, ['description'] unless description.is_a?(String) && description.length <= 1000
  end

  def validate_flags!(row)
    OPTIONAL_FIELDS.each do |field|
      raise Invalid, [field] if row.key?(field) && [true, false].exclude?(row[field])
    end
  end

  def validate_times!(row)
    invalid = TIMES.reject { |field| valid_minutes?(row[field]) }
    invalid << 'default_minutes' unless row['default_minutes'].is_a?(Integer)
    raise Invalid, invalid.uniq if invalid.any?

    pairs = [%w[minimum_minutes default_minutes], %w[default_minutes maximum_minutes], %w[minimum_minutes maximum_minutes]]
    invalid = pairs.filter_map do |left, right|
      right if inverted_time_pair?(row, left, right)
    end
    raise Invalid, invalid.uniq if invalid.any?
  end

  def inverted_time_pair?(row, left, right)
    row[left] && row[right] && row[left] > row[right]
  end

  def valid_minutes?(value)
    value.nil? || (value.is_a?(Integer) && value.between?(0, 5999))
  end

  def identifiers(values, relation, field, verify_references)
    ids = identifier_values(values, field)
    raise ActiveRecord::RecordNotFound if verify_references && relation.where(id: ids).count != ids.length

    ids.sort
  end

  def identifier_values(values, field)
    valid = values.is_a?(Array) && values.length <= 100 && values.all? { |id| identifier?(id) }
    raise Invalid, [field] unless valid

    ids = values.map(&:to_i)
    raise Invalid, [field] unless ids.uniq.length == ids.length

    ids
  end

  def identifier?(value)
    return value.between?(1, 9_223_372_036_854_775_807) if value.is_a?(Integer)

    value.is_a?(String) && value.match?(/\A[1-9]\d{0,18}\z/) && value.to_i <= 9_223_372_036_854_775_807
  end
end
