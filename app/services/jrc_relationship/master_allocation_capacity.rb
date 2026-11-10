# Whole-selection workload using native units and limits. This operation never
# transfers owners; only new roots consume global capacity, while new links
# consume their own portfolio capacity. Hidden workload is never spare capacity.
class JrcRelationship::MasterAllocationCapacity
  MAX_ASSIGNMENTS = 10_000

  def initialize(context)
    @context = context
    @sources = JrcRelationship::DistributionConfigurations.new(context.account)
  end

  def capture(records, rows, group, applied: {})
    @target_group_key = "portfolio:#{group.id}"
    @sources.preload(records)
    scopes = scope_keys(records)
    configurations = configurations(records, group)
    selection = { records: records, rows: rows, applied: applied, scopes: scopes, group: group }
    facts = configurations.uniq(&:scope_key).sort_by(&:scope_key).flat_map { |config| configured_facts(config, selection) }
    raise ArgumentError, 'Narrow the reviewed capacity scopes' if facts.size > 1000

    { 'state' => facts.empty? ? 'not_configured' : 'projected', 'rows' => facts }
  end

  def for_view(captured)
    JrcRelationship::PortfolioGroupConfiguration.authorize_bindings!(@context, captured.fetch('rows'))
    captured.merge('rows' => captured.fetch('rows').map do |row|
      ids = row.fetch('source_assignment_ids', [])
      raise Pundit::NotAuthorizedError unless @context.assignments.where(id: ids).count == ids.size

      row.except('source_assignment_ids', 'baseline_digest')
    end)
  end

  private

  def scope_keys(records)
    records.to_h { |record| [record.company_id, @sources.for(record).map(&:scope_key)] }
  end

  def configurations(records, group)
    records.flat_map { |record| @sources.for(record) } +
      JrcRelationship::Configuration.where(account: @context.account, scope_key: "portfolio:#{group.id}").to_a
  end

  def configured_facts(config, selection)
    limits = config.effective_rules.fetch('portfolio_capacity_limits')
    return [] if limits.empty?

    JrcRelationship::DistributionCapacityPolicy.validate!(@context.account, limits)
    selected = selection.fetch(:records).select do |record|
      consumes?(record) && scoped?(config, record, selection.fetch(:scopes), selection.fetch(:group))
    end
    selected.group_by(&:owner_id).sort.map do |_, records|
      measure(config, limits, records, selection.fetch(:rows), selection.fetch(:applied))
    end
  end

  def consumes?(record)
    record.owner_id && JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES.include?(record.status)
  end

  def scoped?(config, record, scopes, group)
    config.scope_key == "portfolio:#{group.id}" || scopes.fetch(record.company_id).include?(config.scope_key)
  end

  def measure(config, limits, selected, rows, applied)
    owner_id = selected.first.owner_id
    entry = limits.find { |row| row.fetch('user_id') == owner_id }
    result = { 'scope_key' => config.scope_key, 'configuration_version' => config.version, 'user_id' => owner_id,
               'unit' => entry&.fetch('unit', 'customers') || 'customers' }
    return result.merge('blocker' => 'capacity_missing') unless entry

    incoming = incoming_records(config, selected, rows)
    result.merge(measure_workload(config, incoming, applied, entry))
  rescue JrcRelationship::CapacityWorkload::Unavailable
    result.merge('blocker' => 'capacity_workload_missing')
  end

  def measure_workload(config, incoming, applied, entry)
    own_ids = incoming.filter_map { |record| applied[record.company_id]&.fetch('assignment_id') }
    baseline = @sources.relation(config).where(owner_id: entry.fetch('user_id'), status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
                       .where.not(id: own_ids).order(:id)
    return { 'blocker' => 'capacity_scope_denied' } if baseline.where.not(id: @context.assignments.select(:id)).exists?
    return { 'blocker' => 'controlled_review_required' } if baseline.limit(MAX_ASSIGNMENTS + 1).count > MAX_ASSIGNMENTS

    workload(baseline, incoming, entry)
  end

  def incoming_records(config, selected, rows)
    selected.select do |record|
      original = rows.find { |row| row.fetch('company_id') == record.company_id }
      config.scope_key == @target_group_key ? !original.fetch('linked') : original.fetch('mode') == 'create'
    end
  end

  def workload(baseline, incoming, entry)
    unit = entry.fetch('unit', 'customers')
    current = JrcRelationship::CapacityWorkload.sum(baseline, unit)
    addition = incoming.sum { |record| unit == 'customers' ? 1.to_d : JrcRelationship::CapacityWorkload.value(record.settings, unit) }
    limit = JrcRelationship::DistributionCapacityPolicy.effective(entry)
    projected = current + addition
    sources = baseline.pluck(:id, :status, :settings, :updated_at)
    { 'current' => current.to_f, 'incoming' => addition.to_f, 'incoming_customers' => incoming.size,
      'projected' => projected.to_f, 'effective_capacity' => limit.to_f, 'available_after' => (limit - projected).to_f,
      'baseline_digest' => JrcRelationship::PlaybookFlowReference.digest(sources), 'source_assignment_ids' => sources.map(&:first),
      'blocker' => blocker(entry, addition, projected, limit) }
  end

  def blocker(entry, addition, projected, limit)
    return unless addition.positive?
    return 'capacity_owner_unavailable' unless JrcRelationship::PortfolioGroupAdmission.available?(@context.account.id, entry)

    'capacity_exceeded' if projected > limit
  end
end
