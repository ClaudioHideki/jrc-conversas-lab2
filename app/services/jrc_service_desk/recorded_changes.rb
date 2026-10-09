# frozen_string_literal: true

module JrcServiceDesk::RecordedChanges
  def self.call(value)
    case value
    when Hash then value.transform_values { |item| call(item) }
    when Array then value.map { |item| call(item) }
    when Time, DateTime, ActiveSupport::TimeWithZone then value.iso8601(6)
    else value
    end
  end
end
