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
    snapshots = JrcRelationship::HealthSnapshot.where(account_id: Current.account.id, assignment_id: record.id, viewer_id: Current.user.id, access_signature: relationship_context.access_signature)
    snapshots = JrcRelationship::SnapshotAccess.scope(relationship_context, snapshots)
    history = snapshots.order(calculated_at: :desc, id: :desc).limit(30).to_a
    health_history = history.each_with_index.map do |snapshot, index|
      snapshot.attributes.slice('id', 'score', 'band', 'factors', 'calculated_at', 'config_version', 'config_scope_key').merge(
        'change' => JrcRelationship::HealthChange.call(previous: history[index + 1]&.attributes&.symbolize_keys,
          current: snapshot.attributes.symbolize_keys))
    end
    render json: presenter.assignment(record).merge(health_history: health_history)
  end

  def create
    raise Pundit::NotAuthorizedError unless relationship_context.policy.team?
    attrs = params.require(:assignment).permit(:company_id, :contact_id, :owner_id, :team_id, :business_unit_id, settings: [:segment_id, :product_id, :complexity])
    if attrs[:contact_id].present?
      contact = JrcOperations::Access.contact!(relationship_context.member, attrs[:contact_id])
      attrs[:company_id], attrs[:contact_id] = contact.company_id, nil if contact.company_id
    end
    relationship_context.assignable_users.find(attrs[:owner_id]) if attrs[:owner_id].present?
    record = JrcRelationship::Assignment.new(attrs.merge(account: Current.account))
    record.transaction do
      record.save!
      relationship_context.assignment(record.id)
      relationship_context.audit!(record, after: attrs.to_h, action: 'assignment_created')
    end
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
        title: params.require(:title), due_at: params[:due_at], kind: params.fetch(:kind, 'task'), request_id: params.require(:request_id))
      render json: { id: activity.id, route: 'crm_activities' }, status: :created
    end
  end

  def recommendations
    render json: presenter.recommendations(relationship_context.assignment(params[:id]))
  end

  def work_context
    record = relationship_context.assignment(params[:id])
    render json: JrcRelationship::WorkContext.new(context: relationship_context, assignment: record, period: report_period).call.except(:_source_ids)
  end

  def batch
    raise Pundit::NotAuthorizedError unless relationship_context.policy.manage?
    ids = params.require(:ids)
    raise ArgumentError, 'Select between 1 and 50 customers' unless ids.is_a?(Array) && ids.size.between?(1, 50)
    rows = relationship_context.assignments.where(id: ids).order(:id)
    raise ActiveRecord::RecordNotFound unless rows.count == ids.uniq.size
    operation = params.require(:operation)
    raise ArgumentError, 'Unsupported portfolio operation' unless %w[assign activity playbook].include?(operation)
    raise Pundit::NotAuthorizedError if operation == 'assign' && !relationship_context.policy.team?
    owner = relationship_context.assignable_users.find(params[:owner_id]) if operation == 'assign' && params[:owner_id].present?
    book = JrcRelationship::Playbook.where(account: Current.account, active: true).find(params.require(:playbook_id)) if operation == 'playbook'
    request_id = params.require(:request_id)
    JrcRelationship::Assignment.transaction do
      rows.each do |record|
        relationship_context.assignment(record.id, write: true)
        record.with_lock do
          case operation
          when 'assign'
            before = { owner_id: record.owner_id }
            record.update!(owner: owner)
            record.actions.where(status: JrcRelationship::Action::ACTIVE_STATUSES).find_each do |action|
              action.update!(owner: owner)
              action.activity.update!(user: owner) if owner && action.activity
            end
            relationship_context.audit!(record, before: before, after: { owner_id: owner&.id }, action: 'assignment_updated')
          when 'activity'
            JrcRelationship::Workflow.new(relationship_context).activity!(assignment: record, title: params.require(:title),
              due_at: params.require(:due_at), request_id: "portfolio:#{request_id}:#{record.id}")
          when 'playbook'
            JrcRelationship::Playbooks.new(relationship_context).run!(record, book.trigger_kind,
              source_key: "manual:#{request_id}", playbook_id: book.id)
            relationship_context.audit!(record, after: { playbook_id: book.id }, action: 'playbook_applied')
          end
        end
      end
    end
    render json: { updated: rows.count }
  end

  def channels
    record = relationship_context.assignment(params[:id])
    customer = record.customer_context(relationship_context.member)
    contacts = customer.contacts.order(:id).limit(50).select { |contact| ContactPolicy.new(relationship_context.to_h, contact).show? }
    render json: { company_id: record.company_id, contacts: contacts.map { |contact| { id: contact.id, name: contact.name, phone_number: contact.phone_number, email: contact.email } },
      conversations: customer.conversations.order(updated_at: :desc).limit(20).pluck(:display_id, :contact_id),
      channel_conversations: customer.conversations.includes(:inbox).order(updated_at: :desc).limit(50).map do |conversation|
        { id: conversation.id, display_id: conversation.display_id, inbox: conversation.inbox.name, channel: conversation.inbox.channel_type }
      end,
      can_crm: JrcOperations::Access.crm?(relationship_context.member), can_service_desk: customer.overview[:capabilities][:service_desk] }
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
          .where('created_at > ?', days.days.ago).exists?
        raise ArgumentError, 'Survey frequency limit reached' if recent
        CsatSurveyService.new(conversation: conversation).perform
      end
      message = previous || conversation.messages.where(content_type: :input_csat).order(:id).last
      raise ArgumentError, 'Native CSAT requires a resolved conversation, enabled inbox and an available messaging window/template' unless message
      relationship_context.audit!(record, after: { message_id: message.id, conversation_id: conversation.id }, action: 'native_csat_requested')
      render json: { message_id: message.id, conversation_id: conversation.display_id }
    end
  end
end
