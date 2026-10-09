# frozen_string_literal: true

# Shared native calendar predicate for dispatch and approved continuations.
class JrcFlows::BusinessHours
  def self.open?(settings, at: Time.current)
    return true unless settings['business_hours'] == true

    valid = ActiveSupport::TimeZone[settings['timezone']] && %w[opens_at closes_at].all? do |key|
      settings[key].is_a?(String) && settings[key].match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)
    end
    raise ArgumentError, 'native_flow_calendar_invalid' unless valid

    local = at.in_time_zone(settings.fetch('timezone'))
    return false unless Array(settings['days']).include?(local.wday)

    time = local.strftime('%H:%M')
    opens, closes = settings.values_at('opens_at', 'closes_at')
    opens <= closes ? (opens <= time && time < closes) : (time >= opens || time < closes)
  end
end
