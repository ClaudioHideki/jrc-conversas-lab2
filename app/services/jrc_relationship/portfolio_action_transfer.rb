# Preserve the legacy root-change operation, but never bypass native Action or
# Agenda access. Complete reviewed responsibility transfers use their own flow.
class JrcRelationship::PortfolioActionTransfer
  def self.prepare(context, assignment)
    return unless assignment.will_save_change_to_owner_id?

    new(context, assignment).prepare!
  end

  def initialize(context, assignment)
    context.assignment(assignment.id, write: true)
    @context = context
    @assignment = assignment
  end

  def prepare!
    @ids = active_actions.order(:id).lock.pluck(:id)
    visible = @context.records(JrcRelationship::Action).where(id: @ids)
    raise Pundit::NotAuthorizedError unless visible.count == @ids.length

    @activity_ids = @assignment.owner_id ? active_actions.where(id: @ids).where.not(activity_id: nil).distinct.pluck(:activity_id) : []
    visible_activities = activity_scope(@context).where(id: @activity_ids).order(:id).lock.pluck(:id)
    raise Pundit::NotAuthorizedError unless visible_activities.length == @activity_ids.length

    self
  end

  def apply!(owner)
    return if @ids.empty?

    if owner
      JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: owner.id).call do |target|
        transfer!(owner)
        verify_destination!(target)
      end
    else
      transfer!(nil)
    end
  end

  private

  def active_actions
    @assignment.actions.where(status: JrcRelationship::Action::ACTIVE_STATUSES)
  end

  def activity_scope(context)
    JrcRelationship::PortfolioResponsibilities.new(context).activity_scope
  end

  def transfer!(owner)
    active_actions.where(id: @ids).find_each do |action|
      action.update!(owner: owner)
      action.activity.update!(user: owner) if owner && action.activity
    end
  end

  def verify_destination!(target)
    raise Pundit::NotAuthorizedError unless target.records(JrcRelationship::Action).where(id: @ids).count == @ids.length
    raise Pundit::NotAuthorizedError unless activity_scope(target).where(id: @activity_ids).count == @activity_ids.length
  end
end
