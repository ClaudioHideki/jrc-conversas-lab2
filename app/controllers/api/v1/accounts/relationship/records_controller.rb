class Api::V1::Accounts::Relationship::RecordsController < Api::V1::Accounts::Relationship::BaseController
  def index
    model = JrcRelationship::Workflow::MODELS.fetch(params[:kind])
    scope = relationship_context.records(model).where(assignment_id: filtered_assignments.select(:id))
    scope = survey_scope(model, scope)
    filters = JrcRelationship::RecordFilters.new(model, params, renewal_rules: model == JrcRelationship::Renewal ? renewal_rules : nil)
    scope = filters.identity_scope(scope)
    windows = if model == JrcRelationship::Renewal
                renewal_ranges.keys.index_with { |key| JrcRelationship::RenewalWindow.scope(scope, key, rules: renewal_rules).count }
              end
    scope = filters.operational_scope(filters.renewal_scope(scope))
    render_records(model, scope, windows)
  end

  def render_records(model, scope, windows)
    order = model == JrcRelationship::Action ? { priority: :desc, due_at: :asc, id: :asc } : { updated_at: :desc, id: :desc }
    summary = survey_summary(model, scope)
    records, meta = page(scope.includes(:owner, :assignment).order(order))
    records = records.to_a
    presenter.preload(records.map(&:assignment).uniq(&:id)) if [JrcRelationship::RiskCase, JrcRelationship::Renewal].include?(model)
    render json: { payload: records.map { |row| presenter.record(row) },
                   meta: meta.merge(renewal_windows: windows, renewal_ranges: model == JrcRelationship::Renewal ? renewal_ranges : nil,
                                    survey_report: summary) }
  end

  private :render_records

  def create
    save_record
  end

  def update
    save_record
  end

  def opportunity
    raise ArgumentError, 'Unsupported opportunity origin' unless %w[expansion renewals].include?(params[:kind])

    record = relationship_context.records(JrcRelationship::Workflow::MODELS.fetch(params[:kind])).find(params[:id])
    deal = JrcRelationship::Workflow.new(relationship_context).opportunity!(record, pipeline_id: params.require(:pipeline_id),
                                                                                    stage_id: params.require(:stage_id), contact_id: params[:contact_id])
    render json: { deal_id: deal.id, route: 'crm_deals' }
  end

  def deliver_survey
    survey = relationship_context.records(JrcRelationship::Survey).find(params[:id])
    message = JrcRelationship::SurveyDelivery.new(context: relationship_context, survey: survey, base_url: request.base_url)
                                             .call(conversation_id: params.require(:conversation_id), content: params[:content],
                                                   template_params: survey_template_params)
    render json: { message_id: message.id, conversation_id: message.conversation.display_id }
  end

  def survey_link
    survey = relationship_context.records(JrcRelationship::Survey).find(params[:id])
    raise ArgumentError, 'Survey expired or already answered' if survey.responded_at || survey.expires_at <= Time.current
    raise ArgumentError, 'Survey is not available for response' if survey.source_type && %w[available sent delivered].exclude?(survey.status)

    render json: { url: "#{request.base_url}/jrc/relacionamento/pesquisas/#{survey.signed_id(purpose: :relationship_survey)}" }
  end

  def export_surveys
    csv = JrcRelationship::SurveyReport.new(relationship_context, survey_filters).csv
    send_data csv, type: 'text/csv; charset=utf-8', disposition: 'attachment', filename: "survey-responses-#{Date.current.iso8601}.csv"
  end

  def voice_preview
    survey = relationship_context.records(JrcRelationship::Survey).find(params[:id])
    if request.post?
      raise ArgumentError, 'Voice preview requires an explicit dry-run' unless params[:dry_run] == true

      values = params.require(:inputs)
      keys = survey.questions.pluck('key')
      raise ArgumentError, 'Unknown voice input' unless values.respond_to?(:permit) && (values.keys - keys).empty?
      raise ArgumentError, 'Voice input must be scalar' unless values.values.all? { |value| value.nil? || value.is_a?(String) || value.is_a?(Numeric) }

      inputs = values.permit(*keys).to_h
    end
    render json: JrcRelationship::SurveyVoicePreview.new(relationship_context, survey).call(inputs: inputs)
  end

  def treat_survey
    raise Pundit::NotAuthorizedError unless relationship_context.policy.manage?

    survey = relationship_context.records(JrcRelationship::Survey).find(params[:id])
    raise ArgumentError, 'Only responses can be treated' unless survey.responded_at

    attrs = treatment_attributes

    survey.with_lock do
      persist_treatment!(survey, attrs)
      relationship_context.audit!(survey, after: attrs.to_h, action: 'survey_treated')
    end
    render json: presenter.record(survey)
  end

  def batch
    ids = params.require(:ids)
    raise ArgumentError, 'Select between 1 and 50 actions' unless ids.is_a?(Array) && ids.size.between?(1, 50)

    attrs = params.require(:record).permit(:status, :due_at, :priority, :result, :owner_id).to_h
    raise Pundit::NotAuthorizedError unless relationship_context.policy.manage?

    rows = relationship_context.records(JrcRelationship::Action).where(id: ids).order(:id)
    raise ActiveRecord::RecordNotFound unless rows.count == ids.uniq.size

    JrcRelationship::Action.transaction do
      rows.each do |row|
        JrcRelationship::Workflow.new(relationship_context).save(kind: 'actions', id: row.id,
                                                                 attributes: attrs.merge('assignment_id' => row.assignment_id,
                                                                                         'lock_version' => row.lock_version))
      end
    end
    render json: { updated: rows.count }
  end

  private

  def survey_template_params
    value = params[:template_params]
    return if value.nil?

    raise ArgumentError, 'Invalid template parameters' unless value.respond_to?(:to_unsafe_h)

    value.to_unsafe_h
  end

  def treatment_attributes
    attrs = params.require(:record).permit(:treatment_status, :treatment_cause)
    raise ArgumentError, 'Record the treatment cause' if attrs[:treatment_status] == 'treated' && attrs[:treatment_cause].blank?

    attrs
  end

  def persist_treatment!(survey, attrs)
    survey.update!(attrs.merge(treated_at: attrs[:treatment_status] == 'treated' ? Time.current : nil))
  end

  def survey_summary(model, scope)
    return unless model == JrcRelationship::Survey

    report = JrcRelationship::SurveyReport.new(relationship_context, survey_filters)
    JrcRelationship::SurveySummary.new(relationship_context, scope, selected_period: params[:from].present?,
      cohort: report.cohort_scope, cohort_available: report.cohort_available?, cohort_period: report.cohort_period).call
  end

  def survey_scope(model, scope)
    model == JrcRelationship::Survey ? JrcRelationship::SurveyReport.new(relationship_context, survey_filters).scope : scope
  end

  def renewal_rules
    assignment = relationship_context.assignment(params[:assignment_id]) if params[:assignment_id].present?
    @renewal_rules ||= relationship_context.configuration(assignment).effective_rules
  end

  def renewal_ranges
    JrcRelationship::RenewalWindow.ranges(rules: renewal_rules)
  end

  def survey_filters
    params.permit(:assignment_id, :company_id, :contact_id, :owner_id, :agent_id, :team_id, :business_unit_id, :unit_id,
                  :contract_id, :product_id, :type, :classification, :treatment_status, :source_type, :record_status,
                  :definition_id, :rule_id, :record_id,
                  :portfolio_owner_id, :portfolio_status, :segment_id, :complexity, :mode,
                  :from, :to, :period_basis, :score_min, :score_max, :channel, :q)
  end

  def save_record
    attrs = record_attributes
    if params.dig(
      :record, :plan
    )
      attrs[:plan] =
        params.require(:record).permit(plan: [:cause, :hypothesis, :strategy, :actions, :concessions, :approval_status])[:plan]
    end
    attrs.merge!(params.require(:record).permit(:period_from, :period_to, :notes,
                                                milestones: [:title, :due_at, :status, :owner_id, :evidence, :notes, :activity_id, :task_id,
                                                             :ticket_id, :qbr_id]))
    assign_structured_collections!(attrs)
    result = JrcRelationship::Workflow.new(relationship_context).save(kind: params[:kind], attributes: attrs, id: params[:id])
    render json: presenter.record(result[:record]).merge(survey_token: result[:survey_token]), status: params[:id] ? :ok : :created
  end

  def record_attributes
    params.require(:record).permit(
      :assignment_id, :request_id, :lock_version, :owner_id, :reason, :status, :priority, :due_at,
      :result, :kind, :severity, :outcome, :title, :target_on, :project_id, :scheduled_at, :agenda, :summary,
      :proposed_mrr_cents, :renewed_contract_id, :product_id, :contract_id, :source_contract_id, :source_product_id,
      :potential_cents, :evidence, :expansion_kind, :meeting_url, :recording_url, :provider, :contact_id,
      plan: [:cause, :hypothesis, :strategy, :actions, :concessions], goals: [], participants: [], decisions: []
    )
  end

  def assign_structured_collections!(attrs)
    # Structured collections are limited to finite work items, never domain identity copies.
    %w[goals participants decisions].each do |key|
      value = params.dig(:record, key)
      next if value.nil?

      validate_structured_collection!(value)

      attrs[key] = value.map do |row|
        row.permit(:metric, :baseline, :target, :current, :due_at, :status, :title, :name, :email,
                   :owner_id, :evidence, :notes, :activity_id, :task_id, :ticket_id, :qbr_id, :product_id, :user_id, :participant_type,
                   :decision_key).to_h
      end
    end
  end

  def validate_structured_collection!(value)
    return if value.is_a?(Array) && value.length <= 50 && value.all? { |row| row.respond_to?(:permit) }

    raise ArgumentError, 'Use at most 50 structured work items'
  end
end
