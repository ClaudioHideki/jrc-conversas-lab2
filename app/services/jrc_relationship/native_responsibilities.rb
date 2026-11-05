# Explicit native references from active success plans. Read through native
# scopes; writes are delegated to their own module services.
class JrcRelationship::NativeResponsibilities
  KINDS = %w[project_tasks service_tickets].freeze

  def initialize(context, executor_id: context.user.id)
    @context = context
    @executor_id = executor_id
    @visibility = JrcCustomers::Visibility.new(account: context.account, user: context.user, account_user: context.member)
  end

  def scope(kind)
    kind == 'project_tasks' ? @visibility.project_tasks(@visibility.projects) : @visibility.tickets
  end

  def snapshot(entries, owner_id:, lock:)
    references = plan_references(entries)
    KINDS.flat_map do |kind|
      key = kind == 'project_tasks' ? 'task_id' : 'ticket_id'
      selected_rows(kind, references.filter_map { |row| row[key] }.uniq, lock).map { |row| entry(kind, row, owner_id) }
    end
  end

  def blockers(assignment, entries)
    native = entries.select { |row| KINDS.include?(row['kind']) }
    return [] if native.empty?

    customer = assignment.customer_context(@context.member)
    native.filter_map { |row| blocker_for(assignment, row, customer) }.uniq
  end

  def transfer!(row, owner, correlation_id:)
    if row['kind'] == 'project_tasks'
      JrcProjects::Tasks::Assign.call(account_user: @context.member, task_id: row.fetch('id'), assignee_id: owner.id,
                                      expected_lock_version: row.fetch('lock_version'), correlation_id: correlation_id)
    else
      member = @context.account.account_users.find_by!(user_id: owner.id)
      service = JrcServiceDesk::AssignTicketService.new(user_context: @context.to_h)
      service.call(ticket_id: row.fetch('id'), attributes: { assignee_account_user_id: member.id }, expected_lock_version: row.fetch('lock_version'))
    end
  end

  def owned_scope(kind, owner)
    return scope(kind).where(assignee_id: owner.id) if kind == 'project_tasks'

    member = @context.account.account_users.find_by!(user_id: owner.id)
    scope(kind).where(assignee_membership_id: JrcServiceDesk::UnitMembership.where(account_id: @context.account.id,
                                                                                   account_user_id: member.id).select(:id))
  end

  private

  def plan_references(entries)
    plans = @context.records(JrcRelationship::SuccessPlan).where(id: entries.select { |row| row['kind'] == 'plans' }.pluck('id'))
    references = plans.flat_map { |plan| plan.goals + Array(plan.metadata['milestones']) }
    raise ArgumentError, 'Pending responsibility references require native review' unless references.all?(Hash)

    references
  end

  def selected_rows(kind, ids, lock)
    rows = pending(kind).where(id: ids)
    JrcRelationship::PortfolioResponsibilities.new(@context).authorized!(rows, scope(kind))
    lock_parent!(kind, rows) if lock
    rows = rows.order(:id)
    rows = rows.lock if lock
    selected = rows.limit(JrcRelationship::PortfolioResponsibilities::MAX_RECORDS + 1).to_a
    raise ArgumentError, 'Too many linked native responsibilities' if selected.size > JrcRelationship::PortfolioResponsibilities::MAX_RECORDS

    selected
  end

  # Native writers lock Project -> Task and Unit -> Ticket. Acquire their
  # parent first; NOWAIT avoids a cycle against already locked authority grants.
  def lock_parent!(kind, rows)
    if kind == 'project_tasks'
      @visibility.projects.where(id: rows.select(:project_id)).order(:id).lock('FOR UPDATE NOWAIT').load
    else
      @visibility.service_desk_context.unit_scope.where(id: rows.select(:unit_id)).order(:id)
                 .lock('FOR UPDATE OF jrc_service_desk_units NOWAIT').load
    end
  end

  def blocker_for(assignment, row, customer)
    record = scope(row.fetch('kind')).find(row.fetch('id'))
    expected = row['kind'] == 'project_tasks' ? customer.project_tasks : customer.tickets
    return 'native_customer_context_mismatch' unless expected.exists?(id: record.id)
    return 'shared_native_responsibility_requires_review' if shared?(assignment, row)

    if row['kind'] == 'project_tasks'
      'native_project_requires_reopen' if %w[completed canceled].include?(record.project.status)
    elsif !executor_membership?(record.unit_id)
      'native_actor_membership_required'
    end
  end

  def executor_membership?(unit_id)
    member = @context.account.account_users.find_by!(user_id: @executor_id)
    native = JrcServiceDesk::OperationalContext.new(account: @context.account, user: member.user, account_user: member)
    native.active_memberships.exists?(unit_id: unit_id)
  end

  def pending(kind)
    if kind == 'project_tasks'
      JrcProjects::Task.where(account_id: @context.account.id).where.not(status: %w[completed canceled])
    else
      JrcServiceDesk::Ticket.where(account_id: @context.account.id,
                                   status_id: JrcServiceDesk::TicketStatus.where(account_id: @context.account.id,
                                                                                 phase: %w[
                                                                                   open waiting
                                                                                 ]).select(:id))
    end
  end

  def entry(kind, record, owner_id)
    user = kind == 'project_tasks' ? record.assignee : record.assignee_membership&.account_user&.user
    { 'kind' => kind, 'id' => record.id, 'label' => record.title, 'from_owner_id' => user&.id, 'from_owner_name' => user&.name,
      'to_owner_id' => owner_id, 'lock_version' => record.lock_version,
      'digest' => JrcRelationship::PlaybookFlowReference.digest(record.attributes) }
  end

  def shared?(assignment, row)
    key = row['kind'] == 'project_tasks' ? 'task_id' : 'ticket_id'
    query = 'EXISTS (SELECT 1 FROM jsonb_array_elements(goals || ' \
            "COALESCE(NULLIF(metadata -> 'milestones', 'null'::jsonb), '[]'::jsonb)) AS item(value) " \
            'WHERE item.value ->> ? = ?)'
    JrcRelationship::SuccessPlan.where(account_id: @context.account.id, status: %w[active paused]).where.not(assignment_id: assignment.id)
                                .exists?([query, key, row.fetch('id').to_s])
  end
end
