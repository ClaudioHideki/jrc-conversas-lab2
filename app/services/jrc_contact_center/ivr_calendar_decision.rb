# frozen_string_literal: true

# Explicit instant, native calendar math, no implicit server clock or provider command.
class JrcContactCenter::IvrCalendarDecision
  def initialize(reference)
    @reference = reference
    @snapshot = reference.fetch('snapshot')
    @definition = JrcContactCenter::CalendarDefinition.new(@snapshot.fetch('definition'))
    @zone = TZInfo::Timezone.get(@definition.values.fetch('timezone'))
    @calendar = JrcServiceDesk::SnapshotCalendar.new(timezone: @definition.values.fetch('timezone'), conditions: @definition.conditions)
  end

  def call(instant:)
    time = JrcContactCenter::IvrSimulationInstant.parse(instant)
    date = @zone.to_local(time).to_date.iso8601
    preview = @definition.preview(date)
    { 'calendar_id' => @reference.fetch('calendar_id'), 'sha256' => @reference.fetch('sha256'),
      'instant' => time.iso8601, 'local_date' => date, 'timezone' => preview.fetch('timezone'),
      'precedence' => preview.fetch('precedence'), 'open' => @calendar.elapsed(time, time + 1).positive?,
      'snapshot_active' => @snapshot.fetch('active'), 'local_only' => true, 'provider_applied' => false }
  rescue JrcServiceDesk::LifecycleDependencyError
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar'
  end
end
