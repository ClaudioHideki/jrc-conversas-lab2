class JrcRelationship::DistributionScopeGuard
  def self.check!(context, record, attrs)
    return unless scope_change?(attrs)

    sources = JrcRelationship::DistributionConfigurations.new(context.account)
    before = sources.for(record).select { |config| governed?(config) }
    return if before.empty?

    projected = record.class.instantiate(record.attributes.merge(attrs.to_h.stringify_keys.slice('team_id', 'settings')))
    removed = before.map(&:scope_key) - sources.for(projected).map(&:scope_key)
    return if removed.empty?

    raise ArgumentError, 'A governed scope cannot be removed by changing portfolio classification'
  end

  def self.governed?(config)
    rules = config.effective_rules
    rules.fetch('portfolio_transfer_approval_required') || rules.fetch('portfolio_capacity_limits').present?
  end

  def self.scope_change?(attrs)
    attrs.keys.map(&:to_s).intersect?(%w[team_id settings])
  end
  private_class_method :governed?, :scope_change?
end
