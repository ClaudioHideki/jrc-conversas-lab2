# frozen_string_literal: true

# Native, currently authorized sources only; the dossier is not an external-system result.
class JrcNico::Helpdesk::GroupEvidence
  def initialize(context:, event:, group_key:, input:)
    @context = context
    @event = event
    @ticket = context.ticket(event.ticket_id)
    @group = group_key
    @input = input
    @resources = [[@ticket.class.name, @ticket.id]]
  end

  def call
    value = { evidence: [ticket_evidence], resources: @resources, required_fields: [], missing: [] }
    customer_evidence(value) if %w[A1 A2 A3 A4 B1 C2 D2].include?(@group)
    contract_evidence(value) if %w[A1 D2].include?(@group)
    history_evidence(value) if %w[C1 E].include?(@group)
    knowledge_evidence(value) if %w[B2 E].include?(@group)
    catalogue_evidence(value) if @group == 'D1'
    broker_evidence(value) if @group == 'C2'
    JrcNico::Helpdesk::GroupNativeActions.new(context: @context, event: @event, group_key: @group, input: @input).evidence!(value)
    value
  end

  private

  def ticket_evidence
    { kind: 'native_ticket', id: @ticket.id, unit_id: @ticket.unit_id, company_id: @ticket.company_id,
      title: @ticket.title, status_id: @ticket.status_id, lock_version: @ticket.lock_version }
  end

  def customer_evidence(value)
    Pundit.authorize(@context.native.to_h, @ticket, :view_customer?)
    contact = @context.access.contact(@ticket.requester_id)
    @resources.push(['Contact', contact.id], ['JrcNico::ServiceTicketCustomer', @ticket.id])
    value[:evidence] << { kind: 'native_requester', id: contact.id, company_id: contact.company_id }
    value[:missing] << 'customer_admin_identity_not_verified' if %w[A2 A4 B1].include?(@group)
  end

  def contract_evidence(value)
    contracts = customer_contracts
    contracts.each do |contract|
      JrcNico::DomainAccess.authorize_resource!(@context.access, contract.class.name, contract.id)
      @resources << [contract.class.name, contract.id]
      value[:evidence] << { kind: 'native_crm_contract', id: contract.id, number: contract.contract_number,
                            status: contract.status, billing_verified: false }
    end
    value[:missing] << 'native_contract_not_found' if contracts.empty?
  end

  def customer_contracts
    scope = JrcServiceDesk::CatalogueContracts.new(@context.native).scope
    scope.includes(:contact, :deal).order(:id).limit(200).select do |contract|
      JrcServiceDesk::CatalogueContracts.belongs_to?(contract, @ticket.requester, @ticket.company_id)
    end.first(20)
  end

  def history_evidence(value)
    raise Pundit::NotAuthorizedError unless @context.native.capability?(:history_view)

    closed_history_scope.order(id: :desc).limit(10).each do |ticket|
      evidence = closed_history_evidence(ticket)
      value[:evidence] << evidence if evidence
    end
  end

  def closed_history_scope
    scope = @context.tickets.where(unit_id: @ticket.unit_id, company_id: @ticket.company_id)
    scope = scope.where(requester_id: @ticket.requester_id) unless @ticket.company_id
    scope = scope.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: 'closed' }).where.not(id: @ticket.id)
    if @input['query'].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@input['query'])}%"
      scope = scope.where('jrc_service_desk_tickets.title ILIKE ?', query)
    end
    scope
  end

  def closed_history_evidence(ticket)
    @context.ticket(ticket.id)
    Pundit.authorize(@context.native.to_h, ticket, :view_history?)
    close = ticket.lifecycle_transitions.where(action: 'close').order(:id).last
    return unless close

    JrcNico::DomainAccess.authorize_resource!(@context.access, close.class.name, close.id)
    @resources.push([ticket.class.name, ticket.id], [close.class.name, close.id])
    closed_history_projection(ticket, close)
  end

  def closed_history_projection(ticket, close)
    solution = close.payload['solution'] if JrcServiceDesk::TicketPolicy.new(@context.native.to_h, ticket).view_notes?
    @resources << ['JrcNico::ServiceTicketNotes', ticket.id] if solution
    { kind: 'native_closed_solution', id: close.id, ticket_id: ticket.id,
      title: ticket.title, solution: solution, closed_at: close.occurred_at.iso8601(6) }
  end

  def knowledge_evidence(value)
    return if @input['query'].blank?

    rows = JrcNico::KnowledgeDocument.where(account: @context.account).approved
                                     .where("to_tsvector('portuguese', title || ' ' || body) @@ plainto_tsquery('portuguese', ?)", @input['query'])
                                     .order(:id).limit(5)
    rows.each do |row|
      @resources << [row.class.name, row.id]
      value[:evidence] << { kind: 'approved_native_knowledge', id: row.id, title: row.title, body: row.body.first(4000), digest: row.digest }
    end
  end

  def catalogue_evidence(value)
    classification = @input.fetch('classification', {})
    form = JrcServiceDesk::CatalogueForm.new(user_context: @context.native.to_h).call(parameters: catalogue_parameters(classification))
    value[:form_fields] = form.fetch(:form_fields)
    answers = @ticket.service_fields.merge(classification.fetch('service_fields', {}))
    value[:required_fields] = missing_catalogue_fields(form, answers)
    value[:evidence] << { kind: 'native_catalogue', id: @ticket.id, revision: form.fetch(:revision), fields: form.fetch(:form_fields) }
    value[:missing] << 'required_catalogue_answers_missing' if value[:required_fields].any?
  end

  def catalogue_parameters(classification)
    { 'unit_id' => @ticket.unit_id, 'service_id' => @ticket.service_id,
      'ticket_type_id' => @ticket.ticket_type_id, 'category_id' => @ticket.category_id,
      'subcategory_id' => @ticket.subcategory_id }.merge(classification.slice('ticket_type_id', 'category_id', 'subcategory_id'))
  end

  def missing_catalogue_fields(form, answers)
    form.fetch(:form_fields).select do |field|
      answer = answers[field['key']]
      field['required'] && (answer.nil? || answer == '')
    end.pluck('key')
  end

  def broker_evidence(value)
    unless @input['binding_id'] && @input['conversation_id']
      value[:required_fields] += %w[binding_id conversation_id]
      value[:missing] << 'explicit_ticket_conversation_binding_required'
      return
    end
    binding, conversation = authorized_broker_binding
    policy = JrcBrokerPolicy.new(@context.native.to_h, binding)
    raise Pundit::NotAuthorizedError unless policy.status?

    @resources << ['Conversation', conversation.id]
    value[:broker] = { binding_id: binding.id, conversation_id: conversation.display_id, status: 'not_requested', pair_allowed: false }
    return unless @input['check_broker_status'] == true

    value[:broker].merge!(broker_health(binding, policy))
  end

  def authorized_broker_binding
    raise Pundit::NotAuthorizedError unless @context.account.feature_enabled?('jrc_broker') && JrcBroker::Configuration.enabled?

    binding = JrcBrokerInboxBinding.where(account: @context.account).find(@input['binding_id'])
    conversation = @context.access.conversation(@input['conversation_id'])
    valid = conversation.inbox_id == binding.inbox_id && conversation.contact_id == @ticket.requester_id &&
            @ticket.ticket_conversations.exists?(account_id: @context.account.id, conversation_id: conversation.id)
    raise Pundit::NotAuthorizedError unless valid && matching_contact_inbox?(conversation, binding)

    [binding, conversation]
  end

  def matching_contact_inbox?(conversation, binding)
    conversation.contact_inbox&.inbox_id == binding.inbox_id && conversation.contact_inbox&.contact_id == @ticket.requester_id
  end

  def broker_health(binding, policy)
    # This is the sole native, explicit operator-requested read. No pair call is made.
    status = JrcBroker::Control.new(account: @context.account, user: @context.member.user,
                                    account_user: @context.member, binding: binding).status
    allowed = policy.pair? && Array(status['allowedActions']).include?('pair')
    { status: status['integrationStatus'], pair_allowed: allowed,
      identity_approved: status['identityApproved'] == true, route_name: 'jrc_broker_connections' }
  end
end
