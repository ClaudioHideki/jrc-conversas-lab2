# A read-only inventory with links to the original module editors. Viewing a
# row never grants assignment, membership or final analyst-removal authority.
class JrcRelationship::AnalystNativeResponsibilities
  KINDS = (JrcRelationship::NativeResponsibilities::KINDS + %w[projects activities]).freeze

  def initialize(context)
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id, write: false)
  end

  def call(analyst_id, kind:, page: 1)
    page = Integer(page.to_s, 10)
    raise ActionController::BadRequest, 'Invalid native responsibility page' unless page.positive?
    raise ArgumentError, 'Unsupported native responsibility kind' unless KINDS.include?(kind)

    @authority.call do |context|
      raise Pundit::NotAuthorizedError unless context.policy.team?

      analyst = context.account.users.find(analyst_id)
      rows = authorized_source(context, analyst, kind)
      result = presentation(context, analyst, rows, kind, page)
      verify_viewer!(context, analyst, kind, result.fetch(:payload).pluck(:id))
      result
    end
  end

  private

  def presentation(context, analyst, rows, kind, page)
    total = rows.count
    selected = (page - 1) * 10 < total ? rows.order(:id).offset((page - 1) * 10).limit(10).to_a : []
    { analyst: { id: analyst.id, name: analyst.name }, kind: kind,
      payload: selected.map { |row| project(context, row, kind) }, meta: { page: page, per_page: 10, total: total } }
  end

  def verify_viewer!(context, analyst, kind, ids)
    current = JrcRelationship::Context.new(context.member.reload)
    allowed = current.account.active? && current.user.active_for_authentication? && current.policy.access? && current.policy.team?
    raise Pundit::NotAuthorizedError unless allowed

    rows = authorized_source(current, current.account.users.find(analyst.id), kind)
    raise Pundit::NotAuthorizedError unless rows.where(id: ids).count == ids.length
  end

  def authorized_source(context, analyst, kind)
    rows, visible = source_scopes(context, analyst, kind)
    raise Pundit::NotAuthorizedError if rows.where.not(id: visible.select(:id)).exists?

    kind == 'service_tickets' ? rows.includes(:status) : rows
  end

  def source_scopes(context, analyst, kind)
    if kind == 'activities'
      rows = JrcRelationship::LinkedCrmCommitments.new(context.account).owned_pending_scope(analyst)
      visible = JrcRelationship::PortfolioResponsibilities.new(context).activity_scope
    elsif kind == 'projects'
      rows = JrcProjects::Project.where(account: context.account, owner: analyst).where.not(status: %w[completed canceled])
      visible = rows.exists? ? JrcOperations::Access.projects(context.member) : rows.none
    else
      native = JrcRelationship::NativeResponsibilities.new(context)
      rows = native.owned_pending_scope(kind, analyst)
      visible = rows.exists? ? native.owned_scope(kind, analyst) : rows.none
    end
    rows = JrcRelationship::WithdrawalNativeLinks.new(context).restrict(kind, rows) unless kind == 'activities'
    [rows, visible]
  end

  def project(context, row, kind)
    { id: row.id, title: kind == 'projects' ? row.name : row.title, status: kind == 'service_tickets' ? row.status.phase : row.status,
      updated_at: row.updated_at, source_route: source_route(context.account.id, row, kind) }
  end

  def source_route(account_id, row, kind)
    if kind == 'activities'
      { name: 'crm_activities', params: { accountId: account_id }, query: { activityId: row.id } }
    elsif kind == 'service_tickets'
      { name: 'jrc_service_desk_detail', params: { accountId: account_id, ticketId: row.id } }
    else
      project_id = kind == 'projects' ? row.id : row.project_id
      { name: 'jrc_projects_detail', params: { accountId: account_id, projectId: project_id },
        query: kind == 'project_tasks' ? { taskId: row.id } : {} }
    end
  end
end
