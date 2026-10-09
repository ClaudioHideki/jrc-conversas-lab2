# frozen_string_literal: true

# Atomic creation plus optional native conversation link, reusing the CP2 commands.
# Request context is recorded once to bind the optional relation to the same key.
class JrcServiceDesk::CreateTicketWorkflowService < JrcServiceDesk::BaseService
  def call(unit_id:, attributes:, idempotency_key:, **options)
    inputs = workflow_options(options)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    result = with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create)

      validate_conversation!(inputs[:conversation_id])
      existing = existing_ticket(unit, key, inputs)
      ticket = create_ticket(unit, attributes, key, inputs)
      initialize_workflow(ticket, inputs, key) unless existing
      ticket
    end
    capture_created(result)
    result
  end

  private

  def workflow_options(options)
    raise ArgumentError unless (options.keys - %i[conversation_id service_id origin_channel files]).empty?

    files = options.fetch(:files, [])
    uploads = JrcServiceDesk::InteractionAttachments.prepare(files)

    { conversation_id: optional_id(options[:conversation_id]),
      service_id: optional_id(options[:service_id]),
      origin_channel: options.fetch(:origin_channel, 'manual'), files: files,
      file_fingerprints: uploads.map { |file| file.except(:io).deep_stringify_keys } }
  end

  def optional_id(value)
    value.nil? ? nil : JrcServiceDesk::Input.id(value)
  end

  def validate_conversation!(id)
    @intake_conversation = nil
    return unless id
    raise Pundit::NotAuthorizedError unless context.capability?(:conversations_link)

    conversation = Conversation.where(account_id: context.account.id).find(id)
    authorize!(conversation, :show?) # Includes replay; a saved key is not a grant.
    @intake_conversation = conversation
  end

  def existing_ticket(unit, key, inputs)
    existing = JrcServiceDesk::Ticket.find_by(account_id: context.account.id, unit_id: unit.id,
                                              created_by_membership_id: actor_membership.id, idempotency_key: key)
    return unless existing

    authorize!(existing, :show?)
    marker = existing.ticket_events.find_by(event_type: 'creation_context_recorded')
    unless same_creation_context?(existing, marker, inputs)
      raise JrcServiceDesk::IdempotencyConflict, 'Creation relation differs from original request'
    end

    existing
  end

  def same_creation_context?(ticket, marker, inputs)
    previous = marker&.data&.fetch('conversation_id', nil)
    files = marker&.data&.fetch('file_fingerprints', []) || []
    previous == inputs[:conversation_id] && ticket.service_id == inputs[:service_id] && files == inputs[:file_fingerprints]
  end

  def create_ticket(unit, attributes, key, inputs)
    JrcServiceDesk::CreateTicketService.new(user_context: context.to_h).call(
      unit_id: unit.id, attributes: attributes, idempotency_key: key,
      service_id: inputs[:service_id], origin_channel: inputs[:origin_channel], intake_conversation: @intake_conversation
    )
  end

  def initialize_workflow(ticket, inputs, key)
    conversation_id = inputs[:conversation_id]
    if conversation_id
      JrcServiceDesk::LinkConversationService.new(user_context: context.to_h).call(ticket_id: ticket.id, conversation_id: conversation_id)
    end
    marker = { 'conversation_id' => conversation_id }
    marker['file_fingerprints'] = inputs[:file_fingerprints] if inputs[:files].any?
    append_event!(ticket, 'creation_context_recorded', marker)
    attach_opening_files(ticket, inputs[:files], key) if inputs[:files].any?
    JrcServiceDesk::OlaTracker.sync!(ticket)
    return unless ticket.queue && ticket.queue.distribution_mode != 'manual'

    JrcServiceDesk::AutomaticRoutingService.new(user_context: context.to_h).call(ticket_id: ticket.id)
  end

  def attach_opening_files(ticket, files, key)
    JrcServiceDesk::AddNoteService.new(user_context: context.to_h).call(
      ticket_id: ticket.id, files: files,
      attributes: { body: ticket.description.presence || ticket.title, visibility: 'internal' },
      idempotency_key: "opening:#{Digest::SHA256.hexdigest(key)}"
    )
  end

  def capture_created(result)
    JrcNico::Helpdesk::Capture.call(ticket: result, trigger: 'created', origin_key: "sd:ticket:#{result.id}:created",
                                    member: actor_membership.account_user)
  end
end
