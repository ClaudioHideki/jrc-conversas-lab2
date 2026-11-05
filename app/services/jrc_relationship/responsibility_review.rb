class JrcRelationship::ResponsibilityReview
  def initialize(context)
    @context = context
    @inventory = JrcRelationship::PortfolioResponsibilities.new(context)
  end

  def snapshot(inputs, records, lock: false)
    return unless inputs['transfer_responsibilities']

    raise ArgumentError, 'A destination and justification are required for complete responsibility transfer' unless
      inputs['owner_id'] && inputs['justification'].present?

    JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: inputs.fetch('owner_id')).call { |_target| true }
    records.map { |row| @inventory.snapshot(row, owner_id: inputs.fetch('owner_id'), lock: lock) }
  end

  def verify!(review, assignment: nil, lock: true)
    return unless review.inputs['transfer_responsibilities']

    ids = assignment ? [assignment.id] : review.items.where(state: 'pending').pluck(:assignment_id)
    actual = snapshot(review.inputs, selected_assignments(ids), lock: lock)
    expected = review.snapshot.fetch('responsibilities').select { |row| ids.include?(row.fetch('assignment_id')) }
    raise ArgumentError, 'Reviewed responsibilities changed; create a new simulation' unless actual == expected
    raise ArgumentError, 'Pending responsibilities require native source review before transfer' if actual.any? { |row| row.fetch('blockers').any? }
  end

  def for_view(review)
    return unless review.inputs['transfer_responsibilities']

    review.snapshot.fetch('responsibilities').map do |row|
      view_row(review, row)
    end
  end

  private

  def selected_assignments(ids)
    records = @context.assignments.where(id: ids).order(:id).to_a
    raise Pundit::NotAuthorizedError unless records.size == ids.size

    records
  end

  def view_row(review, row)
    @context.assignment(row.fetch('assignment_id'))
    raise Pundit::NotAuthorizedError unless @inventory.visible_snapshot?(row)

    item = review.items.find_by!(assignment_id: row.fetch('assignment_id'))
    states = { 'applied' => 'executed', 'failed' => 'failed', 'canceled' => 'canceled' }
    return row.merge('state' => states.fetch(item.state)) unless item.state == 'pending'

    current = @inventory.snapshot(@context.assignment(row.fetch('assignment_id')), owner_id: review.inputs.fetch('owner_id'))
    state = if current == row
              row.fetch('blockers').any? ? 'blocked' : 'ready'
            else
              'stale'
            end
    row.merge('state' => state)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    { 'assignment_id' => row.fetch('assignment_id'), 'state' => 'unavailable', 'entries' => [], 'blockers' => ['responsibility_scope_denied'] }
  end
end
