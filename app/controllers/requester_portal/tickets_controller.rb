# frozen_string_literal: true

# Reuses the native customer-facing controller and all its create/reply/download
# services. Only the authentication adapter and the dedicated shell contract vary.
class RequesterPortal::TicketsController < Api::V1::Widget::ServiceDeskController
  include RequesterPortal::NativeSession

  skip_before_action :set_web_widget, :set_contact, :verified_service_desk_identity!
  protect_from_forgery with: :exception, prepend: true
  before_action :authenticate_user!
  before_action :bind_requester_context
  before_action :require_own_reply, only: :reply
  before_action :require_current_master_profile, only: :create
  after_action :hide_native_credentials

  def index
    values = JrcServiceDesk::Input.attributes(request.query_parameters, %w[q phase from to page])
    query = values.fetch('q', '')
    raise ArgumentError unless query.is_a?(String) && query.size <= 200

    rows = JrcServiceDesk::TicketSearch.apply(portal_scope.tickets, query)
    if values['phase'].present?
      raise ArgumentError unless %w[open waiting resolved closed cancelled].include?(values['phase'])

      rows = rows.where(jrc_service_desk_ticket_statuses: { phase: values['phase'] })
    end
    rows = rows.where('jrc_service_desk_tickets.opened_at >= ?', Date.iso8601(values['from']).beginning_of_day) if values['from'].present?
    rows = rows.where('jrc_service_desk_tickets.opened_at < ?', Date.iso8601(values['to']).next_day.beginning_of_day) if values['to'].present?
    page = Integer(values.fetch('page', 1).to_s, 10)
    raise ArgumentError unless page.between?(1, 100_000)

    total = rows.count
    records = rows.order(created_at: :desc, id: :desc).offset((page - 1) * 20).limit(20)
    render json: { tickets: records.map { |ticket| ticket_payload(ticket) }, page: page, total: total, per_page: 20 }
  end

  def show
    ticket = portal_ticket
    details = JrcServiceDesk::PortalTicketDetails.new(scope: portal_scope, ticket: ticket).call
    details[:sla] = [] unless sla_visible?(ticket)
    render json: { ticket: ticket_payload(ticket), notes: notes_payload(ticket),
                   conversations: own_ticket?(ticket) ? ticket_conversations(ticket).order(:id).pluck(:id).map(&:to_s) : [],
                   replies: customer_messages(ticket).map { |message| portal_presenter.customer_message(message) },
                   public_messages: public_messages(ticket).timeline.map { |message| portal_presenter.customer_message(message) },
                   can_reply: own_ticket?(ticket) }.merge(details)
  end

  def public_attachment
    message = public_messages(portal_ticket).messages.find { |row| row.id == JrcServiceDesk::Input.id(params[:message_id]) }
    raise ActiveRecord::RecordNotFound unless message

    file = message.attachments.find(JrcServiceDesk::Input.id(params[:attachment_id])).file
    return render json: { code: 'attachment_scan_unavailable' }, status: :conflict unless file.blob.metadata['service_desk_scan_state'] == 'clean'

    authorize_portal_attachment!(file)
    send_data file.download, filename: file.filename.to_s, type: 'application/octet-stream', disposition: 'attachment'
  end

  def services
    render json: { services: portal_scope.services.order(:name, :id).limit(100).map do |service|
      portal_presenter.service(service, contact: portal_scope.contact).merge(category: service.default_category&.name, unit: service.unit.name)
    end }
  end

  private

  def bind_requester_context
    @contact_inbox = requester_grant.contact_inbox
    @contact = requester_grant.contact
    @current_account = requester_grant.account
    Current.account = @current_account
    portal_scope
  end

  def portal_scope
    @portal_scope ||= JrcServiceDesk::RequesterPortalScope.new(grant: requester_grant, user: current_user)
  end

  def portal_identity_proof
    JrcServiceDesk::PortalSessionProof.new(grant: requester_grant, user: current_user)
  end

  def own_ticket?(ticket)
    ticket.requester_id == requester_grant.contact_id
  end

  def require_own_reply
    forbidden unless own_ticket?(portal_ticket)
  end

  def require_current_master_profile
    contact = requester_grant.contact
    valid = contact.name.present? && JrcCustomers::Identity.email(contact.email) && JrcCustomers::Identity.phone(contact.phone_number)
    return render json: { code: 'master_profile_incomplete' }, status: :unprocessable_entity unless valid

    values = ticket_attributes(JrcServiceDesk::Input.attributes(request.request_parameters, %w[ticket files]))
    description = values.is_a?(Hash) ? values['description'] || values[:description] : nil
    raise ArgumentError unless description.is_a?(String) && description.strip.size.between?(1, 20_000)
  end

  def incoming_messages(ticket)
    @current_account.messages.where(conversation_id: ticket_conversations(ticket).select(:id), message_type: :incoming,
                                    sender: ticket.requester, private: false)
  end

  def sla_visible?(ticket)
    requester_grant.expose_sla? && ticket.contract_id && ticket.service &&
      JrcServiceDesk::PortalCatalogue.new(contact: ticket.requester, service: ticket.service).contracts.any? { |contract| contract.id == ticket.contract_id }
  end

  def public_messages(ticket)
    JrcServiceDesk::PortalPublicMessages.new(scope: portal_scope, ticket: ticket)
  end

  def hide_native_credentials
    RequesterPortal::NativeSession::HEADERS.each { |key| response.headers.delete(key) }
  end
end
