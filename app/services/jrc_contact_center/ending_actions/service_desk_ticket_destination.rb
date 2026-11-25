# frozen_string_literal: true

# Private adapter preparation. No rule kind, route, dispatcher or provider is
# activated. The future independent destination executor must own the account
# transaction and commit its immutable attempt/result with the native Ticket.
class JrcContactCenter::EndingActions::ServiceDeskTicketDestination
  def initialize(account:, member:)
    @account = account
    @member = JrcOperations::Access.refresh(member)
  end

  def call(origin:, parameters:, request_key:)
    unless Account.connection.transaction_open?
      raise JrcContactCenter::OperationError, 'ending_destination_requires_transaction'
    end

    original = JrcContactCenter::EndingActionOrigin.where(account: @account).find(origin.id)
    input = JrcContactCenter::EndingActions::ServiceDeskDestinationDefinition.new.call(parameters)
    key = JrcServiceDesk::Input.request_key(request_key)
    ActiveRecord::Base.logger.silence(Logger::WARN) { create_for_locked_contact(original, input, key) }
  end

  private

  def customer_reference(origin)
    JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: @account, member: @member, origin: origin).call
  end

  def create_for_locked_contact(origin, input, key)
    reference = customer_reference(origin)
    @account.contacts.find(reference.fetch(:contact_id)).with_lock do
      reference = customer_reference(origin)
      context = JrcServiceDesk::OperationalContext.new(account: @account, account_user: @member, user: @member.user)
      unit = authorized_unit!(context, origin, input.fetch('unit_id'))
      ticket = JrcServiceDesk::CreateTicketWorkflowService.new(user_context: context.to_h).call(
        unit_id: unit.id, attributes: ticket_attributes(input, reference), idempotency_key: key,
        service_id: input.fetch('service_id'), origin_channel: 'manual'
      )
      verify_native_result!(ticket, unit, reference)
      ticket
    end
  end

  def authorized_unit!(context, origin, identifier)
    unit = context.unit_scope.find(identifier)
    permitted = context.native_operator? && context.capability?(:tickets_create) && context.capability?(:customers_view) &&
                context.operational_unit_allowed?(unit)
    raise Pundit::NotAuthorizedError unless permitted

    authorize_native_mapping!(origin, unit)
    unit
  end

  def authorize_native_mapping!(origin, unit)
    raise JrcContactCenter::OperationError, 'ending_service_desk_mapping_required' unless origin.business_unit_id

    business = @account.jrc_crm_business_units.where(active: true).lock('FOR SHARE').find(origin.business_unit_id)
    linked = business.settings.fetch('service_desk_unit_id', nil)
    unless business.company_id == origin.issuer_company_id && JrcServiceDesk::Input.id(linked) == unit.id
      raise JrcContactCenter::OperationError.new('ending_service_desk_mapping_changed', status: :conflict)
    end
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'ending_service_desk_mapping_required'
  end

  def ticket_attributes(input, reference)
    attributes = input.fetch('attributes').deep_dup.merge('requester_id' => reference.fetch(:contact_id))
    company = reference.fetch(:current_company_id)
    if company
      raise JrcContactCenter::OperationError, 'ending_customer_master_required' unless @account.feature_enabled?('jrc_customer_master')

      attributes['company_id'] = company
    end
    attributes
  end

  def verify_native_result!(ticket, unit, reference)
    actual = [ticket.account_id, ticket.unit_id, ticket.requester_id, ticket.company_id]
    expected = [@account.id, unit.id, reference.fetch(:contact_id), reference.fetch(:current_company_id)]
    raise JrcContactCenter::OperationError, 'ending_service_desk_native_identity_mismatch' unless actual == expected

    verify_native_events!(ticket)
  end

  def verify_native_events!(ticket)
    events = ticket.ticket_events.where(account: @account, actor_membership_id: ticket.created_by_membership_id)
    actor = ticket.created_by_membership
    unless actor.account_user_id == @member.id && events.where(event_type: 'ticket_created').exists? &&
           events.where(event_type: 'creation_context_recorded').exists?
      raise JrcContactCenter::OperationError, 'ending_service_desk_native_audit_missing'
    end
  end
end
