# Admission of an existing allocation consumes group capacity without changing
# its native owner. Reuse the current role authority, units and capacity formula.
class JrcRelationship::PortfolioGroupAdmission
  def initialize(record, configuration)
    @record = record
    @configuration = configuration
  end

  def call
    raise ActiveRecord::RecordNotFound unless matching_configuration?
    return unless consumes_capacity?

    limits = @configuration.effective_rules.fetch('portfolio_capacity_limits')
    return if limits.empty?

    JrcRelationship::DistributionCapacityPolicy.validate!(@record.account, limits)
    entry = limits.find { |row| row.fetch('user_id') == @record.owner_id }
    return @record.errors.add(:owner, :portfolio_capacity_unconfigured) unless entry

    validate_entry(entry)
  rescue JrcRelationship::CapacityWorkload::Unavailable => e
    @record.errors.add(:owner, e.message)
  end

  def self.available?(account_id, entry)
    return false unless entry.fetch('availability').positive? && entry.fetch('dedication').positive?

    JrcRelationship::BatchReviewAuthority.new(account_id: account_id, actor_id: entry.fetch('user_id'), write: false).call { true }
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  private

  def matching_configuration?
    @configuration.account_id == @record.account_id && @configuration.scope_key.start_with?('portfolio:')
  end

  def consumes_capacity?
    @record.owner_id && JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES.include?(@record.status)
  end

  def validate_entry(entry)
    return @record.errors.add(:owner, :portfolio_capacity_unavailable) unless self.class.available?(@record.account_id, entry)

    scope = JrcRelationship::DistributionConfigurations.new(@record.account).relation(@configuration)
    pool = scope.where(owner_id: @record.owner_id, status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
    value = JrcRelationship::CapacityWorkload.sum(pool, entry.fetch('unit', 'customers'))
    @record.errors.add(:owner, :portfolio_capacity_exceeded) if value > JrcRelationship::DistributionCapacityPolicy.effective(entry)
  end
end
