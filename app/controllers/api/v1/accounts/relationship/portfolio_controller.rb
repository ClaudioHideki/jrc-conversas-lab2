class Api::V1::Accounts::Relationship::PortfolioController < Api::V1::Accounts::Relationship::BaseController
  def index
    records, meta = page(filtered_assignments.includes(:company, :contact, :owner, :business_unit).order(updated_at: :desc, id: :desc))
    records = records.to_a
    presenter.preload(records)
    render json: { payload: records.map { |row| presenter.assignment(row) }, meta: meta }
  end

  def show
    record = relationship_context.assignment(params[:id])
    presenter.preload([record])
    snapshots = JrcRelationship::HealthSnapshot.where(account_id: Current.account.id, assignment_id: record.id, viewer_id: Current.user.id,
                                                      access_signature: relationship_context.access_signature)
    snapshots = JrcRelationship::SnapshotAccess.scope(relationship_context, snapshots)
    history = snapshots.order(calculated_at: :desc, id: :desc).limit(30).to_a
    health_history = history.each_with_index.map do |snapshot, index|
      snapshot.attributes.slice('id', 'score', 'band', 'factors', 'calculated_at', 'config_version', 'config_scope_key').merge(
        'change' => JrcRelationship::HealthChange.call(previous: history[index + 1]&.attributes&.symbolize_keys,
                                                       current: snapshot.attributes.symbolize_keys)
      )
    end
    render json: presenter.assignment(record).merge(health_history: health_history)
  end

  def create
    raise Pundit::NotAuthorizedError unless relationship_context.policy.team?

    attrs = params.require(:assignment).permit(:company_id, :contact_id, :owner_id, :team_id, :business_unit_id,
                                               settings: [:segment_id, :product_id, :complexity])
    if attrs[:contact_id].present?
      contact = JrcOperations::Access.contact!(relationship_context.member, attrs[:contact_id])
      attrs[:company_id], attrs[:contact_id] = contact.company_id, nil if contact.company_id
    end
    relationship_context.assignable_users.find(attrs[:owner_id]) if attrs[:owner_id].present?
    record = JrcRelationship::Assignment.new(attrs.merge(account: Current.account))
    initialize_assignment!(record)
    save_assignment!(record, attrs)
    render json: presenter.assignment(record), status: :created
  end

  def update
    record = relationship_context.assignment(params[:id], write: true)
    attrs = params.require(:assignment).permit(:owner_id, :team_id, :status, settings: [:segment_id, :product_id, :complexity])
    raise Pundit::NotAuthorizedError unless relationship_context.policy.team?

    relationship_context.assignable_users.find(attrs[:owner_id]) if attrs[:owner_id].present?
    record.with_lock do
      before = record.attributes.slice(*attrs.keys)
      record.update!(attrs)
      if attrs.key?(:owner_id)
        record.actions.where(status: JrcRelationship::Action::ACTIVE_STATUSES).find_each do |action|
          action.update!(owner_id: record.owner_id)
          action.activity.update!(user_id: record.owner_id) if action.activity && record.owner_id
        end
      end
      relationship_context.audit!(record, before: before, after: attrs.to_h, action: 'assignment_updated')
    end
    render json: presenter.assignment(record)
  end

  def recalculate
    record = relationship_context.assignment(params[:id], write: true)
    data = JrcRelationship::Processor.new(context: relationship_context, assignment: record).call
    render json: presenter.assignment(record, signals: data)
  end

  def activity
    record = relationship_context.assignment(params[:id], write: true)
    record.with_lock do
      activity = JrcRelationship::Workflow.new(relationship_context).activity!(assignment: record,
                                                                               title: params.require(:title), due_at: params[:due_at],
                                                                               kind: params.fetch(:kind, 'task'),
                                                                               request_id: params.require(:request_id))
      render json: { id: activity.id, route: 'crm_activities' }, status: :created
    end
  end

  def manual_attendance
    record = relationship_context.assignment(params[:id], write: true)
    attrs = params.require(:attendance).permit(:request_id, :title, :description, :activity_type, :due_at, :completed,
                                               :contact_id, :deal_id, :contract_id, :product_id)
    activity = JrcRelationship::ManualAttendance.new(relationship_context).call(assignment: record, attributes: attrs)
    render json: { id: activity.id, status: activity.status, route: 'crm_activities' }, status: :created
  end

  def recommendations
    render json: presenter.recommendations(relationship_context.assignment(params[:id]))
  end

  def work_context
    record = relationship_context.assignment(params[:id])
    render json: JrcRelationship::WorkContext.new(context: relationship_context, assignment: record, period: report_period).call.except(:_source_ids)
  end

  def batch
    count = JrcRelationship::PortfolioBatch.new(relationship_context, params).call
    render json: { updated: count }
  end

  def channels
    record = relationship_context.assignment(params[:id])
    customer = record.customer_context(relationship_context.member)
    contacts = customer.contacts.order(:id).limit(50).select { |contact| ContactPolicy.new(relationship_context.to_h, contact).show? }
    render json: { company_id: record.company_id, contacts: contacts.map do |contact|
      { id: contact.id, name: contact.name, phone_number: contact.phone_number, email: contact.email }
    end,
                   conversations: customer.conversations.order(updated_at: :desc).limit(20).pluck(:display_id, :contact_id),
                   channel_conversations: customer.conversations.includes(:inbox).order(updated_at: :desc).limit(50).map do |conversation|
                     { id: conversation.id, display_id: conversation.display_id, inbox: conversation.inbox.name,
                       channel: conversation.inbox.channel_type, inbox_id: conversation.inbox_id, can_reply: conversation.can_reply?,
                       supports_whatsapp_templates: conversation.inbox.channel_type == 'Channel::Whatsapp' }
                   end,
                   can_crm: JrcOperations::Access.crm?(relationship_context.member),
                   can_service_desk: customer.overview[:capabilities][:service_desk] }
  end

  def native_csat
    record = relationship_context.assignment(params[:id], write: true)
    customer = record.customer_context(relationship_context.member)
    conversation = customer.conversations.find(params.require(:conversation_id))
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(relationship_context.to_h, conversation).show?

    conversation.with_lock do
      previous = conversation.messages.where(content_type: :input_csat).order(:id).last
      unless previous
        days = relationship_context.configuration(record).effective_rules['survey_frequency_days']
        recent = Message.where(account: Current.account, conversation_id: customer.conversations.select(:id), content_type: :input_csat)
                        .exists?(['created_at > ?', days.days.ago])
        raise ArgumentError, 'Survey frequency limit reached' if recent

        CsatSurveyService.new(conversation: conversation).perform
      end
      message = previous || conversation.messages.where(content_type: :input_csat).order(:id).last
      raise ArgumentError, 'Native CSAT requires a resolved conversation, enabled inbox and an available messaging window/template' unless message

      relationship_context.audit!(record, after: { message_id: message.id, conversation_id: conversation.id }, action: 'native_csat_requested')
      render json: { message_id: message.id, conversation_id: conversation.display_id }
    end
  end

  private

  def initialize_assignment!(record)
    record.status = 'onboarding' if relationship_context.configuration.effective_rules['handoff_acceptance_required']
  end

  def save_assignment!(record, attrs)
    record.transaction do
      validate_assignment_eligibility!(record)
      record.save!
      relationship_context.assignment(record.id)
      relationship_context.audit!(record, after: attrs.to_h, action: 'assignment_created')
      audit_eligibility_exception!(record)
    end
  end

  def audit_eligibility_exception!(record)
    return unless record.settings['eligibility_exception']

    relationship_context.audit!(record, after: record.settings['eligibility_exception'], action: 'eligibility_exception_approved')
  end

  def validate_assignment_eligibility!(record)
    return unless relationship_context.configuration.effective_rules['eligibility_mode'] == 'active_contract_product'

    reason = JrcRelationship::CommercialEligibility.reason(record.customer_context(relationship_context.member).contracts,
                                                           account: Current.account, product_id: record.settings['product_id'])
    return unless reason

    exception = params.dig(:assignment, :exception_reason)
    raise ArgumentError, reason unless exception.is_a?(String) && exception.strip.length.between?(1, 2000)

    record.settings = record.settings.merge('eligibility_exception' => eligibility_exception(exception))
  end

  def eligibility_exception(exception)
    { 'reason' => exception.strip, 'approved_by_id' => Current.user.id, 'approved_at' => Time.current.iso8601 }
  end
end
