class JrcRelationship::HealthChange
  def self.call(previous:, current:)
    return nil unless previous && current && previous[:score] && current[:score]
    old = Array(previous[:factors]).to_h { |factor| [factor['factor'] || factor[:factor], factor.transform_keys(&:to_sym)] }
    now = Array(current[:factors]).to_h { |factor| [factor['factor'] || factor[:factor], factor.transform_keys(&:to_sym)] }
    factors = (old.keys | now.keys).filter_map do |name|
      row = now[name]
      before = old[name]
      next if before == row
      { factor: name, before: before&.slice(:raw, :normalized, :weight, :contribution, :evidence),
        after: row&.slice(:raw, :normalized, :weight, :contribution, :evidence),
        delta: before&.dig(:contribution) && row&.dig(:contribution) ? (row[:contribution] - before[:contribution]).round(4) : nil }
    end
    { previous: previous[:score].to_f, current: current[:score].to_f,
      delta: (current[:score].to_f - previous[:score].to_f).round(2),
      configuration_changed: [previous[:config_scope_key], previous[:config_version]] != [current[:config_scope_key], current[:config_version]],
      factors: factors }
  end
end
