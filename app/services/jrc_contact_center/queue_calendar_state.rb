# frozen_string_literal: true

# One explicitly reviewed internal draft association per native queue. Never a provider-applied calendar.
class JrcContactCenter::QueueCalendarState
  KEY = 'jrc_contact_center_queue_calendar_v1'
  FORMAT = 'jrc-cc-queue-calendar-v1'
  FIELDS = %w[format id calendar_snapshot calendar_digest scope_snapshot request_digest].freeze

  def initialize(queue:)
    @queue = queue
    @unit = JrcContactCenter::Unit.find_by!(account_id: queue.account_id, id: queue.unit_id)
  end

  def call
    return unless @queue.settings.key?(KEY)

    validate!(@queue.settings.fetch(KEY))
  end

  def validate!(value)
    invalid! unless header?(value)
    invalid! unless identifiers?(value)
    invalid! unless value.fetch('scope_snapshot') == JrcContactCenter::ConfigurationAuditSnapshot.capture(@queue).fetch('scope')
    snapshot = JrcContactCenter::CalendarCatalogState.new(unit: @unit).entry!(value.fetch('calendar_snapshot'))
    invalid! unless value.fetch('calendar_digest') == JrcContactCenter::ConfigurationRevision.content_token(snapshot)

    value.deep_dup
  end

  def build(input, snapshot:)
    { 'format' => FORMAT, 'id' => input.fetch('idempotency_key'), 'calendar_snapshot' => snapshot.deep_dup,
      'calendar_digest' => JrcContactCenter::ConfigurationRevision.content_token(snapshot),
      'scope_snapshot' => JrcContactCenter::ConfigurationAuditSnapshot.capture(@queue).fetch('scope'),
      'request_digest' => JrcContactCenter::ConfigurationRevision.content_token(input) }
  end

  private

  def header?(value)
    value.is_a?(Hash) && value.keys.all?(String) && value.keys.sort == FIELDS.sort && value['format'] == FORMAT &&
      value.to_json.bytesize <= 70_000
  end

  def identifiers?(value)
    value['id'].is_a?(String) && JrcContactCenter::CalendarCatalogState::UUID.match?(value['id']) &&
      digest?(value['calendar_digest']) && digest?(value['request_digest'])
  end

  def digest?(value)
    value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding'
  end
end
