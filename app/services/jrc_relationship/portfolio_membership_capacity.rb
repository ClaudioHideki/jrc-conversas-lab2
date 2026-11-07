# Historical read-only projection of the entire selected final membership.
# Native per-item admission remains the only writer; no allocation/owner changes.
class JrcRelationship::PortfolioMembershipCapacity
  MAX_ASSIGNMENTS = 10_000

  def initialize(context)
    @context = context
  end

  def capture(group, inputs, records, configuration)
    base = { 'read_only' => true, 'captured_at' => Time.current.iso8601(6), 'rows' => [] }
    limits = configuration&.effective_rules&.fetch('portfolio_capacity_limits', []) || []
    return base.merge('state' => 'not_configured') if limits.empty?

    base.merge(configured_capture(group, inputs, records, configuration, limits))
  rescue Pundit::NotAuthorizedError
    base.merge('state' => 'scope_denied')
  end

  def for_view(group_id, captured)
    return captured.except('source_assignment_ids') unless captured['state'] == 'projected'

    JrcRelationship::PortfolioGroupAccess.complete_management!(@context, group_id)
    ids = captured.fetch('source_assignment_ids')
    raise Pundit::NotAuthorizedError unless @context.assignments.where(id: ids).count == ids.size

    captured.except('source_assignment_ids')
  rescue Pundit::NotAuthorizedError
    { 'read_only' => true, 'captured_at' => captured.fetch('captured_at'), 'state' => 'scope_denied', 'rows' => [] }
  end

  private

  def configured_capture(group, inputs, records, configuration, limits)
    JrcRelationship::PortfolioGroupAccess.complete_management!(@context, group.id)
    JrcRelationship::DistributionCapacityPolicy.validate!(@context.account, limits)
    current, proposed = scopes(group, inputs)
    return { 'state' => 'controlled_review_required' } if current.count > MAX_ASSIGNMENTS || proposed.count > MAX_ASSIGNMENTS

    owners = affected_owners(records)
    sources = current.where(owner_id: owners).or(proposed.where(owner_id: owners)).order(:id).pluck(:id)
    rows = owners.sort.map { |id| measure(configuration, current.where(owner_id: id), proposed.where(owner_id: id), id, limits) }
    { 'state' => 'projected', 'rows' => rows, 'source_assignment_ids' => sources }
  end

  def affected_owners(records)
    records.select do |row|
      row.owner_id && JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES.include?(row.status)
    end.map(&:owner_id).uniq
  end

  def scopes(group, inputs)
    roots = @context.assignments
    current = roots.where(id: group.customer_links.where(active: true).select(:assignment_id))
    proposed = inputs.fetch('active') ? current.or(roots.where(id: inputs.fetch('ids'))) : current.where.not(id: inputs.fetch('ids'))
    [current, proposed].map { |scope| scope.where(status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES) }
  end

  def measure(configuration, current, proposed, owner_id, limits)
    entry = limits.find { |row| row.fetch('user_id') == owner_id }
    identity = { 'scope_key' => configuration.scope_key, 'user_id' => owner_id,
                 'configuration_version' => configuration.version, 'unit' => entry&.fetch('unit', 'customers') || 'customers' }
    return identity.merge('blocker' => 'capacity_missing') unless entry

    identity.merge(entry.except('user_id')).merge(facts(current, proposed, entry))
  rescue JrcRelationship::CapacityWorkload::Unavailable
    identity.merge('blocker' => 'capacity_workload_missing')
  end

  def facts(current, proposed, entry)
    before = JrcRelationship::CapacityWorkload.sum(current, entry.fetch('unit', 'customers'))
    after = JrcRelationship::CapacityWorkload.sum(proposed, entry.fetch('unit', 'customers'))
    limit = JrcRelationship::DistributionCapacityPolicy.effective(entry)
    { 'current' => before.to_f, 'incoming' => (after - before).to_f, 'projected' => after.to_f,
      'effective_capacity' => limit.to_f, 'available_after' => (limit - after).to_f, 'blocker' => blocker(entry, after, limit) }
  end

  def blocker(entry, after, limit)
    return 'capacity_owner_unavailable' unless JrcRelationship::PortfolioGroupAdmission.available?(@context.account.id, entry)

    'capacity_exceeded' if after > limit
  end
end
