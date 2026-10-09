class JrcRelationship::CustomerTimeline
  def initialize(context:, customer:, assignment: nil)
    @context = context
    @customer = customer
    @assignment = assignment
  end

  def sources
    surveys = survey_scope
    result = { 'relationship_survey_created' => [surveys, :created_at],
               'relationship_survey_response' => [surveys.where.not(responded_at: nil), :responded_at],
               'relationship_survey_treatment' => [surveys.where.not(treated_at: nil), :treated_at],
               'relationship_survey_decision' => [decisions, :evaluated_at] }
    return result unless @assignment

    result.merge('relationship_handoff' => [handoffs.where.not(decided_at: nil), :decided_at],
                 'relationship_playbook_execution' => [executions, :created_at])
  end

  def audit_origins
    return {} unless @assignment

    { 'JrcRelationship::HandoffCase' => handoffs,
      'JrcRelationship::PlaybookExecution' => executions,
      'JrcRelationship::SurveyDispatchDecision' => decisions }
  end

  def self.event(source, record)
    titles = { 'relationship_survey_created' => 'Survey published', 'relationship_survey_response' => 'Survey answered',
               'relationship_survey_treatment' => 'Survey treatment recorded', 'relationship_survey_decision' => 'Survey policy evaluated',
               'relationship_handoff' => 'Handoff decision recorded', 'relationship_playbook_execution' => 'Playbook execution recorded' }
    { title: titles.fetch(source), resource_type: record.class.name, resource_id: record.id }
  end

  private

  def survey_scope
    rows = @context.records(JrcRelationship::Survey)
    rows = rows.where(assignment_id: @assignment.id).or(rows.where(assignment_id: nil)) if @assignment
    visible = rows.where(contact_id: @customer.contacts.select(:id)).where.not(source_type: nil)
    @assignment ? visible.or(rows.where(source_type: nil, assignment_id: @assignment.id)) : visible
  end

  def decisions
    rows = JrcRelationship::SurveyDispatchDecision.where(account: @context.account)
    visible = rows.where(source_type: 'Conversation', source_id: @customer.conversations.select(:id))
    visible = visible.or(rows.where(source_type: 'JrcServiceDesk::Ticket', source_id: @customer.tickets.select(:id)))
    visible = visible.or(rows.where(source_type: 'JrcCrm::Activity', source_id: @customer.activities.select(:id)))
    visible = visible.or(rows.where(source_type: 'Call', source_id: @customer.calls.select(:id))) if @customer.calls
    if @assignment
      visible = visible.or(rows.where(source_type: 'JrcRelationship::Qbr',
                                      source_id: @context.records(JrcRelationship::Qbr).where(assignment: @assignment).select(:id)))
    end
    visible
  end

  def handoffs
    rows = JrcRelationship::HandoffCase.where(account: @context.account, assignment: @assignment)
    rows.where(source_type: 'JrcCrm::SalesOrder', source_id: @customer.orders.select(:id))
        .or(rows.where(source_type: 'JrcProjects::Project', source_id: @customer.projects.select(:id)))
  end

  def executions
    rows = JrcRelationship::PlaybookExecution.where(account: @context.account, assignment: @assignment)
    models = JrcRelationship::Workflow::MODELS.values
    results = "jsonb_array_elements(COALESCE(NULLIF(snapshot -> 'results', 'null'::jsonb), '[]'::jsonb)) AS result(value)"
    rows = rows.where("NOT EXISTS (SELECT 1 FROM #{results} WHERE NULLIF(result.value ->> 'resource_id', '') IS NOT NULL " \
                      "AND COALESCE(result.value ->> 'resource_type', '') NOT IN (?))", models.map(&:name) + ['JrcFlowRun'])
    rows = filter_native_results(rows, results, models)
    filter_flow_activity_results(rows, results)
  end

  def filter_native_results(rows, results, models)
    models.each do |model|
      visible = @context.records(model).reselect(model.arel_table[:id]).reorder(nil).to_sql
      rows = rows.where("NOT EXISTS (SELECT 1 FROM #{results} WHERE result.value ->> 'resource_type' = :resource_type " \
                        "AND NULLIF(result.value ->> 'resource_id', '') IS NOT NULL " \
                        "AND #{json_id('resource_id')} NOT IN (#{visible}))", resource_type: model.name)
    end
    rows
  end

  def filter_flow_activity_results(rows, results)
    flows = JrcRelationship::PlaybookFlow.visible_runs(context: @context, assignment: @assignment).reselect(:id).reorder(nil).to_sql
    rows = rows.where("NOT EXISTS (SELECT 1 FROM #{results} WHERE result.value ->> 'resource_type' = 'JrcFlowRun' " \
                      "AND NULLIF(result.value ->> 'resource_id', '') IS NOT NULL " \
                      "AND #{json_id('resource_id')} NOT IN (#{flows}))")
    activities = @customer.activities.reselect(JrcCrm::Activity.arel_table[:id]).reorder(nil).to_sql
    rows.where("NOT EXISTS (SELECT 1 FROM #{results} WHERE NULLIF(result.value ->> 'activity_id', '') IS NOT NULL " \
               "AND #{json_id('activity_id')} NOT IN (#{activities}))")
  end

  def json_id(key)
    "CASE WHEN result.value ->> '#{key}' ~ '^[0-9]+$' THEN (result.value ->> '#{key}')::bigint ELSE -1 END"
  end
end
