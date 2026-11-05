# One customer's root allocation and all supported pending responsibilities form
# one transaction. Any denied destination rolls the entire item back.
class JrcRelationship::ResponsibilityTransfer
  def initialize(context, review)
    @context = context
    @review = review
  end

  def call(assignment, owner)
    raise ArgumentError, 'Complete transfers require the original reviewed proposal and a destination' unless
      @review&.inputs&.fetch('transfer_responsibilities', false) && owner

    JrcRelationship::ResponsibilityReview.new(@context).verify!(@review, assignment: assignment)
    captured = @review.snapshot.fetch('responsibilities').find { |row| row.fetch('assignment_id') == assignment.id }
    before = assignment.owner_id
    assignment.update!(owner: owner)
    captured.fetch('entries').each { |row| transfer_entry!(row, assignment, owner) }
    verify_destination!(captured, owner)
    after = { owner_id: owner.id, review_id: @review.id, responsibility_count: captured.fetch('entries').size }
    @context.audit!(assignment, before: { owner_id: before }, after: after, action: 'responsibilities_transferred')
  end

  private

  def transfer_entry!(row, assignment, owner)
    if row['kind'] == 'activities'
      activity = JrcRelationship::PortfolioResponsibilities.new(@context).activity_scope.lock.find(row.fetch('id'))
      activity.update!(user: owner)
      @context.audit!(activity, before: { user_id: row['from_owner_id'] }, after: { user_id: owner.id }, action: 'responsibility_transferred')
    else
      JrcRelationship::Workflow.new(@context).transfer_owner!(kind: row.fetch('kind'), id: row.fetch('id'), assignment: assignment, owner: owner)
    end
  end

  def verify_destination!(captured, owner)
    JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: owner.id).call do |target|
      inventory = JrcRelationship::PortfolioResponsibilities.new(target)
      raise Pundit::NotAuthorizedError unless inventory.visible_snapshot?(captured)

      captured.fetch('entries').group_by { |row| row.fetch('kind') }.each do |kind, rows|
        scope = owned_scope(target, inventory, kind, owner)
        raise ArgumentError, 'Responsibility ownership did not persist' unless scope.where(id: rows.pluck('id')).count == rows.size
      end
    end
  end

  def owned_scope(target, inventory, kind, owner)
    return inventory.activity_scope.where(user_id: owner.id) if kind == 'activities'

    target.records(JrcRelationship::PortfolioResponsibilities::TYPES.fetch(kind).first).where(owner_id: owner.id)
  end
end
