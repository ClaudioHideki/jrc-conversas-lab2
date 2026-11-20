# frozen_string_literal: true

# Account-local administrative catalogue. Old rules and pending qualifications are not rewritten.
class JrcContactCenter::AcwEndingReasons
  KEY = 'voice_reason_catalog'
  FIELDS = %w[code name category description order active].freeze
  MAX_ENTRIES = 100

  def initialize(account:)
    @account = account
  end

  def call
    settings = @account.settings.fetch(JrcContactCenter::AcwPolicy::KEY, {})
    return { 'version' => 0, 'entries' => [] } unless settings.key?(KEY)

    value = settings.fetch(KEY)

    invalid! unless valid_header?(value) && validate!(value['entries']) == value['entries']
    value.deep_dup
  end

  def signature(values)
    state = call
    return values unless state.fetch('version').positive?

    rows = state.fetch('entries').map { |row| FIELDS.map { |field| row.fetch(field) } }
    values + [[KEY, state.fetch('version'), rows]]
  end

  def propose(settings:, entries:)
    return settings if entries == :unchanged

    previous = call
    current = validate!(entries)
    removed = previous.fetch('entries').pluck('code') - current.pluck('code')
    raise JrcContactCenter::OperationError, 'ending_reason_deactivation_required' if removed.any?
    return settings if previous.fetch('entries') == current

    settings.merge(KEY => { 'version' => previous.fetch('version') + 1, 'entries' => current })
  end

  private

  def valid_header?(value)
    value.is_a?(Hash) && value.keys.sort == %w[entries version] && value['version'].is_a?(Integer) && value['version'].positive?
  end

  def validate!(entries)
    valid = entries.is_a?(Array) && entries.length <= MAX_ENTRIES && entries.to_json.bytesize <= 131_072
    invalid! unless valid
    rows = entries.map { |entry| validated_entry(entry) }
    invalid! unless rows.pluck('code').uniq.length == rows.length
    rows
  end

  def validated_entry(entry)
    invalid! unless entry.is_a?(Hash)
    row = entry.deep_stringify_keys
    invalid! unless row.keys.sort == FIELDS.sort
    validate_text!(row)
    valid_order = row['order'].is_a?(Integer) && row['order'].between?(0, 1000)
    invalid! unless valid_order && [true, false].include?(row['active'])
    row
  end

  def validate_text!(row)
    invalid! unless text?(row['code'], 100) && text?(row['name'], 120) && text?(row['category'], 120)
    invalid! unless row['description'].is_a?(String) && row['description'].length <= 2000
  end

  def text?(value, maximum)
    value.is_a?(String) && value.strip.present? && value == value.strip && value.length <= maximum
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_acw_ending_reasons'
  end
end
