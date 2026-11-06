require 'digest'

# Viewer-scoped preview of actual allocation counts. Missing visibility is never
# presented as zero or as spare capacity. The same facts are checked at execution.
class JrcRelationship::DistributionCapacity
  def initialize(context)
    @context = context
    @sources = JrcRelationship::DistributionConfigurations.new(context.account)
  end

  def preview(inputs, records, applied_ids: [])
    return [] unless inputs['owner_id']

    configs = records.flat_map { |row| @sources.for(row) }.uniq(&:scope_key)
    configs.filter_map do |config|
      limits = config.effective_rules.fetch('portfolio_capacity_limits')
      next if limits.empty?

      fact(config, limits, inputs, records, applied_ids)
    end
  end

  def verify!(review)
    return unless review.inputs['operation'] == 'assign'

    actual = live_facts(review)
    raise Pundit::NotAuthorizedError if actual.any? { |row| row['blocker'] == 'capacity_scope_denied' }

    captured = review.snapshot.fetch('capacity', [])
    raise ArgumentError, 'Reviewed capacity changed. Create a new simulation.' unless actual == captured
    raise ArgumentError, 'Destination capacity is not available for this transfer' if actual.any? { |row| row['blocker'] }
  end

  # Current workload only: no proposed incoming customer and no admission receipt.
  def current_page(owner_id:, records:, page: 1, per_page: 10)
    number = Integer(page.to_s, 10).clamp(1, 10_000)
    size = Integer(per_page.to_s, 10).clamp(1, 20)
    configs = current_configurations(records)
    rows = configs.drop((number - 1) * size).first(size).map do |config|
      fact(config, config.effective_rules.fetch('portfolio_capacity_limits'), { 'owner_id' => owner_id, 'ids' => [] }, records, [])
        .except('baseline_digest', 'incoming', 'incoming_customers', 'projected')
    end
    { payload: rows, meta: { page: number, per_page: size, total: configs.size } }
  end

  def for_view(review)
    review.snapshot.fetch('capacity', []).map do |row|
      config = JrcRelationship::Configuration.new(account: @context.account, scope_key: row.fetch('scope_key'))
      pool = @sources.relation(config).where(owner_id: row.fetch('user_id'), status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
      if pool.where.not(id: @context.assignments.select(:id)).exists?
        row.slice('scope_key', 'user_id', 'unit').merge('blocker' => 'capacity_scope_denied')
      else
        row
      end
    end
  end

  private

  def current_configurations(records)
    configs = records.flat_map { |row| @sources.for(row) }.uniq(&:scope_key)
    configs = JrcRelationship::Configuration.where(account: @context.account, scope_key: 'account').to_a if records.empty?
    configs.reject { |config| config.effective_rules.fetch('portfolio_capacity_limits').empty? }.sort_by(&:scope_key)
  end

  def live_facts(review)
    records = @context.assignments.where(id: review.inputs.fetch('ids')).order(:id).to_a
    raise ActiveRecord::RecordNotFound unless records.size == review.inputs.fetch('ids').size

    preview(review.inputs, records, applied_ids: applied_ids(review))
  end

  def applied_ids(review)
    completed = review.items.where(state: 'applied').pluck(:assignment_id)
    review.snapshot.fetch('distribution', []).filter_map do |row|
      row['assignment_id'] if row['from_owner_id'] != review.inputs['owner_id'] && completed.include?(row['assignment_id'])
    end
  end

  def fact(config, limits, inputs, records, applied_ids)
    JrcRelationship::DistributionCapacityPolicy.validate!(@context.account, limits)
    entry = limits.find { |row| row['user_id'] == inputs['owner_id'] }
    result = capacity_identity(config, inputs['owner_id'], entry)
    return result.merge('blocker' => 'capacity_missing') unless entry

    pool = @sources.relation(config).where(status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
    target = pool.where(owner_id: inputs['owner_id'])
    visible = target.where(id: @context.assignments.select(:id))
    return result.merge('blocker' => 'capacity_scope_denied') unless target.count == visible.count

    sources = { records: records, applied_ids: applied_ids }
    counts = capacity_counts(pool, target, inputs, sources, result['unit'])
    capacity_result(result, entry, counts)
  rescue JrcRelationship::CapacityWorkload::Unavailable
    result.merge('blocker' => 'capacity_workload_missing')
  end

  def capacity_result(result, entry, counts)
    limit = JrcRelationship::DistributionCapacityPolicy.effective(entry)
    limit = limit.to_f if entry.fetch('unit', 'customers') != 'customers'
    incoming = counts.fetch('incoming_customers', counts.fetch('incoming'))
    unavailable = entry.fetch('availability').zero? || entry.fetch('dedication').zero?
    exceeded = incoming.positive? && (unavailable || counts.fetch('projected') > limit)
    result.merge(entry.except('user_id')).merge(counts).merge('effective_capacity' => limit,
                                                              'available_after' => limit - counts.fetch('projected'),
                                                              'blocker' => exceeded ? 'capacity_exceeded' : nil)
  end

  def capacity_identity(config, user_id, entry)
    { 'scope_key' => config.scope_key, 'configuration_version' => config.version, 'user_id' => user_id,
      'unit' => entry ? entry.fetch('unit', 'customers') : 'customers' }
  end

  def capacity_counts(pool, target, inputs, sources, unit)
    return counts(pool, target, inputs, sources.fetch(:records), sources.fetch(:applied_ids)) if unit == 'customers'

    original = sources.fetch(:records).select { |row| sources.fetch(:applied_ids).include?(row.id) }.map(&:id)
    JrcRelationship::WeightedCapacity.facts(pool: pool, target: target, inputs: inputs, applied_ids: original, unit: unit)
  end

  def counts(pool, target, inputs, records, applied_ids)
    original = records.select { |row| applied_ids.include?(row.id) }.map(&:id)
    # Already-owned no-op items were in the original baseline and must stay there.
    baseline = target.where.not(id: original)
    current, digest = baseline_digest(baseline)
    selected = pool.where(id: inputs.fetch('ids'))
    incoming_ids = selected.where.not(owner_id: inputs['owner_id']).or(selected.where(owner_id: nil)).pluck(:id)
    # Return original before/final counts, stable across this batch's own receipts.
    applied_count = pool.where(id: original, owner_id: inputs['owner_id']).count
    { 'current' => current, 'incoming' => incoming_ids.size + applied_count,
      'projected' => current + incoming_ids.size + applied_count,
      'baseline_digest' => digest }
  end

  def baseline_digest(baseline)
    digest = Digest::SHA256.new
    count = 0
    baseline.in_batches(of: 1000) do |batch|
      batch.order(:id).pluck(:id).each do |id|
        digest << ':' unless count.zero?
        digest << id.to_s
        count += 1
      end
    end
    [count, digest.hexdigest]
  end
end
