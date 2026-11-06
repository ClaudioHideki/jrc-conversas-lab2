# Shared report/action dates; legacy start-only input remains a single day.
class JrcRelationship::OperationalPeriod
  class Invalid < ArgumentError; end

  def self.call(params)
    from = parse_date(params[:from])
    to = parse_date(params[:to])
    return if [from, to].all?(&:nil?)
    raise Invalid, 'Select a start date before applying an end date' unless from

    to ||= from
    raise Invalid, 'Invalid period' if to < from || (to - from).to_i > 366

    from.beginning_of_day..to.end_of_day
  end

  def self.parse_date(value)
    return if value.nil?
    raise Invalid, 'Invalid period dates' unless value.is_a?(String)
    return if value.blank?

    Date.iso8601(value)
  rescue Date::Error
    raise Invalid, 'Invalid period dates'
  end
  private_class_method :parse_date
end
