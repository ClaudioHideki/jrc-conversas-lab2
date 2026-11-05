# Frozen operational inventory. Source scopes are checked before titles, owners
# or counts are returned; historical/closed records are never reassigned.
class JrcRelationship::PortfolioResponsibilities
  TYPES = {
    'actions' => [JrcRelationship::Action, JrcRelationship::Action::ACTIVE_STATUSES],
    'plans' => [JrcRelationship::SuccessPlan, %w[active paused]],
    'qbrs' => [JrcRelationship::Qbr, %w[scheduled]],
    'risks' => [JrcRelationship::RiskCase, %w[detected analyzing planned negotiating]],
    'renewals' => [JrcRelationship::Renewal, %w[open negotiating]],
    'expansion' => [JrcRelationship::ExpansionSignal, %w[suggested approved]]
  }.freeze
  MAX_RECORDS = 1000

  def initialize(context, executor_id: context.user.id)
    @context = context
    @executor_id = executor_id
  end

  def snapshot(assignment, owner_id:, lock: false)
    rows = TYPES.flat_map do |kind, (model, statuses)|
      source = model.where(account_id: @context.account.id, assignment_id: assignment.id, status: statuses)
      authorized!(source, @context.records(model))
      bounded(source, :owner, lock).map { |record| entry(kind, record, owner_id) }
    end
    activities = activity_rows(assignment, rows, lock)
    rows += JrcRelationship::NativeResponsibilities.new(@context, executor_id: @executor_id).snapshot(rows, owner_id: owner_id, lock: lock)
    { 'assignment_id' => assignment.id, 'entries' => rows + activities.map { |row| entry('activities', row, owner_id) },
      'blockers' => JrcRelationship::ResponsibilityBlockers.new(@context, executor_id: @executor_id).call(assignment, rows, activities) }
  end

  def authorized!(source, visible)
    raise Pundit::NotAuthorizedError if source.where.not(id: visible.select(:id)).exists?
  end

  def visible_snapshot?(snapshot)
    snapshot.fetch('entries').group_by { |row| row.fetch('kind') }.all? do |kind, rows|
      ids = rows.pluck('id')
      relation = visible_scope(kind)
      relation.where(id: ids).count == ids.size
    end
  end

  def activity_scope
    visibility.crm(@context.account.jrc_crm_activities, owner: :user_id)
  end

  def visible_scope(kind)
    return activity_scope if kind == 'activities'
    return JrcRelationship::NativeResponsibilities.new(@context).scope(kind) if JrcRelationship::NativeResponsibilities::KINDS.include?(kind)

    @context.records(TYPES.fetch(kind).first)
  end

  def plan_activity_ids(entries)
    ids = plan_activity_references(entries).filter_map { |row| row['activity_id'] }.map { |id| Integer(id.to_s, 10) }.uniq
    raise ArgumentError, 'Plan activities must belong to this account' unless @context.account.jrc_crm_activities.where(id: ids).count == ids.length

    ids
  end

  private

  def plan_activity_references(entries)
    plans = @context.records(JrcRelationship::SuccessPlan).where(id: entries.select { |row| row['kind'] == 'plans' }.pluck('id'))
    references = plans.flat_map { |plan| plan.goals + Array(plan.metadata['milestones']) }
    raise ArgumentError, 'Pending plan activities require native review' unless references.length <= MAX_RECORDS && references.all?(Hash)

    references
  end

  def entry(kind, record, owner_id)
    from = kind == 'activities' ? record.user_id : record.owner_id
    person = kind == 'activities' ? record.user : record.owner
    { 'kind' => kind, 'id' => record.id, 'label' => record.try(:title).presence || record.try(:reason).presence || record.try(:renewal_on)&.iso8601,
      'from_owner_id' => from, 'from_owner_name' => person&.name, 'to_owner_id' => owner_id,
      'digest' => JrcRelationship::PlaybookFlowReference.digest(record.attributes) }
  end

  def activity_rows(assignment, entries, lock)
    relation = @context.account.jrc_crm_activities.where(id: activity_ids(entries)).or(
      @context.account.jrc_crm_activities.where("metadata ->> 'relationship_assignment_id' = ?", assignment.id.to_s)
    ).where.not(status: %w[completed cancelled])
    authorized!(relation, activity_scope)
    bounded(relation, :user, lock)
  end

  def bounded(relation, association, lock)
    relation = relation.order(:id)
    relation = relation.lock if lock
    rows = relation.includes(association).limit(MAX_RECORDS + 1).to_a
    raise ArgumentError, 'Too many pending responsibilities for one reviewed customer' if rows.size > MAX_RECORDS

    rows
  end

  def activity_ids(entries)
    ids = %w[actions qbrs].flat_map do |kind|
      ids = entries.select { |row| row['kind'] == kind }.pluck('id')
      TYPES.fetch(kind).first.where(account_id: @context.account.id, id: ids).pluck(:activity_id).compact
    end
    (ids + plan_activity_ids(entries)).uniq
  end

  def visibility
    JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
  end
end
