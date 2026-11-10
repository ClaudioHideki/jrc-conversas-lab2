require 'bigdecimal/util'

class JrcRelationship::DistributionCapacityPolicy
  FIELDS = %w[user_id maximum availability dedication].freeze

  def self.validate!(account, limits)
    valid = limits.is_a?(Array) && limits.to_json.bytesize <= 128.kilobytes && limits.all? { |entry| valid_entry?(entry) }
    raise ArgumentError, 'Capacity limits require existing users, whole customer limits and availability/dedication from0 to1' unless valid

    ids = limits.pluck('user_id')
    unless ids.uniq.size == ids.size && account.users.where(id: ids).count == ids.size
      raise ArgumentError, 'Capacity users must be unique members of this account'
    end

    true
  end

  def self.valid_entry?(entry)
    return false unless valid_fields?(entry)
    return false unless JrcRelationship::CapacityWorkload::UNITS.include?(entry.fetch('unit', 'customers'))

    valid_identity?(entry) && %w[availability dedication].all? do |key|
      value = entry[key]
      value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
    end
  end

  def self.valid_fields?(entry)
    entry.is_a?(Hash) && (entry.keys.sort == FIELDS.sort || entry.keys.sort == (FIELDS + ['unit']).sort)
  end

  def self.valid_identity?(entry)
    maximum = entry['maximum']
    valid = JrcRelationship::CapacityWorkload.numeric?(maximum)
    valid &&= maximum.is_a?(Integer) if entry.fetch('unit', 'customers') == 'customers'
    entry['user_id'].is_a?(Integer) && entry['user_id'].positive? && valid
  end

  def self.effective(entry)
    value = entry.fetch('maximum').to_d * entry.fetch('availability').to_d * entry.fetch('dedication').to_d
    entry.fetch('unit', 'customers') == 'customers' ? value.floor : value
  end
end
