# Weekly periods use the inbox timezone. Overnight periods wrap across weekdays.
class JrcHumanAssignment::AgentSchedule
  WEEK_MINUTES = 7 * 24 * 60
  DAYS = (0..6).map(&:to_s).freeze
  CLOCK = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/

  def self.validate!(schedules)
    raise ArgumentError unless schedules.is_a?(Hash) && schedules.size <= 1000

    schedules.each do |user_id, days|
      raise ArgumentError unless user_id.is_a?(String) && user_id.match?(/\A[1-9]\d*\z/)

      validate_days!(days)
    end
  end

  def self.validate_days!(days)
    raise ArgumentError unless days.is_a?(Hash) && days.keys.sort == DAYS
    raise ArgumentError unless days.values.all? { |periods| valid_periods?(periods) }

    ranges = new(days).ranges
    raise ArgumentError if ranges.each_cons(2).any? { |first, second| first.last > second.first }
  end
  private_class_method :validate_days!

  def self.valid_periods?(periods)
    periods.is_a?(Array) && periods.size <= 4 && periods.all? { |period| valid_period?(period) }
  end
  private_class_method :valid_periods?

  def self.valid_period?(period)
    period.is_a?(Hash) && period.keys.sort == %w[end start] && valid_clock?(period['start']) &&
      valid_end_clock?(period['end']) && period['start'] != period['end']
  end
  private_class_method :valid_period?

  def self.valid_clock?(value)
    value.is_a?(String) && CLOCK.match?(value)
  end
  private_class_method :valid_clock?

  def self.valid_end_clock?(value)
    valid_clock?(value) || value == '24:00'
  end
  private_class_method :valid_end_clock?

  def initialize(days)
    @days = days
  end

  def open?(time:, timezone:)
    return true if @days.nil?

    local = time.in_time_zone(timezone)
    minute = (local.wday * 1440) + (local.hour * 60) + local.min
    ranges.any? { |start_minute, end_minute| minute >= start_minute && minute < end_minute }
  end

  def ranges
    @ranges ||= @days.flat_map do |day, periods|
      periods.flat_map { |period| period_ranges(day.to_i, period) }
    end.sort_by(&:first)
  end

  private

  def period_ranges(day, period)
    start_clock = minutes(period.fetch('start'))
    end_clock = minutes(period.fetch('end'))
    start_minute = (day * 1440) + start_clock
    end_minute = (day * 1440) + end_clock + (end_clock <= start_clock ? 1440 : 0)
    return [[start_minute, end_minute]] if end_minute <= WEEK_MINUTES

    [[start_minute, WEEK_MINUTES], [0, end_minute - WEEK_MINUTES]]
  end

  def minutes(clock)
    hour, minute = clock.split(':').map(&:to_i)
    (hour * 60) + minute
  end
end
