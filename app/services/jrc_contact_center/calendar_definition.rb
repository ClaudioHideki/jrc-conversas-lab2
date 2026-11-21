# frozen_string_literal: true

# Call Center metadata adapter; calculation and interval validation remain native to SnapshotCalendar.
# Explicit holiday dates are selected by the operator, never fabricated from a locality or movable-date formula.
class JrcContactCenter::CalendarDefinition
  FIELDS = %w[name description timezone weekly holidays exceptions].freeze
  HOLIDAY_KINDS = %w[national state municipal internal].freeze
  HOLIDAY_TYPES = %w[fixed movable].freeze
  MAX_BYTES = 65_536

  def initialize(input)
    valid = input.is_a?(Hash) && input.keys.all?(String) && input.keys.sort == FIELDS.sort && input.to_json.bytesize <= MAX_BYTES
    invalid! unless valid

    @values = input.deep_dup
    @values['name'] = text!(@values.fetch('name'), 120)
    @values['description'] = text!(@values.fetch('description'), 1000, empty: true)
    @holidays = holiday_rows(@values.fetch('holidays'))
    @exceptions = exception_rows(@values.fetch('exceptions'))
    @calendar = JrcServiceDesk::SnapshotCalendar.new(timezone: @values.fetch('timezone'), conditions: conditions)
  rescue JrcServiceDesk::LifecycleDependencyError
    invalid!
  end

  def values
    @values.deep_dup
  end

  def conditions
    { 'format' => JrcServiceDesk::SnapshotCalendar::VERSION, 'weekly' => @values.fetch('weekly').deep_dup,
      'holidays' => @holidays.map { |row| row.fetch('date') },
      'exceptions' => @exceptions.to_h { |row| [row.fetch('date'), row.fetch('intervals').deep_dup] } }
  end

  def preview(date)
    day = date!(date)
    first, finish = day_boundaries(day)
    kind, pairs = effective_intervals(date, day)
    { 'date' => date, 'timezone' => @values.fetch('timezone'), 'precedence' => kind, 'intervals' => pairs,
      'working_seconds' => @calendar.elapsed(first, finish).to_i, 'local_only' => true, 'pabx_confirmed' => false }
  rescue ArgumentError, TypeError, TZInfo::InvalidTimezoneIdentifier, TZInfo::PeriodNotFound, TZInfo::AmbiguousTime,
         JrcServiceDesk::LifecycleDependencyError
    invalid!
  end

  private

  def date!(value)
    date = Date.iso8601(value)
    invalid! unless value.is_a?(String) && date.iso8601 == value

    date
  end

  def day_boundaries(day)
    zone = TZInfo::Timezone.get(@values.fetch('timezone'))
    [day, day.next_day].map { |date| zone.local_to_utc(Time.utc(date.year, date.month, date.day), nil) }
  end

  def effective_intervals(date, day)
    exception = @exceptions.find { |row| row.fetch('date') == date }
    return ['exception', exception.fetch('intervals').deep_dup] if exception
    return ['holiday', []] if @holidays.any? { |row| row.fetch('date') == date }

    ['weekly', @values.fetch('weekly').fetch(day.cwday.to_s).deep_dup]
  end

  def text!(value, maximum, empty: false)
    invalid! unless value.is_a?(String) && value.length <= maximum
    result = value.strip
    invalid! if !empty && result.empty?

    result
  end

  def holiday_rows(input)
    rows = rows!(input, %w[date name kind type])
    rows.each do |row|
      row['name'] = text!(row.fetch('name'), 120)
      invalid! unless HOLIDAY_KINDS.include?(row.fetch('kind')) && HOLIDAY_TYPES.include?(row.fetch('type'))
    end
    @values['holidays'] = rows
  end

  def exception_rows(input)
    rows = rows!(input, %w[date name intervals])
    rows.each { |row| row['name'] = text!(row.fetch('name'), 120) }
    @values['exceptions'] = rows
  end

  def rows!(input, fields)
    invalid! unless input.is_a?(Array) && input.length <= 1000
    invalid! unless input.all? { |row| row.is_a?(Hash) && row.keys.all?(String) && row.keys.sort == fields.sort }
    dates = input.map { |row| row.fetch('date') }
    invalid! unless dates.uniq.length == dates.length

    input.deep_dup
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar'
  end
end
