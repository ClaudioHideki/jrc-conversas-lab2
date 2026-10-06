class Api::V1::Accounts::Relationship::DashboardController < Api::V1::Accounts::Relationship::BaseController
  def show
    render json: presenter.dashboard(filtered_assignments, period: report_period)
  end

  def drilldown
    render json: JrcRelationship::MetricDrilldown.new(context: relationship_context, scope: filtered_assignments, period: report_period)
      .call(metric: params.require(:metric), page: params.fetch(:page, 1), day: params[:day])
  end

  def team
    raise Pundit::NotAuthorizedError unless relationship_context.policy.team?
    scope = filtered_assignments
    ids = scope.where.not(owner_id: nil).distinct.pluck(:owner_id)
    users = Current.account.users.where(id: ids).order(:name)
    metrics = JrcRelationship::TeamMetrics.new(context: relationship_context, scope: scope, period: report_period).call
    render json: { payload: users.map { |user| { user: { id: user.id, name: user.name }, metrics: metrics.fetch(user.id) } } }
  end

  def metadata
    ctx = relationship_context
    render json: { can_manage: ctx.policy.manage?, can_team: ctx.policy.team?, can_configure: ctx.policy.configure?, can_export_history: ctx.policy.admin?,
      owners: ctx.policy.team? ? ctx.assignable_users.order(:name).limit(500).pluck(:id, :name) : [[Current.user.id, Current.user.name]],
      pipelines: JrcOperations::Access.crm?(ctx.member) ? Current.account.jrc_crm_pipelines.active.includes(:stages).map { |pipeline| { id: pipeline.id, name: pipeline.name, stages: pipeline.stages.select { |stage| stage.active && !stage.is_terminal }.map { |stage| { id: stage.id, name: stage.name } } } } : [],
      can_crm: JrcOperations::Access.crm?(ctx.member),
      can_configure_operations: ctx.policy.configure? && JrcOperations::Access.crm?(ctx.member) && ctx.member.administrator?,
      operating_companies: ctx.policy.configure? ? Current.account.master_companies.where(id: Current.account.jrc_crm_business_units.select(:company_id)).order(:name).pluck(:id, :name) : [],
      teams: (ctx.policy.admin? ? Current.account.teams : Current.account.teams.joins(:team_members).where(team_members: { user_id: Current.user.id })).distinct.pluck(:id, :name),
      units: (ctx.policy.admin? ? Current.account.jrc_crm_business_units : JrcCrm::OrganizationalVisibility.new(account: Current.account, user: Current.user, relation: Current.account.jrc_crm_business_units).call).pluck(:id, :name),
      products: JrcOperations::Access.crm?(ctx.member) ? Current.account.jrc_crm_products.active.order(:name).limit(250).pluck(:id, :name) : [],
      segments: JrcCustomers::Taxonomy.where(account: Current.account, kind: 'segment').active.ordered.limit(250).pluck(:id, :name),
      projects: JrcOperations::Access.projects(ctx.member).order(:name).limit(250).pluck(:id, :name),
      native_csats: true, sources: %w[customer_master customer360 crm service_desk projects conversations calls],
      qbr_agenda_template: ctx.configuration.effective_rules['qbr_agenda_template'],
      risk_reasons: ctx.configuration.effective_rules['risk_reasons'], formatting: ctx.formatting,
      can_nico: Current.account.active? && Current.account.custom_attributes['nico_enabled'] == true,
      playbooks: JrcRelationship::Playbook.where(account: Current.account, active: true).order(:name).limit(100).pluck(:id, :name),
      playbook_step_kinds: JrcRelationship::PlaybookSteps::KINDS, kinds: JrcRelationship::Workflow::MODELS.keys }
  end

  def export
    raise Pundit::NotAuthorizedError unless relationship_context.policy.team?
    scope = filtered_assignments
    raise ArgumentError, 'Limit the export to 10000 customers' if scope.count > 10_000
    require 'csv'
    csv = CSV.generate do |output|
      output << %w[cliente responsavel status unidade mrr_centavos health faixa ultima_interacao]
      scope.includes(:company, :contact, :owner, :business_unit).find_in_batches(batch_size: 100) do |records|
        presenter.preload(records)
        records.each do |record|
          row = presenter.assignment(record)
          cells = [row[:name], row.dig(:owner, :name), row[:status], row[:business_unit],
                   row.dig(:signals, :mrr_cents), row.dig(:signals, :health, :score), row.dig(:signals, :health, :band),
                   row.dig(:signals, :last_interaction_at)]
          output << cells.map { |value| value.is_a?(String) && value.match?(/\A[=+@\-\t\r]/) ? "'#{value}" : value }
        end
      end
    end
    relationship_context.audit!(Current.account, after: { rows: scope.count }, action: 'portfolio_exported')
    send_data "\uFEFF#{csv}", filename: 'relationship-portfolio.csv', type: 'text/csv; charset=utf-8'
  end

  def export_history
    raise Pundit::NotAuthorizedError unless relationship_context.policy.admin?
    assignments = filtered_assignments
    events = JrcCrm::AuditEvent.where(account_id: Current.account.id).none
    models = [JrcRelationship::Assignment] + JrcRelationship::Workflow::MODELS.values.uniq
    models.each do |model|
      records = model == JrcRelationship::Assignment ? assignments : relationship_context.records(model).where(assignment_id: assignments.select(:id))
      events = events.or(JrcCrm::AuditEvent.where(account_id: Current.account.id, resource_type: model.name, resource_id: records.select(:id)))
    end
    snapshots = JrcRelationship::HealthSnapshot.where(account_id: Current.account.id, viewer_id: Current.user.id,
      access_signature: relationship_context.access_signature, assignment_id: assignments.select(:id))
    snapshots = JrcRelationship::SnapshotAccess.scope(relationship_context, snapshots)
    events = events.or(JrcCrm::AuditEvent.where(account_id: Current.account.id, resource_type: snapshots.klass.name, resource_id: snapshots.select(:id)))
    events = events.where(created_at: report_period) if report_period
    raise ArgumentError, 'Limit the history export to 10000 events' if events.count > 10_000
    data = events.order(:created_at, :id).as_json(only: [:id, :resource_type, :resource_id, :event_type, :actor_type, :actor_id,
      :created_at, :from_value, :to_value, :metadata])
    relationship_context.audit!(Current.account, after: { rows: data.size }, action: 'history_exported')
    send_data JSON.pretty_generate(data), filename: 'relationship-history.json', type: 'application/json'
  end
end
