# frozen_string_literal: true

# Internal adapter only. A future per-destination executor must own the native
# transaction and append its immutable result in that same transaction. This
# service does not activate a rule, dispatch an event or grant CRM access.
class JrcContactCenter::EndingActions::CrmLeadDestination
  def initialize(account:, member:)
    @account = account
    @member = JrcOperations::Access.refresh(member)
  end

  def call(origin:)
    raise JrcContactCenter::OperationError, 'ending_destination_requires_transaction' unless Account.connection.transaction_open?

    # Scope only the native SQL diagnostics of this synchronous command. Native
    # audit rows, warnings and errors remain active; no global filter is changed.
    ActiveRecord::Base.logger.silence(Logger::WARN) { create_for_locked_contact(origin) }
  end

  private

  def customer_reference(origin)
    JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: @account, member: @member, origin: origin).call
  end

  def create_for_locked_contact(origin)
    reference = customer_reference(origin)
    authorize_native_crm!
    @account.contacts.find(reference.fetch(:contact_id)).with_lock do
      # The native customer editor locks the Contact too. Do not use identity
      # authorized before waiting for a concurrent company/contact edit.
      customer_reference(origin)
      authorize_native_crm!
      result = JrcCrm::ContactLeadService.new(account: @account, actor: @member.user, contact_id: reference.fetch(:contact_id)).call(create: true)
      result = result.merge(lead: authorized_native_result!(result.fetch(:lead)))
      unless result.fetch(:lead).company_id == reference.fetch(:current_company_id)
        raise JrcContactCenter::OperationError, 'ending_customer_reference_changed'
      end
      require_native_creation_audit!(result.fetch(:lead)) if result.fetch(:created)
      result
    end
  end

  # The native CRM controller checks module permissions independently of the
  # ContactLeadService flag. A custom role may deny CRM while that flag remains.
  def authorize_native_crm!
    AccountUser.uncached do
      @member = JrcOperations::Access.refresh(@member)
      raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@member)
    end
  end

  # Contact visibility does not grant a CRM record's corporate scope. Preserve
  # the native controller's owner and organizational restrictions, including a
  # newly created Lead without a visible unit. Never guess or assign its unit.
  def authorized_native_result!(lead)
    relation = @account.jrc_crm_leads
    relation = relation.where(owner_id: @member.user_id) unless @member.administrator?
    JrcCrm::OrganizationalVisibility.new(account: @account, user: @member.user, relation: relation).call.find(lead.id)
  end

  # The native logger deliberately rescues persistence errors. An automation may
  # not turn that absence into success or commit an unaudited new Lead.
  def require_native_creation_audit!(lead)
    events = JrcCrm::AuditEvent.where(
      account: @account, resource_type: lead.class.name, resource_id: lead.id,
      event_type: 'lead_created', actor_type: @member.user.class.name, actor_id: @member.user_id
    )
    raise JrcContactCenter::OperationError, 'ending_crm_native_audit_missing' unless events.exists?
  end
end
