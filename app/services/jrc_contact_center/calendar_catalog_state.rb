# frozen_string_literal: true

# A bounded catalog in the native unit's existing JSONB settings; no synthetic units or parallel calendar database.
class JrcContactCenter::CalendarCatalogState
  KEY = 'jrc_contact_center_calendars_v1'
  MAX_ENTRIES = 100
  MAX_BYTES = 262_144
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  def initialize(unit:)
    @unit = unit
  end

  def call
    return { 'version' => 0, 'scope_snapshot' => scope, 'entries' => [] } unless @unit.settings.key?(KEY)

    validate!(@unit.settings.fetch(KEY))
  end

  def validate!(state)
    header = state.is_a?(Hash) && state.keys.all?(String) && state.keys.sort == %w[entries scope_snapshot version] &&
             state['version'].is_a?(Integer) && state['version'].positive? && state.to_json.bytesize <= MAX_BYTES
    invalid! unless header && state['scope_snapshot'] == scope
    entries = state.fetch('entries')
    invalid! unless entries.is_a?(Array) && entries.length <= MAX_ENTRIES
    ids = entries.map { |row| entry!(row).fetch('id') }
    invalid! unless ids.uniq.length == ids.length

    state.deep_dup
  end

  def entry!(input)
    valid = input.is_a?(Hash) && input.keys.all?(String) && input.keys.sort == %w[active definition id] &&
            input['id'].is_a?(String) && UUID.match?(input['id']) && [true, false].include?(input['active'])
    invalid! unless valid
    definition = JrcContactCenter::CalendarDefinition.new(input.fetch('definition')).values
    normalized = input.merge('definition' => definition)
    invalid! unless normalized == input

    normalized.deep_dup
  end

  def scope
    JrcContactCenter::ConfigurationAuditSnapshot.capture(@unit).fetch('scope')
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_catalog'
  end
end
