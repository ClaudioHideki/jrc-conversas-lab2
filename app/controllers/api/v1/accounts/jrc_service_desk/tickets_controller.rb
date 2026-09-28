# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::TicketsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize ::JrcServiceDesk::Ticket, :index?
    query = ::JrcServiceDesk::TicketQuery.new(user_context: pundit_user, parameters: query_values, scope: policy_scope(::JrcServiceDesk::Ticket))
    render json: result_for(query.collection) { |record| presenter.ticket(record) }
  end

  def show
    raise ArgumentError unless query_values.empty?
    authorize strict_ticket, :show?
    render json: base_payload.merge(ticket: presenter.ticket(strict_ticket))
  end

  def create
    values = body_values(%w[unit_id ticket conversation_id service_id])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Ticket.new(account: Current.account, unit: unit), :create?
    ticket = ::JrcServiceDesk::CreateTicketWorkflowService.new(user_context: pundit_user).call(
      unit_id: unit.id, attributes: values.fetch('ticket'), conversation_id: values['conversation_id'], service_id: values['service_id'],
      idempotency_key: request.headers['Idempotency-Key'])
    link_id = values['conversation_id'] && ticket.ticket_conversations.find_by(conversation_id: ::JrcServiceDesk::Input.id(values['conversation_id']))&.id
    acknowledged(ticket, 'create', status: :created, result_id: link_id)
  end

  def update
    authorize strict_ticket, :show? # Field-level capabilities are rechecked by UpdateTicketService.
    values = body_values(%w[ticket expected_lock_version])
    ticket = ::JrcServiceDesk::UpdateTicketService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, attributes: values.fetch('ticket'), expected_lock_version: values.fetch('expected_lock_version'))
    acknowledged(ticket, 'update')
  end

  def assign
    authorize strict_ticket, :assign?
    values = body_values(%w[assignment expected_lock_version])
    ticket = ::JrcServiceDesk::AssignTicketService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, attributes: values.fetch('assignment'), expected_lock_version: values.fetch('expected_lock_version'))
    acknowledged(ticket, 'assign')
  end

  def transfer
    authorize strict_ticket, :transfer?
    values = body_values(%w[assignment expected_lock_version])
    ticket = ::JrcServiceDesk::TransferTicketService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, attributes: values.fetch('assignment'), expected_lock_version: values.fetch('expected_lock_version'))
    acknowledged(ticket, 'transfer')
  end

  def work_status
    authorize strict_ticket, :change_work_status?, policy_class: ::JrcServiceDesk::WorkStatusPolicy
    values = body_values(%w[status_id expected_lock_version])
    ticket = ::JrcServiceDesk::ChangeWorkStatusService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, status_id: values.fetch('status_id'), expected_lock_version: values.fetch('expected_lock_version'))
    acknowledged(ticket, 'work_status')
  end

  def add_note
    authorize strict_ticket, :add_note?
    values = body_values(%w[note])
    note = ::JrcServiceDesk::AddNoteService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, attributes: values.fetch('note'), idempotency_key: request.headers['Idempotency-Key'])
    acknowledged(strict_ticket, 'add_note', result_id: note.id)
  end

  def link_conversation
    authorize strict_ticket, :link_conversation?
    values = body_values(%w[conversation_id])
    link = ::JrcServiceDesk::LinkConversationService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, conversation_id: values.fetch('conversation_id'))
    acknowledged(strict_ticket, 'link_conversation', result_id: link.id)
  end

  def related_item
    raise ArgumentError unless query_values.empty?
    authorize strict_ticket, :show?
    kind = params[:kind].to_s
    model = { 'notes' => ::JrcServiceDesk::TicketNote, 'conversations' => ::JrcServiceDesk::TicketConversation }.fetch(kind)
    record = model.where(account_id: Current.account.id, unit_id: strict_ticket.unit_id, ticket_id: strict_ticket.id)
      .find(::JrcServiceDesk::Input.id(params[:record_id]))
    authorize record, :show?
    render json: base_payload.merge(ticket_id: strict_ticket.id.to_s, kind: kind, item: presenter.related(record, kind))
  end

  def related
    authorize strict_ticket, :show?
    kind = params[:kind].to_s
    result = ::JrcServiceDesk::RelatedRecordsQuery.new(user_context: pundit_user, ticket: strict_ticket, kind: kind, parameters: query_values).collection
    render json: result_for(result) { |record| presenter.related(record, kind) }.merge(ticket_id: strict_ticket.id.to_s, kind: kind)
  end
end
