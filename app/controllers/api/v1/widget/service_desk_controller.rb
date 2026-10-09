# frozen_string_literal: true

class Api::V1::Widget::ServiceDeskController < Api::V1::Widget::BaseController
  wrap_parameters false
  before_action :verified_service_desk_identity!
  after_action :no_cache
  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from JrcServiceDesk::PortalIdentityRequired, with: :forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :unavailable
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, with: :invalid_input
  rescue_from JrcServiceDesk::IdempotencyConflict, with: :conflict

  def index
    values = JrcServiceDesk::Input.attributes(request.query_parameters, %w[website_token q])
    query = values.fetch('q', '')
    raise ArgumentError unless query.is_a?(String) && query.size <= 200

    rows = JrcServiceDesk::TicketSearch.apply(portal_scope.tickets, query)
    render json: { tickets: rows.order(created_at: :desc).limit(100).map { |row| ticket_payload(row) } }
  end

  def services
    rows = portal_scope.services.order(:name, :id).limit(100)
    render json: { services: rows.map { |row| portal_presenter.service(row, contact: portal_scope.contact) } }
  end

  def knowledge
    values = JrcServiceDesk::Input.attributes(request.query_parameters, %w[website_token q])
    rows = portal_scope.knowledge(values.fetch('q', ''))
    render json: { articles: rows.map { |article| public_article(article) } }
  end

  def show
    ticket = portal_ticket
    render json: {
      ticket: ticket_payload(ticket), notes: notes_payload(ticket),
      conversations: ticket_conversations(ticket).order(:id).pluck(:id).map(&:to_s),
      replies: customer_messages(ticket).map { |message| portal_presenter.customer_message(message) },
      tasks: portal_scope.tasks(ticket).order(:id).map { |row| portal_presenter.task(row) }
    }.merge(JrcServiceDesk::PortalTicketDetails.new(scope: portal_scope, ticket: ticket).call)
  end

  def create
    values = JrcServiceDesk::Input.attributes(request.request_parameters, %w[website_token ticket files])
    fields = ticket_attributes(values)
    service = JrcServiceDesk::PortalCreationService.new(contact_inbox: @contact_inbox, identity_proof: portal_identity_proof)
    row = service.call(attributes: fields, files: values.fetch('files', []), idempotency_key: request.headers['Idempotency-Key'])
    render json: { applied: true, ticket: ticket_payload(row.ticket), message_id: row.message_id.to_s,
                   conversation_id: row.conversation_id.to_s }, status: :created
  end

  def reply
    values = JrcServiceDesk::Input.attributes(request.request_parameters, %w[website_token body conversation_id files])
    validate_reply_body!(values)
    key = JrcServiceDesk::Input.request_key(request.headers['Idempotency-Key'])
    files = values.fetch('files', [])
    uploads = JrcServiceDesk::InteractionAttachments.prepare(files)
    ticket = portal_ticket
    row = persist_reply(ticket, values, key, files, uploads)
    render json: { applied: true, ticket_id: ticket.id.to_s, message_id: row.id.to_s }, status: :created
  end

  def attachment
    ticket = portal_ticket
    note = portal_scope.notes(ticket).find(JrcServiceDesk::Input.id(params[:note_id]))
    file = note.files.find(JrcServiceDesk::Input.id(params[:attachment_id]))
    return render json: { code: 'attachment_scan_unavailable' }, status: :conflict unless file.blob.metadata['service_desk_scan_state'] == 'clean'

    send_data file.download, filename: file.filename.to_s, type: 'application/octet-stream', disposition: 'attachment'
  end

  def customer_attachment
    file = customer_attachment_file(portal_ticket)
    return render json: { code: 'attachment_scan_unavailable' }, status: :conflict unless file.blob.metadata['service_desk_scan_state'] == 'clean'

    send_data file.download, filename: file.filename.to_s, type: 'application/octet-stream', disposition: 'attachment'
  end

  private

  def notes_payload(ticket)
    portal_scope.notes(ticket).order(:id).map { |row| portal_presenter.note(row) }
  end

  def public_article(article)
    { id: article.id.to_s, title: article.title, description: article.description.to_s,
      path: Rails.application.routes.url_helpers.public_portal_article_path(slug: article.portal.slug, article_slug: article.slug) }
  end

  def ticket_attributes(values)
    fields = values.fetch('ticket')
    fields = JSON.parse(fields) if fields.is_a?(String) && fields.bytesize <= 250_000
    fields
  end

  def validate_reply_body!(values)
    body = values.fetch('body')
    raise ArgumentError unless body.is_a?(String) && body.strip.size.between?(1, 20_000)
  end

  def persist_reply(ticket, values, key, files, uploads)
    JrcServiceDesk::Base.transaction do
      ticket.unit.lock!
      @portal_scope = nil # Recheck verified identity and active operator/unit under the lock.
      ticket = portal_ticket
      conversation = ticket_conversations(ticket).find(JrcServiceDesk::Input.id(values.fetch('conversation_id')))
      fingerprint = reply_fingerprint(ticket, conversation, values, uploads)
      source_key = "jrc-sd-portal:#{ticket.id}:#{@contact.id}:#{Digest::SHA256.hexdigest(key)}"
      previous = conversation.messages.where(account_id: @current_account.id, sender: @contact, message_type: :incoming)
                             .find_by(source_id: source_key)
      if previous
        raise JrcServiceDesk::IdempotencyConflict unless previous.content_attributes['service_desk_portal_fingerprint'] == fingerprint

        next previous
      end
      attributes = reply_attributes(ticket, values, key, fingerprint, source_key).merge(files: files)
      JrcServiceDesk::PortalCustomerMessage.create!(conversation: conversation, contact: @contact, **attributes)
    end
  end

  def reply_fingerprint(ticket, conversation, values, uploads)
    JrcServiceDesk::CanonicalJson.digest(
      'body' => values.fetch('body'), 'ticket_id' => ticket.id, 'conversation_id' => conversation.id,
      'files' => uploads.map { |file| file.except(:io).stringify_keys }
    )
  end

  def reply_attributes(ticket, values, key, fingerprint, source_key)
    { content: values.fetch('body'), source_id: source_key,
      content_attributes: { 'service_desk_ticket_id' => ticket.id.to_s, 'service_desk_portal_request_key' => key,
                            'service_desk_portal_fingerprint' => fingerprint } }
  end

  def ticket_conversations(ticket)
    portal_scope.conversations.where(id: ticket.ticket_conversations.select(:conversation_id))
  end

  def incoming_messages(ticket)
    @current_account.messages.where(conversation_id: ticket_conversations(ticket).select(:id), message_type: :incoming, sender: @contact)
  end

  def customer_attachment_file(ticket)
    message = incoming_messages(ticket).find(JrcServiceDesk::Input.id(params[:message_id]))
    raise ActiveRecord::RecordNotFound unless message.content_attributes['service_desk_ticket_id'].to_s == ticket.id.to_s

    message.attachments.find(JrcServiceDesk::Input.id(params[:attachment_id])).file
  end

  def customer_messages(ticket)
    incoming_messages(ticket).order(created_at: :desc, id: :desc).limit(100)
                             .select { |row| row.content_attributes['service_desk_ticket_id'].to_s == ticket.id.to_s }.reverse
  end

  def verified_service_desk_identity!
    no_cache
    raise Pundit::NotAuthorizedError unless auth_token_params[:inbox_id].to_s == @web_widget.inbox.id.to_s

    portal_scope
  end

  def portal_scope
    @portal_scope ||= JrcServiceDesk::PortalScope.new(contact_inbox: @contact_inbox, identity_proof: portal_identity_proof)
  end

  def portal_identity_proof
    @portal_identity_proof ||= JrcServiceDesk::PortalIdentityProof.new(
      identifier: request.headers[JrcServiceDesk::PortalIdentityProof::IDENTIFIER_HEADER],
      token: request.headers[JrcServiceDesk::PortalIdentityProof::TOKEN_HEADER]
    )
  end

  def portal_ticket
    portal_scope.tickets.find(JrcServiceDesk::Input.id(params[:id]))
  end

  def ticket_payload(ticket)
    portal_presenter.ticket(ticket)
  end

  def portal_presenter
    @portal_presenter ||= JrcServiceDesk::PortalPresenter.new
  end

  def no_cache
    response.headers['Cache-Control'] = 'no-store'
  end

  def forbidden
    render json: { code: 'verified_customer_identity_required' }, status: :forbidden
  end

  def unavailable
    render json: { code: 'not_found' }, status: :not_found
  end

  def invalid_input
    render json: { code: 'invalid_input' }, status: :unprocessable_entity
  end

  def conflict
    render json: { code: 'conflict' }, status: :conflict
  end
end
