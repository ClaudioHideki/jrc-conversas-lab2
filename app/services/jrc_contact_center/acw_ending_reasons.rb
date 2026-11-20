# frozen_string_literal: true

# Account-local catalogue. The caller retains native global configuration authority and Account locking.
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

    validate_document!(settings.fetch(KEY)).deep_dup
  end

  def validate_document!(value)
    invalid! unless valid_header?(value) && validate!(value['entries']) == value['entries']
    if value.key?('required_queue_ids')
      invalid! unless stored_queue_ids?(value['required_queue_ids'])
      validate_required!(value.fetch('entries'), value.fetch('required_queue_ids'))
    end
    value
  end

  def signature(values)
    state = call
    return values unless state.fetch('version').positive?

    rows = state.fetch('entries').map { |row| FIELDS.map { |field| row.fetch(field) } }
    signature = values + [[KEY, state.fetch('version'), rows]]
    queues = state.fetch('required_queue_ids', [])
    queues.any? ? signature + [['required_ending_reason_queues_v1', queues]] : signature
  end

  def propose(settings:, entries:, required_queue_ids: :unchanged, activation_confirmed: false)
    return settings if entries == :unchanged && required_queue_ids == :unchanged

    previous = call
    current = entries == :unchanged ? previous.fetch('entries') : validate!(entries)
    queues = required_queue_ids == :unchanged ? previous.fetch('required_queue_ids', []) : validated_queue_ids(required_queue_ids)
    validate_change!(previous, current, queues, activation_confirmed)
    return settings if previous.fetch('entries') == current && previous.fetch('required_queue_ids', []) == queues

    settings.merge(KEY => versioned_state(previous, current, queues))
  end

  private

  # Keep the original document shape when queue enforcement has never been configured.
  def versioned_state(previous, entries, queues)
    state = { 'version' => previous.fetch('version') + 1, 'entries' => entries }
    state['required_queue_ids'] = queues if previous.key?('required_queue_ids') || queues.any?
    state
  end

  def valid_header?(value)
    keys = %w[entries required_queue_ids version]
    value.is_a?(Hash) && (value.keys - keys).empty? && value.key?('entries') &&
      value['version'].is_a?(Integer) && value['version'].between?(1, 2_147_483_647)
  end

  def validate_change!(previous, entries, queues, confirmed)
    removed = previous.fetch('entries').pluck('code') - entries.pluck('code')
    raise JrcContactCenter::OperationError, 'ending_reason_deactivation_required' if removed.any?

    validate_required!(entries, queues)
    added = queues - previous.fetch('required_queue_ids', [])
    return unless added.any? && confirmed != true

    raise JrcContactCenter::OperationError, 'ending_reason_queue_confirmation_required'
  end

  def validate_required!(entries, queues)
    return if queues.empty? || entries.any? { |entry| entry.fetch('active') }

    raise JrcContactCenter::OperationError, 'active_ending_reason_required'
  end

  def validated_queue_ids(values)
    invalid! unless values.is_a?(Array) && values.length <= MAX_ENTRIES
    ids = values.map do |value|
      invalid! unless queue_identifier?(value)
      value.to_s
    end
    invalid! unless ids.uniq.length == ids.length
    JrcContactCenter::Queue.where(account: @account).find(ids) if ids.any?
    ids.sort
  end

  # Historical queue identifiers are retained after native queue deletion; they are not grants.
  def stored_queue_ids?(values)
    return false unless values.is_a?(Array) && values.length <= MAX_ENTRIES && values.all?(String)
    return false unless values == values.uniq.sort

    values.all? do |id|
      queue_identifier?(id)
    end
  end

  def queue_identifier?(value)
    (value.is_a?(Integer) || value.is_a?(String)) && value.to_s.match?(/\A[1-9]\d{0,18}\z/) && value.to_i <= 9_223_372_036_854_775_807
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
