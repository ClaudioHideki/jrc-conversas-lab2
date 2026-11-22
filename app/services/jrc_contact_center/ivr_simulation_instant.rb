# frozen_string_literal: true

require 'date'

# One absolute instant. Named local times must be unique; never guess an offset or use Time.current.
class JrcContactCenter::IvrSimulationInstant
  ABSOLUTE = /\A\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z/
  LOCAL = /\A\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?\z/

  def self.parse(value)
    return DateTime.iso8601(value).to_time.utc if value.is_a?(String) && ABSOLUTE.match?(value)

    local_time(value)
  rescue ArgumentError, TypeError, TZInfo::InvalidTimezoneIdentifier, TZInfo::PeriodNotFound, TZInfo::AmbiguousTime
    raise JrcContactCenter::OperationError, 'ivr_calendar_instant_required'
  end

  def self.local_time(value)
    raise ArgumentError unless local_fields?(value)
    raise ArgumentError unless value.fetch('local').is_a?(String) && LOCAL.match?(value.fetch('local'))
    raise ArgumentError unless value.fetch('timezone').is_a?(String) && value.fetch('timezone').length.between?(1, 100)

    date = DateTime.iso8601("#{value.fetch('local')}Z")
    clock = Time.utc(date.year, date.month, date.day, date.hour, date.minute, date.second)
    TZInfo::Timezone.get(value.fetch('timezone')).local_to_utc(clock, nil)
  end

  def self.local_fields?(value)
    value.is_a?(Hash) && value.keys.all?(String) && value.keys.sort == %w[local timezone]
  end

  private_class_method :local_time, :local_fields?
end
