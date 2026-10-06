class JrcRelationship::RenewalWindow
  WINDOWS = { 'overdue' => [nil, -1], '15' => [0, 15], '30' => [16, 30], '60' => [31, 60],
              '90' => [61, 90], '120' => [91, 120], 'later' => [121, nil] }.freeze

  def self.key(date, today: Date.current)
    return nil unless date
    days = (date - today).to_i
    WINDOWS.find { |_key, (from, to)| (!from || days >= from) && (!to || days <= to) }&.first
  end

  def self.scope(relation, key, today: Date.current)
    from, to = WINDOWS.fetch(key.to_s)
    range = from.nil? ? (...(today + to + 1)) : to.nil? ? ((today + from)..) : ((today + from)..(today + to))
    relation.where(renewal_on: range)
  end
end
