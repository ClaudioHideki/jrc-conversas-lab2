# frozen_string_literal: true

class JrcServiceDesk::PortalCreationService
  def initialize(contact_inbox:, identity_proof:)
    @identity = ContactInbox.find(contact_inbox.id)
    @identity_proof = identity_proof
  end

  def call(attributes:, idempotency_key:, files: [])
    fields = %w[service_id service_revision title description service_fields conversation_id contract_id]
    values = JrcServiceDesk::Input.attributes(attributes, fields)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    uploads = JrcServiceDesk::InteractionAttachments.prepare(files)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(values.merge('files' => uploads.map { |file| file.except(:io).stringify_keys }))
    JrcServiceDesk::Base.transaction do
      scope, service = locked_service(values)
      revision = JrcServiceDesk::ConfigurationResources.revision('services', service)
      raise JrcServiceDesk::IdempotencyConflict unless values.fetch('service_revision') == revision

      context = execution_context(service)
      prior = authorized_replay(scope, service, context, key, fingerprint)
      prior || create_request(service, scope, context, values, { key: key, fingerprint: fingerprint, files: files })
    end
  rescue ActiveRecord::RecordNotUnique
    raise JrcServiceDesk::IdempotencyConflict
  end

  private

  def locked_service(values)
    initial = JrcServiceDesk::PortalScope.new(contact_inbox: @identity, identity_proof: @identity_proof)
    service = initial.services.find(JrcServiceDesk::Input.id(values.fetch('service_id')))
    service.unit.lock!
    @identity.lock!('FOR SHARE')
    scope = JrcServiceDesk::PortalScope.new(contact_inbox: @identity, identity_proof: @identity_proof)
    [scope, scope.services.lock('FOR SHARE OF jrc_service_desk_services').find(service.id)]
  end

  def execution_context(service)
    member = service.portal_execution_membership.account_user
    context = JrcServiceDesk::OperationalContext.new(account: service.account, user: member.user, account_user: member)
    permitted = context.unit_allowed?(service.unit) && %i[tickets_create conversations_link].all? { |name| context.capability?(name) }
    permitted &&= JrcServiceDesk::NativeExecutionContext.with(context.to_h) { InboxPolicy.new(context.to_h, service.portal_inbox).show? }
    raise Pundit::NotAuthorizedError unless permitted

    context
  end

  def authorized_replay(scope, service, context, key, fingerprint)
    prior = JrcServiceDesk::PortalRequest.find_by(account_id: service.account_id, contact_id: @identity.contact_id, request_key: key)
    return unless prior

    revision = JrcServiceDesk::ConfigurationResources.revision('services', service)
    matches = prior.fingerprint == fingerprint && prior.service_id == service.id && prior.service_revision == revision &&
              prior.execution_membership_id == service.portal_execution_membership_id
    raise JrcServiceDesk::IdempotencyConflict unless matches

    scope.tickets.find(prior.ticket_id)
    Pundit.authorize(context.to_h, prior.ticket, :show?)
    Pundit.authorize(context.to_h, prior.conversation, :show?)
    prior
  end

  def create_request(service, scope, context, values, submission)
    conversation = conversation_for(scope, values)
    namespace = "portal:#{@identity.contact_id}:#{Digest::SHA256.hexdigest(submission[:key])}"
    ticket = create_ticket(service, context, conversation, values, namespace)
    message = JrcServiceDesk::PortalCustomerMessage.create!(
      conversation: conversation, contact: @identity.contact, content: values['description'].presence || values.fetch('title'),
      source_id: "jrc-sd-#{namespace}", files: submission[:files], content_attributes: { service_desk_ticket_id: ticket.id.to_s }
    )
    JrcServiceDesk::PortalRequest.create!(
      account: service.account, unit: service.unit, service: service, ticket: ticket, contact: @identity.contact,
      contact_inbox: @identity, inbox: @identity.inbox, execution_membership: service.portal_execution_membership,
      conversation: conversation, message: message, request_key: submission[:key], fingerprint: submission[:fingerprint],
      service_revision: JrcServiceDesk::ConfigurationResources.revision('services', service),
      service_snapshot: JrcServiceDesk::ConfigurationResources.fields('services', service)
    )
  end

  def conversation_for(scope, values)
    return scope.conversations.find(JrcServiceDesk::Input.id(values['conversation_id'])) if values['conversation_id']

    ConversationBuilder.new(params: {}, contact_inbox: @identity).perform
  end

  def create_ticket(service, context, conversation, values, namespace)
    status = JrcServiceDesk::TicketStatus.find_by!(unit_id: service.unit_id, account_id: service.account_id, active: true,
                                                   initial: true, phase: 'open')
    attributes = { title: values.fetch('title'), description: values['description'], requester_id: @identity.contact_id,
                   status_id: status.id, service_fields: values.fetch('service_fields', {}) }
    attributes[:contract_id] = values['contract_id'] if values.key?('contract_id')
    JrcServiceDesk::CreateTicketWorkflowService.new(user_context: context.to_h).call(
      unit_id: service.unit_id, attributes: attributes, conversation_id: conversation.id, service_id: service.id,
      idempotency_key: namespace, origin_channel: 'portal'
    )
  end
end
