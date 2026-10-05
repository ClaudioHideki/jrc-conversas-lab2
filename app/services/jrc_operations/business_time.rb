module JrcOperations
  class BusinessTime
    DEFAULT_WEEKDAYS = [1, 2, 3, 4, 5].freeze

    def initialize(config)
      @config = (config || {}).with_indifferent_access
      @weekdays = Array(@config[:weekdays]).presence&.map(&:to_i) || DEFAULT_WEEKDAYS
      @start_hour, @start_minute = parse_clock(@config[:start].presence || '08:00')
      @end_hour, @end_minute = parse_clock(@config[:end].presence || '18:00')
      @holidays = Array(@config[:holidays]).map(&:to_s).to_set
      @enabled = ActiveModel::Type::Boolean.new.cast(@config.fetch(:enabled, false))
      if @enabled && (!@weekdays.any? { |day| (0..6).cover?(day) } ||
                      @end_hour * 60 + @end_minute <= @start_hour * 60 + @start_minute)
        raise ArgumentError, 'Invalid business calendar'
      end
    end

    def add_minutes(time, minutes)
      return nil if minutes.blank?
      return time + minutes.to_f.minutes unless @enabled

      remaining = minutes.to_f
      cursor = normalize_start(time)
      while remaining.positive?
        day_end = cursor.change(hour: @end_hour, min: @end_minute, sec: 0)
        available = [(day_end - cursor) / 60, 0].max
        if available >= remaining
          return cursor + remaining.minutes
        end
        remaining -= available
        cursor = normalize_start((cursor + 1.day).beginning_of_day)
      end
      cursor
    end

    def seconds_between(start_time, end_time)
      return 0 if end_time <= start_time
      return end_time - start_time unless @enabled

      cursor = normalize_start(start_time)
      seconds = 0
      while cursor < end_time
        day_end = cursor.change(hour: @end_hour, min: @end_minute, sec: 0)
        seconds += [day_end, end_time].min - cursor
        cursor = normalize_start((cursor + 1.day).beginning_of_day)
      end
      seconds
    end

    private

    def normalize_start(time)
      cursor = time.in_time_zone
      loop do
        if business_day?(cursor)
          day_start = cursor.change(hour: @start_hour, min: @start_minute, sec: 0)
          day_end = cursor.change(hour: @end_hour, min: @end_minute, sec: 0)
          return day_start if cursor < day_start
          return cursor if cursor < day_end
        end
        cursor = (cursor + 1.day).beginning_of_day
      end
    end

    def business_day?(time)
      @weekdays.include?(time.wday) && !@holidays.include?(time.to_date.iso8601)
    end

    def parse_clock(value)
      hour, minute = value.to_s.split(':', 2).map(&:to_i)
      [[hour, 0].max.clamp(0, 23), [minute, 0].max.clamp(0, 59)]
    end
  end
end
