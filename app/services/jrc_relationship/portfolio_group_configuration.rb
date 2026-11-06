# Distribution-only policies live in the existing immutable configuration store.
# Multiple memberships never choose or override the customer's health configuration.
class JrcRelationship::PortfolioGroupConfiguration
  RULES = %w[portfolio_capacity_limits portfolio_transfer_approval_required portfolio_review_validity_minutes].freeze

  def self.authorize!(context, scope_key)
    id = JrcRelationship::PortfolioOwnerInput.parse(scope_key.split(':', 2).last)
    group = JrcRelationship::PortfolioGroupScope.writable(context).find(id)
    links = group.customer_links.where(active: true)
    raise Pundit::NotAuthorizedError if links.where.not(assignment_id: context.assignments.select(:id)).exists?

    group
  end

  def self.verify_revision!(context, scope_key, version)
    return unless scope_key.to_s.start_with?('portfolio:')

    JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id).call do |current|
      raise Pundit::NotAuthorizedError unless current.policy.configure?

      group = authorize!(current, scope_key)
      raise ArgumentError, 'Reactivate the portfolio before changing its distribution rules' unless group.status == 'active'
      raise ArgumentError, 'A whole-number portfolio revision is required' unless version.is_a?(Integer) && version >= 0
      raise ActiveRecord::StaleObjectError.new(group, 'configure') unless group.lock_version == version
    end
  end

  def self.payload(context, scope_key)
    return {} unless scope_key.to_s.start_with?('portfolio:')

    { portfolio_revision: authorize!(context, scope_key).lock_version }
  end

  def self.validate!(configuration)
    return unless configuration.scope_key.to_s.start_with?('portfolio:') && configuration.weights.is_a?(Hash)

    defaults = JrcRelationship::Configuration::DEFAULT_RULES
    extra = configuration.rules.except(*RULES)
    valid = configuration.effective_weights == JrcRelationship::Configuration::DEFAULT_WEIGHTS && extra.all? { |key, value| value == defaults[key] }
    configuration.errors.add(:rules, 'named portfolios configure distribution only') unless valid
  end

  def self.authorize_groups!(context, ids)
    return if ids.empty?

    visible = JrcRelationship::PortfolioGroupScope.resolve(context).where(id: ids).pluck(:id)
    raise Pundit::NotAuthorizedError unless visible.sort == ids.uniq.sort
  end

  def self.authorize_snapshot!(context, snapshot)
    bindings = snapshot.dig('distribution_approval', 'configurations') || []
    authorize_bindings!(context, bindings)
  end

  def self.authorize_bindings!(context, bindings)
    ids = bindings.filter_map { |row| row.fetch('scope_key').split(':', 2).last.to_i if row.fetch('scope_key').start_with?('portfolio:') }
    authorize_groups!(context, ids)
  end

  def self.review_validity(account, binding, fallback)
    keys = binding.fetch('configurations').map { |row| row.fetch('scope_key') }.select { |key| key.start_with?('portfolio:') }.uniq
    return fallback if keys.empty?

    configurations = JrcRelationship::Configuration.where(account: account, scope_key: keys).index_by(&:scope_key)
    minutes = keys.map { |key| configurations.fetch(key).effective_rules.fetch('portfolio_review_validity_minutes') }
    [fallback, *minutes].min
  end

  def self.for(group)
    JrcRelationship::Configuration.find_by(account_id: group.account_id, scope_key: "portfolio:#{group.id}")
  end

  def self.governed?(group)
    rules = self.for(group)&.effective_rules
    rules && (rules.fetch('portfolio_transfer_approval_required') || rules.fetch('portfolio_capacity_limits').present?)
  end

  def self.before_unlink!(group, ids)
    return unless governed?(group) && group.customer_links.exists?(active: true, assignment_id: ids)

    raise ArgumentError, 'Review and clear governed portfolio rules before unlinking customers'
  end

  def self.before_archive!(group)
    return unless group.will_save_change_to_status? && group.status == 'archived' && governed?(group)

    raise ArgumentError, 'Review and clear governed portfolio rules before archiving'
  end

  def self.admit!(group, records)
    configuration = self.for(group)
    return unless configuration

    active = records.select { |row| row.owner_id && JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES.include?(row.status) }
    active.uniq(&:owner_id).each do |row|
      JrcRelationship::PortfolioGroupAdmission.new(row, configuration).call
      raise ActiveRecord::RecordInvalid, row if row.errors.any?
    end
  end
end
