class JrcRelationship::RenewalWindow
  WINDOWS = { 'overdue' => [nil, -1], '15' => [0, 15], '30' => [16, 30], '60' => [31, 60],
              '90' => [61, 90], '120' => [91, 120], 'later' => [121, nil] }.freeze

  def self.horizon(rules)
    [rules['renewal_days'], rules['renewal_window_days'].last].max
  end

  def self.ranges(rules: nil)
    limits = rules&.fetch('renewal_window_days', nil)
    return WINDOWS unless limits

    lower = 0
    windows = { 'overdue' => [nil, -1] }
    %w[15 30 60 90 120].zip(limits).each do |key, upper|
      windows[key] = [lower, upper]
      lower = upper + 1
    end
    windows.merge('later' => [lower, nil])
  end

  def self.key(date, today: Date.current, rules: nil)
    return nil unless date

    days = (date - today).to_i
    ranges(rules: rules).find { |_key, (from, to)| (!from || days >= from) && (!to || days <= to) }&.first
  end

  def self.scope(relation, key, today: Date.current, rules: nil)
    from, to = ranges(rules: rules).fetch(key.to_s)
    range = from.nil? ? (...(today + to + 1)) : to.nil? ? ((today + from)..) : ((today + from)..(today + to))
    relation.where(renewal_on: range)
  end
end
