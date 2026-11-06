# Reuses canonical implementation-origin resolution. A formal live CS handoff
# remains a link when its implementation project is reopened.
class JrcRelationship::WithdrawalHandoffProjects
  def initialize(context)
    @context = context
  end

  def restrict(projects)
    projects = projects.where(account_id: @context.account.id)
    candidates = candidate_projects(projects)
    return projects.none unless candidates.exists?

    visible = JrcOperations::Access.projects(@context.member)
    raise Pundit::NotAuthorizedError if candidates.where.not(id: visible.select(:id)).exists?

    rows = candidates.order(:id).limit(JrcRelationship::WithdrawalReadiness::MAX_ROWS + 1).to_a
    raise ArgumentError, 'Too many implementation origins for one CS withdrawal review' if rows.size > JrcRelationship::WithdrawalReadiness::MAX_ROWS

    authorize_rows!(rows)
    projects.where(id: rows.map(&:id))
  end

  private

  def cases
    assignments = JrcRelationship::Assignment.where(account_id: @context.account.id,
                                                    status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
    @cases ||= JrcRelationship::HandoffCase.where(account_id: @context.account.id, status: %w[pending accepted],
                                                  assignment_id: assignments.select(:id))
  end

  def candidate_projects(projects)
    direct = projects.where(id: cases.where(source_type: 'JrcProjects::Project').select(:source_id))
    orders = cases.where(source_type: 'JrcCrm::SalesOrder')
    requests = @context.account.jrc_crm_backoffice_requests.where(request_kind: 'fulfillment', sales_order_id: orders.select(:source_id))
    project_ids = requests.reselect(Arel.sql("metadata ->> 'implementation_project_id'")).to_sql
    linked = projects.where("#{projects.klass.table_name}.id::text IN (#{project_ids})")
    order_ids = orders.reselect(:source_id).to_sql
    legacy = projects.where("EXISTS (SELECT 1 FROM (#{order_ids}) AS cs_order WHERE " \
                            "#{projects.klass.table_name}.idempotency_key = 'crm-order-implementation-' || cs_order.source_id::text)")
    direct.or(linked).or(legacy)
  end

  def authorize_rows!(rows)
    direct = cases.where(source_type: 'JrcProjects::Project', source_id: rows.map(&:id)).pluck(:assignment_id, :source_id)
    authorize_direct_cases!(direct)
    direct_ids = direct.map(&:last).index_with(true)
    rows.each { |project| authorize_order_project!(project) unless direct_ids.key?(project.id) }
  end

  def authorize_direct_cases!(direct)
    direct.group_by(&:first).each do |assignment_id, pairs|
      customer = subject_sources(assignment_id)
      ids = pairs.map(&:last).uniq
      raise Pundit::NotAuthorizedError unless customer.projects.where(id: ids).count == ids.length
    end
  end

  def authorize_order_project!(project)
    order = JrcRelationship::Handoff.origin_order(project)
    matching = cases.where(source_type: 'JrcCrm::SalesOrder', source_id: order&.id).to_a
    raise ArgumentError, 'Implementation origin requires native source review' if matching.empty?

    matching.each { |handoff| authorize_case!(handoff, project, order) }
  end

  def authorize_case!(handoff, project, order)
    customer = subject_sources(handoff.assignment_id)
    raise Pundit::NotAuthorizedError unless customer.projects.exists?(id: project.id)
    raise Pundit::NotAuthorizedError unless customer.orders.exists?(id: order.id)
  end

  def subject_sources(assignment_id)
    assignment = @context.assignment(assignment_id)
    JrcCustomers::SubjectSources.new(account: @context.account, user: @context.user, account_user: @context.member,
                                     company: assignment.company, contact: assignment.contact)
  end
end
