class JrcRelationship::AnalystCapacity
  MAX_ASSIGNMENTS = 10_000

  def initialize(context)
    @context = context
  end

  def call(analyst_id, page: 1, per_page: 10)
    JrcRelationship::Assignment.transaction do
      authority.call do |current|
        raise Pundit::NotAuthorizedError unless current.policy.team?

        analyst = current.assignable_users.find(analyst_id)
        records = owned_assignments(current, analyst)
        JrcRelationship::DistributionCapacity.new(current).current_page(owner_id: analyst.id, records: records, page: page, per_page: per_page)
                                             .merge(analyst: { id: analyst.id, name: analyst.name, active_user: analyst.active_for_authentication? },
                                                    read_only: true, active_statuses: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
      end
    end
  end

  private

  def owned_assignments(context, analyst)
    source = JrcRelationship::Assignment.where(account: context.account, owner: analyst,
                                               status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
    raise Pundit::NotAuthorizedError if source.where.not(id: context.assignments.select(:id)).exists?

    records = source.order(:id).limit(MAX_ASSIGNMENTS + 1).to_a
    raise ArgumentError, 'Use a controlled capacity review for more than10000 active assignments' if records.size > MAX_ASSIGNMENTS

    records
  end

  def authority
    JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: @context.user.id, write: false)
  end
end
