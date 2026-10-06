# Uses evidenced measurements entered on the existing Success Plan goals; absent telemetry is never invented.
class JrcRelationship::AdoptionMetric
  def self.growth(goals:, metric:)
    goals.filter_map do |row|
      baseline, current = Float(row['baseline'], exception: false), Float(row['current'], exception: false)
      next unless row['metric'] == metric && !row['evidence'].to_s.strip.empty? && baseline&.positive? && baseline.finite? && current&.finite?
      { percent: 100.0 * (current - baseline) / baseline, baseline: baseline, current: current,
        product_id: row['product_id'], evidence: row['evidence'] }
    end.max_by { |row| row[:percent] }
  end

  def self.call(goals:, metric:, product_id: nil)
    rows = goals.select do |goal|
      goal['metric'] == metric && !goal['evidence'].to_s.strip.empty? &&
        (!product_id || goal['product_id'].to_s == product_id.to_s) &&
        Float(goal['target'], exception: false)&.positive? && Float(goal['target'], exception: false)&.finite? &&
        Float(goal['current'], exception: false)&.finite?
    end
    return { raw: nil, normalized: nil, evidence: 'No evidenced adoption measurement configured' } if rows.empty?

    scores = rows.map { |row| (Float(row['current']) * 100 / Float(row['target'])).clamp(0, 100) }
    { raw: rows.map { |row| row.slice('metric', 'target', 'current', 'product_id') },
      normalized: scores.sum / scores.size, evidence: rows.map { |row| row['evidence'] }.join('; ') }
  end
end
