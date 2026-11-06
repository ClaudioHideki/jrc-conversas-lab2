# Restricts the CS withdrawal inventory to effective pending CS origins. Native
# ownership and authorization stay in their original modules.
class JrcRelationship::WithdrawalNativeLinks
  SOURCES = [JrcRelationship::SuccessPlan, JrcRelationship::Action, JrcRelationship::RiskCase].freeze
  KEYS = { 'projects' => 'project_id', 'project_tasks' => 'task_id', 'service_tickets' => 'ticket_id' }.freeze
  MANIFEST_KEYS = { 'projects' => 'projects', 'project_tasks' => 'project_tasks', 'service_tickets' => 'tickets' }.freeze
  NATIVE_TYPES = { 'projects' => 'JrcProjects::Project', 'project_tasks' => 'JrcProjects::Task',
                   'service_tickets' => 'JrcServiceDesk::Ticket' }.freeze

  def initialize(context)
    @context = context
  end

  def restrict(kind, rows)
    KEYS.fetch(kind)
    selected = direct(kind, rows)
    if kind == 'projects'
      tasks = JrcProjects::Task.where(account_id: @context.account.id, project_id: rows.select(:id))
      selected = selected.or(rows.where(id: direct('project_tasks', tasks).select(:project_id)))
    elsif kind == 'project_tasks'
      projects = JrcProjects::Project.where(account_id: @context.account.id, id: rows.select(:project_id))
      selected = selected.or(rows.where(project_id: direct('projects', projects).select(:id)))
    end
    selected
  end

  private

  def direct(kind, rows)
    SOURCES.reduce(rows.none) do |selected, model|
      origins = authorized_origins(model, rows, kind)
      next selected unless origins

      predicate = reference_predicate(model, kind, "#{rows.klass.table_name}.id")
      sql = origins.where(predicate).reselect('1').reorder(nil).to_sql
      selected.or(rows.where("EXISTS (#{sql})"))
    end
  end

  def authorized_origins(model, rows, kind)
    statuses = JrcRelationship::PortfolioResponsibilities::TYPES.values.find { |type, _| type == model }.last
    origins = model.where(account_id: @context.account.id, status: statuses)
    relevant = relevant_origins(origins, rows, kind)
    return unless relevant.exists?

    visible = @context.records(model)
    raise Pundit::NotAuthorizedError if relevant.where.not(id: visible.select(:id)).exists?

    origins.where(id: visible.select(:id))
  end

  def relevant_origins(origins, rows, kind)
    native = rows.reselect(:id).reorder(nil).to_sql
    predicate = reference_predicate(origins.klass, kind, 'withdrawal_native.id')
    origins.where("EXISTS (SELECT 1 FROM (#{native}) AS withdrawal_native WHERE #{predicate})")
  end

  def reference_predicate(model, kind, native_id)
    table = model.table_name
    id = "#{native_id}::text"
    if model == JrcRelationship::SuccessPlan
      refs = "#{table}.goals || COALESCE(NULLIF(#{table}.metadata -> 'milestones', 'null'::jsonb), '[]'::jsonb)"
      goal = "EXISTS (SELECT 1 FROM jsonb_array_elements(#{refs}) AS commitment(value) WHERE commitment.value ->> '#{KEYS.fetch(kind)}' = #{id})"
      kind == 'projects' ? "(#{table}.project_id = #{native_id} OR #{goal})" : goal
    else
      evidence_predicate(table, kind, id)
    end
  end

  def evidence_predicate(table, kind, id)
    manifest = "COALESCE(#{table}.metadata #> '{_source_ids,#{MANIFEST_KEYS.fetch(kind)}}', '[]'::jsonb)"
    captured = "EXISTS (SELECT 1 FROM jsonb_array_elements_text(#{manifest}) AS evidence(value) WHERE evidence.value = #{id})"
    source = "(#{table}.metadata ->> 'source_type' = '#{NATIVE_TYPES.fetch(kind)}' AND #{table}.metadata ->> 'source_id' = #{id})"
    return "(#{captured} OR #{source})" unless kind == 'service_tickets' && table == JrcRelationship::Action.table_name

    "(#{captured} OR #{source} OR (#{table}.source_key LIKE 'post-ticket:%' AND split_part(#{table}.source_key, ':', 2) = #{id}))"
  end
end
