class Api::V1::Accounts::Relationship::RecordsController < Api::V1::Accounts::Relationship::BaseController
  def index
    model = JrcRelationship::Workflow::MODELS.fetch(params[:kind])
    scope = relationship_context.records(model).where(assignment_id: filtered_assignments.select(:id))
    if model == JrcRelationship::Survey && params[:record_status].present?
      scope = case params[:record_status]
              when 'responded' then scope.where.not(responded_at: nil)
              when 'awaiting' then scope.where(responded_at: nil).where('expires_at > ?', Time.current)
              when 'expired' then scope.where(responded_at: nil).where('expires_at <= ?', Time.current)
              else raise ArgumentError, 'Invalid survey state'
              end
    end
    if model == JrcRelationship::Survey && params[:from].present?
      scope = scope.where(responded_at: report_period)
    end
    scope = scope.where(status: params[:record_status]) if params[:record_status].present? && model.column_names.include?('status')
    windows = if model == JrcRelationship::Renewal
                JrcRelationship::RenewalWindow::WINDOWS.keys.to_h { |key| [key, JrcRelationship::RenewalWindow.scope(scope, key).count] }
              end
    scope = JrcRelationship::RenewalWindow.scope(scope, params[:renewal_window]) if model == JrcRelationship::Renewal && params[:renewal_window].present?
    if params[:overdue] == 'true' && model.column_names.include?('due_at')
      scope = scope.where('due_at < ?', Time.current)
      scope = scope.where(sla_paused_at: nil) if model == JrcRelationship::Action
    end
    scope = scope.where(kind: params[:type]) if params[:type].present? && model.column_names.include?('kind')
    scope = scope.where('priority >= ?', params[:priority].to_i.clamp(0, 100)) if params[:priority].present? && model.column_names.include?('priority')
    if params[:from].present? && model.column_names.include?('due_at')
      from = Date.iso8601(params[:from]); to = Date.iso8601(params.fetch(:to, params[:from]))
      raise ArgumentError, 'Invalid period' if to < from || (to - from).to_i > 366
      scope = scope.where(due_at: from.beginning_of_day..to.end_of_day)
    end
    order = model == JrcRelationship::Action ? { priority: :desc, due_at: :asc, id: :asc } : { updated_at: :desc, id: :desc }
    records, meta = page(scope.includes(:owner, assignment: [:company, :contact]).order(order))
    records = records.to_a
    presenter.preload(records.map(&:assignment).uniq(&:id)) if [JrcRelationship::RiskCase, JrcRelationship::Renewal].include?(model)
    render json: { payload: records.map { |row| presenter.record(row) }, meta: meta.merge(renewal_windows: windows) }
  end

  def create
    save_record
  end

  def update
    save_record
  end

  def opportunity
    raise ArgumentError, 'Unsupported opportunity origin' unless %w[expansion renewals].include?(params[:kind])
    record = relationship_context.records(JrcRelationship::Workflow::MODELS.fetch(params[:kind])).find(params[:id])
    deal = JrcRelationship::Workflow.new(relationship_context).opportunity!(record, pipeline_id: params.require(:pipeline_id), stage_id: params.require(:stage_id))
    render json: { deal_id: deal.id, route: 'crm_deals' }
  end

  private

  public

  def deliver_survey
    survey = relationship_context.records(JrcRelationship::Survey).find(params[:id])
    message = JrcRelationship::SurveyDelivery.new(context: relationship_context, survey: survey, base_url: request.base_url)
      .call(conversation_id: params.require(:conversation_id))
    render json: { message_id: message.id, conversation_id: message.conversation.display_id }
  end

  def survey_link
    survey = relationship_context.records(JrcRelationship::Survey).find(params[:id])
    raise ArgumentError, 'Survey expired or already answered' if survey.responded_at || survey.expires_at <= Time.current
    render json: { url: "#{request.base_url}/jrc/relacionamento/pesquisas/#{survey.signed_id(purpose: :relationship_survey)}" }
  end

  def batch
    ids = params.require(:ids)
    raise ArgumentError, 'Select between 1 and 50 actions' unless ids.is_a?(Array) && ids.size.between?(1, 50)
    attrs = params.require(:record).permit(:status, :due_at, :priority, :result, :owner_id).to_h
    raise Pundit::NotAuthorizedError unless relationship_context.policy.manage?
    rows = relationship_context.records(JrcRelationship::Action).where(id: ids).order(:id)
    raise ActiveRecord::RecordNotFound unless rows.count == ids.uniq.size
    JrcRelationship::Action.transaction do
      rows.each { |row| JrcRelationship::Workflow.new(relationship_context).save(kind: 'actions', id: row.id,
        attributes: attrs.merge('assignment_id' => row.assignment_id, 'lock_version' => row.lock_version)) }
    end
    render json: { updated: rows.count }
  end

  private

  def save_record
    attrs = params.require(:record).permit(:assignment_id, :request_id, :lock_version, :owner_id, :reason, :status, :priority, :due_at,
      :result, :kind, :severity, :outcome, :title, :target_on, :project_id, :scheduled_at, :agenda, :summary,
      :proposed_mrr_cents, :product_id, :potential_cents, :evidence, :expansion_kind, plan: [:cause, :hypothesis, :strategy, :actions, :concessions], goals: [], participants: [], decisions: [])
    attrs[:plan] = params.require(:record).permit(plan: [:cause, :hypothesis, :strategy, :actions, :concessions, :approval_status])[:plan] if params.dig(:record, :plan)
    attrs.merge!(params.require(:record).permit(:period_from, :period_to, :notes,
      milestones: [:title, :due_at, :status, :owner_id, :evidence, :notes, :activity_id, :task_id, :ticket_id, :qbr_id]))
    # Structured collections are limited to finite work items, never domain identity copies.
    %w[goals participants decisions].each do |key|
      value = params.dig(:record, key)
      next if value.nil?
      raise ArgumentError, 'Use at most 50 structured work items' unless value.is_a?(Array) && value.length <= 50 && value.all? { |row| row.respond_to?(:permit) }
      attrs[key] = value.map { |row| row.permit(:metric, :baseline, :target, :current, :due_at, :status, :title, :name, :email,
        :owner_id, :evidence, :notes, :activity_id, :task_id, :ticket_id, :qbr_id, :product_id, :user_id, :participant_type, :decision_key).to_h }
    end
    result = JrcRelationship::Workflow.new(relationship_context).save(kind: params[:kind], attributes: attrs, id: params[:id])
    render json: presenter.record(result[:record]).merge(survey_token: result[:survey_token]), status: params[:id] ? :ok : :created
  end
end
