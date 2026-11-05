# Applies to actual owner/count changes, including native entry points outside
# reviewed transfers. It grants no access and exposes no hidden workload counts.
class JrcRelationship::DistributionCapacityGuard
  LOAD_STATUSES = %w[onboarding active at_risk].freeze
  CAPACITY_ERRORS = %i[portfolio_capacity_exceeded portfolio_capacity_unconfigured portfolio_capacity_unavailable].freeze

  def initialize(record)
    @record = record
  end

  def call
    return unless count_change?

    JrcRelationship::DistributionApproval.lock_configuration!(@record.account_id)
    return unless @record.owner_id && LOAD_STATUSES.include?(@record.status)

    sources = JrcRelationship::DistributionConfigurations.new(@record.account)
    sources.for(@record).each { |config| validate_scope(sources.relation(config), config) }
  end

  private

  def count_change?
    return @record.owner_id.present? && LOAD_STATUSES.include?(@record.status) if @record.new_record?
    return true if %w[owner_id business_unit_id company_id team_id].any? { |field| @record.will_save_change_to_attribute?(field) }
    return true if active_status_changed?

    @record.will_save_change_to_settings? &&
      @record.settings.slice('segment_id', 'product_id', 'capacity_workload') !=
        @record.settings_in_database.slice('segment_id', 'product_id', 'capacity_workload')
  end

  def active_status_changed?
    @record.will_save_change_to_status? && LOAD_STATUSES.include?(@record.status_in_database) != LOAD_STATUSES.include?(@record.status)
  end

  def validate_scope(relation, configuration)
    limits = configuration.effective_rules.fetch('portfolio_capacity_limits')
    return if limits.empty?

    JrcRelationship::DistributionCapacityPolicy.validate!(@record.account, limits)
    pool = relation.where(owner_id: @record.owner_id, status: LOAD_STATUSES)
    entry = limits.find { |row| row.fetch('user_id') == @record.owner_id }
    if entry && entry.fetch('unit', 'customers') != 'customers'
      validate_workload(pool, entry)
      return
    end
    return if @record.persisted? && pool.exists?(id: @record.id)

    validate_admission(pool, limits)
  end

  def validate_admission(pool, limits)
    entry = limits.find { |row| row.fetch('user_id') == @record.owner_id }
    return @record.errors.add(:owner, :portfolio_capacity_unconfigured) unless entry
    return @record.errors.add(:owner, :portfolio_capacity_unavailable) unless available_member?
    return if pool.count + 1 <= JrcRelationship::DistributionCapacityPolicy.effective(entry)

    @record.errors.add(:owner, :portfolio_capacity_exceeded)
  end

  def available_member?
    member = @record.account.account_users.find_by(user_id: @record.owner_id)
    member&.user&.active_for_authentication? &&
      JrcRelationship::ModulePolicy.new({ account: @record.account, account_user: member, user: member.user }, @record.account).access?
  end

  def validate_workload(pool, entry)
    return @record.errors.add(:owner, :portfolio_capacity_unavailable) unless available_member?

    unit = entry.fetch('unit')
    return @record.errors.add(:owner, :portfolio_capacity_unavailable) unless weighted_available?(pool, entry)

    incoming = JrcRelationship::CapacityWorkload.value(@record.settings, unit)
    current = JrcRelationship::CapacityWorkload.sum(pool.where.not(id: @record.id), unit)
    limit = JrcRelationship::DistributionCapacityPolicy.effective(entry)
    return if current + incoming <= limit

    return if reduces_workload?(pool, unit, incoming)

    @record.errors.add(:owner, :portfolio_capacity_exceeded)
  rescue JrcRelationship::CapacityWorkload::Unavailable => e
    @record.errors.add(:owner, e.message)
  end

  def weighted_available?(pool, entry)
    pool.exists?(id: @record.id) || (entry.fetch('availability').positive? && entry.fetch('dedication').positive?)
  end

  def reduces_workload?(pool, unit, incoming)
    @record.persisted? && pool.exists?(id: @record.id) && incoming <= JrcRelationship::CapacityWorkload.value(@record.settings_in_database, unit)
  end
end
