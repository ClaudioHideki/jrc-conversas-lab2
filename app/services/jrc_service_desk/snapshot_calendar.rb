# frozen_string_literal: true

require 'date'
require 'time'

# A closed versioned contract, never an Inbox/calendar fallback. UTC is storage only.
# A DST ambiguous/nonexistent interval boundary is rejected instead of choosing an offset.
class JrcServiceDesk::SnapshotCalendar
  VERSION = 'jrc-sd-snapshot-calendar-v1'
  MAX_DAYS = 3660 # Execution safety bound, not an SLA/business default.

  def initialize(timezone:, conditions:, zone: nil)
    raise ArgumentError, 'An explicit timezone identifier is required' unless timezone.is_a?(String) && !timezone.strip.empty?
    @zone = zone || resolve_zone(timezone)
    @conditions = JrcServiceDesk::Input.attributes(conditions, %w[format weekly holidays exceptions])
    raise ArgumentError, 'Unsupported snapshot calendar format' unless @conditions['format'] == VERSION
    @weekly = @conditions.fetch('weekly'); @holidays = @conditions.fetch('holidays'); @exceptions = @conditions.fetch('exceptions')
    raise ArgumentError, 'All seven weekdays must be explicit' unless @weekly.is_a?(Hash) && @weekly.keys.sort == (1..7).map(&:to_s).sort
    @weekly.each_value { |intervals| validate_intervals(intervals) }
    raise ArgumentError, 'Calendar holidays/exceptions required' unless @holidays.is_a?(Array) && @exceptions.is_a?(Hash)
    raise ArgumentError, 'Calendar too large' if @holidays.length > 10000 || @exceptions.length > 10000
    @holidays.each { |date| validate_date(date) }
    @exceptions.each { |date, intervals| validate_date(date); validate_intervals(intervals) }
    raise ArgumentError, 'No working intervals configured' if @weekly.values.all?(&:empty?) && @exceptions.values.all?(&:empty?)
  rescue ArgumentError, KeyError => e
    raise JrcServiceDesk::LifecycleDependencyError, "Calendar configuration required: #{e.message}"
  end

  def elapsed(start_at, end_at)
    raise ArgumentError, 'Invalid clock interval' if end_at < start_at
    return 0.0 if start_at == end_at
    dates(start_at, end_at).sum do |date|
      intervals(date).sum { |first, last| [([last, end_at].min - [first, start_at].max), 0.0].max }
    end
  end

  def advance(start_at, seconds)
    raise ArgumentError, 'Positive remaining duration required' unless seconds.is_a?(Numeric) && seconds.positive? && seconds.finite?
    remaining = seconds.to_f
    first_date = @zone.to_local(start_at).to_date
    MAX_DAYS.times do |index|
      intervals(first_date + index).each do |first, last|
        from = [first, start_at].max
        next if from >= last
        capacity = last - from
        return from + remaining if remaining <= capacity
        remaining -= capacity
      end
    end
    raise JrcServiceDesk::LifecycleDependencyError, 'Calendar horizon exhausted; no deadline was fabricated'
  end

  private

  def resolve_zone(timezone)
    TZInfo::Timezone.get(timezone)
  rescue TZInfo::InvalidTimezoneIdentifier
    raise JrcServiceDesk::LifecycleDependencyError, 'Unsupported explicit timezone identifier'
  end

  def dates(start_at, end_at)
    first = @zone.to_local(start_at).to_date; last = @zone.to_local(end_at).to_date
    raise JrcServiceDesk::LifecycleDependencyError, 'Calendar interval exceeds processing bound' if last - first >= MAX_DAYS
    (first..last)
  end

  def validate_date(value)
    raise ArgumentError, 'ISO calendar date required' unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value).iso8601 == value
  end

  def minute(value)
    raise ArgumentError, 'HH:MM interval boundary required' unless value.is_a?(String) && value.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z|\A24:00\z/)
    h, m = value.split(':').map(&:to_i); h * 60 + m
  end

  def validate_intervals(values)
    raise ArgumentError, 'Calendar intervals must be explicit' unless values.is_a?(Array) && values.size <= 48
    previous = -1
    values.each do |pair|
      raise ArgumentError, 'Calendar interval pair required' unless pair.is_a?(Array) && pair.length == 2
      a, b = pair.map { |value| minute(value) }
      raise ArgumentError, 'Overlapping/unordered/overnight intervals not supported; split per date' unless a < b && a >= previous
      previous = b
    end
  end

  def intervals(date)
    key = date.iso8601
    configured = if @exceptions.key?(key)
                   @exceptions.fetch(key)
                 elsif @holidays.include?(key)
                   []
                 else
                   @weekly.fetch(date.cwday.to_s)
                 end
    configured.map do |pair|
      pair.map do |value|
        offset = minute(value)
        local = Time.utc(date.year, date.month, date.day) + offset * 60
        @zone.local_to_utc(local, nil) # TZInfo raises when a local boundary is not unique.
      rescue StandardError => e
        raise JrcServiceDesk::LifecycleDependencyError, "Calendar boundary cannot be interpreted: #{e.class.name}"
      end
    end
  end
end
