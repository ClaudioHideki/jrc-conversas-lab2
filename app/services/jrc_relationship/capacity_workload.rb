require 'bigdecimal/util'

# Explicit business inputs only. Hours are supplied equivalent hours; no
# currency/day/hour conversion or illustrative Word weights become defaults.
class JrcRelationship::CapacityWorkload
  class Unavailable < StandardError; end
  FACTORS = %w[base complexity_factor risk_factor journey_factor activity_effort].freeze
  UNITS = %w[customers points hours].freeze
  MAXIMUM = 9_007_199_254_740_991

  def self.numeric?(value)
    value.is_a?(Numeric) && value.finite? && value.between?(0, MAXIMUM)
  end

  def self.validate!(settings)
    values = settings.fetch('capacity_workload', {})
    raise Unavailable, 'Explicit capacity workload must use points or hours' unless values.is_a?(Hash) && (values.keys - %w[points hours]).empty?

    values.each_key { |unit| value(settings, unit) }
    true
  end

  def self.value(settings, unit)
    return 1.to_d if unit == 'customers'

    values = settings.fetch('capacity_workload', {})
    raise Unavailable, 'Configure explicit workload inputs' unless values.is_a?(Hash)

    result = unit == 'points' ? point_value(values[unit]) : values[unit]
    raise Unavailable, 'Configure explicit valid workload inputs for the selected capacity unit' unless numeric?(result)

    result.to_d
  end

  def self.point_value(raw)
    valid = raw.is_a?(Hash) && raw.keys.sort == FACTORS.sort && raw.values.all? { |number| numeric?(number) }
    raise Unavailable, 'All explicit point factors are required' unless valid

    (raw.fetch('base').to_d * raw.fetch('complexity_factor').to_d * raw.fetch('risk_factor').to_d *
      raw.fetch('journey_factor').to_d) + raw.fetch('activity_effort').to_d
  end

  def self.sum(records, unit)
    total = 0.to_d
    records.find_each { |record| total += value(record.settings, unit) }
    total
  end
end
