# Observations are historical recurring amounts, never cash receipts or inferred days.
class JrcRelationship::RevenueEvolution
  MAX_OBSERVATIONS = 10_000

  def initialize(context:, scope:, period: nil)
    @context = JrcRelationship::Context.new(context.member)
    @scope = @context.assignments.where(id: scope.reselect(:id)).includes(:company, :contact)
    @period = period || (30.days.ago..Time.current)
    @timezone = Time.find_zone(@context.account.reporting_timezone) || Time.zone
  end

  def call
    raise ArgumentError, 'Invalid revenue period' if @period.end < @period.begin || (@period.end.to_date - @period.begin.to_date).to_i > 366

    result = { basis: 'observed_recurring_snapshots', timezone: @timezone.tzinfo.name,
               period: { from: @period.begin, to: @period.end }, points: [] }
    return result.merge(reason: 'financial_access_unavailable') unless JrcOperations::Access.crm?(@context.member)

    @assignments = @scope.index_by(&:id)
    @customers = @assignments.values.index_by { |assignment| customer_key(assignment) }
    result[:eligible_customers] = @customers.size
    observations = daily_observations.to_a
    return result.merge(reason: 'observation_limit', observation_limit: MAX_OBSERVATIONS) if observations.size > MAX_OBSERVATIONS

    points = observations.group_by { |snapshot| snapshot.calculated_at.in_time_zone(@timezone).to_date }
                         .sort.map { |day, snapshots| point(day, snapshots) }
    result.merge(points: points, reason: points.empty? ? 'no_observations' : nil)
  end

  private

  def daily_observations
    rows = JrcRelationship::HealthSnapshot.where(account: @context.account, viewer: @context.user,
                                                  assignment_id: @assignments.keys, access_signature: @context.access_signature,
                                                  calculated_at: @period)
    rows = JrcRelationship::SnapshotAccess.scope(@context, rows)
    timezone = ActiveRecord::Base.connection.quote(@timezone.tzinfo.name)
    day = "DATE(calculated_at AT TIME ZONE 'UTC' AT TIME ZONE #{timezone})"
    ids = rows.select("DISTINCT ON (assignment_id, #{day}) id").order(Arel.sql("assignment_id, #{day}, calculated_at DESC, id DESC"))
    rows.where(id: ids).order(:calculated_at, :id).limit(MAX_OBSERVATIONS + 1)
  end

  def customer_key(assignment)
    assignment.company_id ? "company:#{assignment.company_id}" : "contact:#{assignment.contact_id}"
  end

  def point(day, snapshots)
    evidence = snapshots.map { |snapshot| customer_observation(snapshot) }
    exclude_overlapping_contracts!(evidence)
    covered = evidence.select { |row| row[:reason].nil? }
    subtotal = covered.empty? ? nil : covered.map { |row| [row[:contract_ids], row[:mrr_cents]] }.uniq.sum(&:last)
    complete = covered.size == @customers.size
    { day: day, observed_mrr_cents: subtotal, mrr_cents: complete ? subtotal : nil,
      coverage: { eligible: @customers.size, observed: evidence.size, covered: covered.size,
                  unknown: evidence.size - covered.size, missing: @customers.size - evidence.size, complete: complete },
      evidence: evidence }
  end

  def customer_observation(snapshot)
    key = customer_key(@assignments.fetch(snapshot.assignment_id))
    value = snapshot.signals['mrr_cents']
    contract_ids = Array(snapshot.signals.dig('_source_ids', 'contracts')).sort
    reason = observation_reason(key, value, contract_ids)
    { customer_key: key, assignment_ids: [snapshot.assignment_id], snapshot_ids: [snapshot.id],
      observed_at: snapshot.calculated_at, contract_ids: contract_ids,
      mrr_cents: reason ? nil : value, reason: reason }
  end

  def observation_reason(key, value, contract_ids)
    return 'amount_unavailable' unless value.is_a?(Integer) && value >= 0
    return 'amount_source_unavailable' if value.positive? && contract_ids.empty?
    return 'customer_source_changed' unless (contract_ids - customer_contract_ids(key)).empty?

    nil
  end

  def customer_contract_ids(key)
    @contract_ids ||= {}
    @contract_ids[key] ||= @customers.fetch(key).customer_context(@context.member).contracts.pluck(:id)
  end

  def exclude_overlapping_contracts!(evidence)
    owners = evidence.select { |row| row[:reason].nil? }.flat_map { |row| row[:contract_ids].map { |id| [id, row] } }.group_by(&:first)
    blocked = {}
    owners.each_value do |rows|
      observations = rows.map(&:last)
      next if observations.map { |row| [row[:contract_ids], row[:mrr_cents]] }.uniq.one?

      reason = observations.pluck(:contract_ids).uniq.one? ? 'conflicting_customer_observations' : 'overlapping_customer_sources'
      observations.each { |row| blocked[row[:customer_key]] = reason }
    end
    evidence.each { |row| row.merge!(mrr_cents: nil, reason: blocked.fetch(row[:customer_key])) if blocked.key?(row[:customer_key]) }
  end
end
