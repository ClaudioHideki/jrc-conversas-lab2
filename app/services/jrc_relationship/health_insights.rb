class JrcRelationship::HealthInsights
  def initialize(scope:, snapshots:, latest:, period:)
    @scope, @snapshots, @latest, @period = scope, snapshots, latest, period || (30.days.ago..Time.current)
  end

  def call
    baseline = @snapshots.where('calculated_at <= ?', @period.begin)
    baseline = baseline.where(id: baseline.select('MAX(id) AS id').group(:assignment_id)).index_by(&:assignment_id)
    earliest = @snapshots.where(calculated_at: @period)
      .select('DISTINCT ON (assignment_id) jrc_relationship_health_snapshots.*').order(:assignment_id, :calculated_at, :id).index_by(&:assignment_id)
    names = @scope.pluck(:id, :company_id, :contact_id)
    companies = JrcCustomers::Company.where(id: names.filter_map { |row| row[1] }).pluck(:id, :name).to_h
    contacts = Contact.where(id: names.filter_map { |row| row[2] }).pluck(:id, :name).to_h
    labels = names.to_h { |id, company, contact| [id, company ? companies[company] : contacts[contact]] }
    comparison = @snapshots.where('calculated_at <= ?', @period.end)
    comparison = comparison.where(id: comparison.select('MAX(id) AS id').group(:assignment_id))
    changes = comparison.filter_map do |snapshot|
      before = baseline[snapshot.assignment_id] || earliest[snapshot.assignment_id]
      change = JrcRelationship::HealthChange.call(previous: before&.attributes&.symbolize_keys, current: snapshot.attributes.symbolize_keys)
      next unless change && !change[:delta].zero?
      change.merge(assignment_id: snapshot.assignment_id, customer: labels[snapshot.assignment_id],
        from: before.calculated_at, to: snapshot.calculated_at)
    end
    positive = @latest.flat_map(&:factors).select { |row| row['available'] && row['normalized'].to_f >= 80 }
      .group_by { |row| row['factor'] }.map do |factor, rows|
        { factor: factor, customers: rows.size, average: (rows.sum { |row| row['normalized'].to_f } / rows.size).round(1) }
      end.sort_by { |row| -row[:average] }
    { most_declined: changes.select { |row| row[:delta].negative? }.sort_by { |row| row[:delta] }.first(10),
      most_improved: changes.select { |row| row[:delta].positive? }.sort_by { |row| -row[:delta] }.first(10),
      positive_factors: positive, health_comparison_period: { from: @period.begin, to: @period.end } }
  end
end
