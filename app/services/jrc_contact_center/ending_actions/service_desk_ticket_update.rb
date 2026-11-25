# frozen_string_literal: true

# Internal native command only. The future caller owns the original-actor
# transaction and independent CC receipt; this does not activate or dispatch.
class JrcContactCenter::EndingActions::ServiceDeskTicketUpdate
  def initialize(account:, member:)
    @account = account
    @member = JrcOperations::Access.refresh(member)
  end

  def call(origin:, parameters:)
    raise JrcContactCenter::OperationError, 'ending_destination_requires_transaction' unless Account.connection.transaction_open?

    original = JrcContactCenter::EndingActionOrigin.where(account: @account).find(origin.id)
    input = JrcContactCenter::EndingActions::ServiceDeskUpdateDefinition.new.call(parameters)
    ActiveRecord::Base.logger.silence(Logger::WARN) { update_original_customer_ticket(original, input) }
  end

  private

  def customer_reference(origin)
    JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: @account, member: @member, origin: origin).call
  end

  def update_original_customer_ticket(origin, input)
    reference = customer_reference(origin)
    @account.contacts.find(reference.fetch(:contact_id)).with_lock do
      reference = customer_reference(origin)
      context = JrcServiceDesk::OperationalContext.new(account: @account, account_user: @member, user: @member.user)
      ticket = JrcServiceDesk::FindTicketService.new(user_context: context.to_h).call(ticket_id: input.fetch('ticket_id'))
      ticket.with_lock do
        authorize_mapping!(context, origin, ticket)
        verify_customer!(ticket, reference)
        apply_native_update(context, ticket, input, reference)
      end
    end
  end

  def authorize_mapping!(context, origin, ticket)
    allowed = context.native_operator? && context.capability?(:customers_view) && context.operational_unit_allowed?(ticket.unit)
    raise Pundit::NotAuthorizedError unless allowed
    raise JrcContactCenter::OperationError, 'ending_service_desk_mapping_required' unless origin.business_unit_id

    business = @account.jrc_crm_business_units.where(active: true).lock('FOR SHARE').find(origin.business_unit_id)
    linked = JrcServiceDesk::Input.id(business.settings.fetch('service_desk_unit_id'))
    return if business.company_id == origin.issuer_company_id && linked == ticket.unit_id

    raise JrcContactCenter::OperationError.new('ending_service_desk_mapping_changed', status: :conflict)
  rescue KeyError, ArgumentError
    raise JrcContactCenter::OperationError, 'ending_service_desk_mapping_required'
  end

  def verify_customer!(ticket, reference)
    actual = [ticket.account_id, ticket.requester_id, ticket.company_id]
    expected = [@account.id, reference.fetch(:contact_id), reference.fetch(:current_company_id)]
    raise JrcContactCenter::OperationError, 'ending_service_desk_customer_link_changed' unless actual == expected
  end

  def apply_native_update(context, ticket, input, reference)
    before = ticket.lock_version
    last_event = ticket.ticket_events.where(event_type: 'ticket_updated').maximum(:id).to_i
    result = JrcServiceDesk::UpdateTicketService.new(user_context: context.to_h).call(
      ticket_id: ticket.id, attributes: input.fetch('attributes'), expected_lock_version: input.fetch('expected_lock_version')
    )
    verify_customer!(result, reference)
    changed = result.lock_version != before
    verify_native_event!(context, result, last_event) if changed
    { ticket: result, changed: changed }
  end

  def verify_native_event!(context, ticket, last_event)
    actors = JrcServiceDesk::UnitMembership.where(account: @account, unit_id: ticket.unit_id, account_user_id: context.account_user.id)
    events = ticket.ticket_events.where(account: @account, event_type: 'ticket_updated', actor_membership_id: actors.select(:id))
    return if events.where('id > ?', last_event).exists?

    raise JrcContactCenter::OperationError, 'ending_service_desk_native_audit_missing'
  end
end
