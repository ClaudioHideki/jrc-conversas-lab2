# Availability constrains automatic routing only; it does not grant a user
# access to a customer or change any existing portfolio or team membership.
class JrcRelationship::RoutingAvailability
  def initialize(context, assignment)
    @context = context
    @assignment = assignment
    @allowed = context.assignable_users.pluck(:id)
    @limits = JrcRelationship::DistributionConfigurations.new(context.account).for(assignment)
                                                         .map { |config| config.effective_rules.fetch('portfolio_capacity_limits') }
    @results = {}
  end

  def call(user)
    return false unless user

    @results.fetch(user.id) { @results[user.id] = eligible?(user) }
  end

  private

  def eligible?(user)
    return false unless @allowed.include?(user.id) && user.active_for_authentication? && available_capacity?(user.id)

    member = @context.account.account_users.find_by!(user_id: user.id)
    candidate = JrcRelationship::Context.new(member)
    candidate.policy.manage? && candidate.assignments.exists?(id: @assignment.id)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def available_capacity?(user_id)
    @limits.all? do |limits|
      next true if limits.empty?

      entry = limits.find { |row| row.fetch('user_id') == user_id }
      entry && JrcRelationship::DistributionCapacityPolicy.effective(entry).positive?
    end
  end
end
