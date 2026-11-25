# frozen_string_literal: true

# Identity only; never a CRM/ServiceDesk grant or execution. The existing origin
# already stores these IDs immutably. No inferred telephone match or shadow CRM.
class JrcContactCenter::EndingActions::OriginalCustomerReference
  def initialize(account:, member:, origin:)
    @account = account
    @member = JrcOperations::Access.refresh(member)
    @origin = JrcContactCenter::EndingActionOrigin.where(account: account).find(origin.id)
  end

  def call
    call = JrcContactCenter::EndingActions::SourceAuthority.new(account: @account, member: @member).call(@origin)
    captured = captured_reference!(call)
    context = { account: @account, account_user: @member, user: @member.user }
    data = JrcContactCenter::CustomerContext.new(account: @account, user_context: context).for_call(call)
    contact = authorized_contact!(data, captured)
    { contact_id: captured.fetch('contact_id'), captured_company_id: captured.fetch('company_id'),
      current_company_id: company_identity(contact) }
  end

  private

  def captured_reference!(call)
    captured = @origin.private_origin_evidence.slice('contact_id', 'company_id')
    unless captured['contact_id'].is_a?(Integer) && captured['contact_id'].positive?
      raise JrcContactCenter::OperationError, 'ending_customer_explicit_reference_required'
    end
    unless call.contact_id == captured.fetch('contact_id') && call.company_id == captured.fetch('company_id')
      raise JrcContactCenter::OperationError, 'ending_customer_reference_changed'
    end

    captured
  end

  def authorized_contact!(data, captured)
    unless data[:status] == 'identified' && data[:identity_source] == 'call_contact_link' && data.fetch(:contacts).length == 1
      raise Pundit::NotAuthorizedError
    end

    contact = data.fetch(:contacts).first
    raise Pundit::NotAuthorizedError unless contact.fetch(:id) == captured.fetch('contact_id').to_s

    validate_company!(contact, captured)
    contact
  end

  def validate_company!(contact, captured)
    if captured['company_id'] && company_identity(contact) != captured.fetch('company_id')
      raise JrcContactCenter::OperationError, 'ending_customer_reference_changed'
    end
  end

  def company_identity(contact)
    contact.dig(:company, :id)&.to_i
  end
end
