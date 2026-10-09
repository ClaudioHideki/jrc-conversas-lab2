class Api::V1::Accounts::Relationship::SurveyAdministrationController < Api::V1::Accounts::Relationship::BaseController
  before_action do
    raise Pundit::NotAuthorizedError unless relationship_context.policy.configure? && relationship_context.policy.admin?
  end

  def index
    model = JrcRelationship::SurveyAdministration::MODELS.fetch(params[:kind])
    render json: { payload: model.where(account: Current.account).order(:id).limit(500) }
  end

  def save
    attrs = if params[:kind] == 'definitions'
              params.require(:record).permit(:name, :code, :kind, :status,
                                             questions: [:key, :text, :type, :required, :min, :max, { condition: [:question, :operator, :value],
                                                                                                      options: [:value, :label, :score] }],
                                             settings: [:low_threshold, :recovery_enabled, :recovery_sla_hours, :thank_you, :ces_direction,
                                                        :available_from, :available_until])
            else
              params.require(:record).permit(:name, :definition_id, :execution_member_id, :active, :priority,
                                             matchers: [:source_type, :channel_type, :company_id, :unit_id, :team_id, :inbox_id, :product_id,
                                                        :contract_id],
                                             settings: [:channel, :frequency_days, :frequency_scope, :delay_minutes, :expires_hours,
                                                        :max_attempts, :resend_minutes, :consent_required, :delivery_inbox_id,
                                                        { whatsapp_template: [:inbox_id, :content, :template_fingerprint, { template_params: {} }] }])
            end
    row = administration.save(kind: params[:kind], id: params[:id], attributes: attrs.to_h, expected_version: params.dig(:record, :version))
    render json: row, status: params[:id] ? :ok : :created
  end

  def duplicate
    render json: administration.duplicate(kind: params[:kind], id: params[:id], code: params[:code]), status: :created
  end

  def history
    row = JrcRelationship::SurveyAdministration::MODELS.fetch(params[:kind]).where(account: Current.account).find(params[:id])
    render json: { payload: JrcRelationship::SurveyVersion.where(account: Current.account, entity_type: row.class.name,
                                                                 entity_id: row.id).order(version: :desc) }
  end

  def preview
    type = params.require(:source_type)
    raise ArgumentError, 'Unsupported survey source' unless JrcRelationship::SurveySource::TYPES.include?(type)

    source = type.constantize.where(account_id: Current.account.id).find(params.require(:source_id))
    result = JrcRelationship::SurveyEngine.new(source: source, cycle_key: params.require(:cycle_key),
                                               member: Current.account_user, contract_id: params[:contract_id],
                                               product_id: params[:product_id]).preview(ignore_activation: true)
    render json: result.except(:source, :rule).merge(rule: result[:rule]&.snapshot)
  end

  def decisions
    # Only origins visible through native grants, never all account decisions for a scoped manager.
    rows = JrcRelationship::SurveyDispatchDecision.where(account: Current.account)
    source_type = params.require(:source_type)
    raise ArgumentError, 'Unsupported survey source' unless JrcRelationship::SurveySource::TYPES.include?(source_type)

    source = source_type.constantize.where(account_id: Current.account.id).find(params.require(:source_id))
    JrcRelationship::SurveySource.new(source, relationship_context)
    render json: { payload: rows.where(source_type: source_type, source_id: source.id).order(id: :desc).limit(100) }
  end

  def origins
    visibility = JrcCustomers::Visibility.new(account: Current.account, user: Current.user, account_user: Current.account_user)
    calls = visibility.calls(contact_ids: Current.account.contacts.select(:id), conversation_ids: visibility.conversations.select(:id))
    rows = mapped_origins(visibility.conversations) { |row| "Atendimento ##{row.display_id}" }
    rows += mapped_origins(visibility.tickets, &:title)
    rows += mapped_origins(relationship_context.records(JrcRelationship::Qbr), &:title)
    rows += mapped_origins(calls) { |row| "Ligação ##{row.id}" } if calls
    rows += attendance_origins(visibility)
    render json: { payload: rows }
  end

  private

  def mapped_origins(scope)
    scope.order(id: :desc).limit(100).map { |row| { type: row.class.name, id: row.id, label: yield(row) } }
  end

  def attendance_origins(visibility)
    scope = visibility.crm(Current.account.jrc_crm_activities, owner: :user_id)
                      .where("metadata -> 'relationship_manual_attendance' = 'true'::jsonb").order(id: :desc).limit(100)
    scope.select { |row| JrcRelationship::ManualAttendance.eligible?(row) }.map do |row|
      { type: row.class.name, id: row.id, label: row.title }
    end
  end

  def administration
    @administration ||= JrcRelationship::SurveyAdministration.new(relationship_context)
  end
end
