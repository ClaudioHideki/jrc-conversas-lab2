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
    return false unless entry.is_a?(Hash) && entry.keys.sort == FIELDS.sort

    valid_identity?(entry) && %w[availability dedication].all? do |key|
      value = entry[key]
      value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
    end
  end

  def self.valid_identity?(entry)
    entry['user_id'].is_a?(Integer) && entry['user_id'].positive? &&
      entry['maximum'].is_a?(Integer) && entry['maximum'].between?(0, 9_007_199_254_740_991)
  end

  def self.effective(entry)
    (entry.fetch('maximum').to_d * entry.fetch('availability').to_d * entry.fetch('dedication').to_d).floor
  end
end
