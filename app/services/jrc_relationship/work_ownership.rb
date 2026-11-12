# Manual responsibility selection uses access, not automatic-routing capacity.
class JrcRelationship::WorkOwnership
  def initialize(context, assignment)
    @context = context
    @assignment = context.assignment(assignment.id)
  end

  def options(record: nil)
    record = @context.records(record.class).where(assignment_id: @assignment.id).find(record.id) if record
    @context.assignable_users.order(:name, :id).limit(500).filter_map do |user|
      candidate = authorize!(user.id)
      next if record && !candidate.records(record.class).exists?(id: record.id)

      [user.id, user.name]
    rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
      nil
    end
  end

  def authorize!(user_id)
    user = @context.assignable_users.find(user_id)
    raise Pundit::NotAuthorizedError unless user.active_for_authentication?

    member = @context.account.account_users.find_by!(user_id: user.id)
    candidate = JrcRelationship::Context.new(member)
    raise Pundit::NotAuthorizedError unless candidate.policy.manage?

    candidate.assignment(@assignment.id, write: true)
    candidate
  end

  def authorize_record!(record, user_id: record.owner_id)
    return unless user_id

    authorize!(user_id).records(record.class).find(record.id)
  end
end
