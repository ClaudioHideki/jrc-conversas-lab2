class JrcCrm::ContactLeadService
  class AmbiguousContact < StandardError; end

  def initialize(account:, actor:, contact_id:)
    @account = account
    @actor = actor
    @contact_id = contact_id
  end

  def call(create: false)
    authorize_crm!
    contact = @account.contacts.find(@contact_id)
    raise Pundit::NotAuthorizedError unless ContactPolicy.new(@context, contact).show?

    # Serialize retries of this entry point on the existing contact row, backed
    # by the existing unique account/idempotency_key index. No schema change.
    contact.with_lock do
      lead = existing_lead(contact)
      next { lead: lead, created: false } if lead || !create

      { lead: create_lead(contact), created: true }
    end
  end

  private

  def authorize_crm!
    membership = @account.account_users.find_by!(user_id: @actor.id)
    allowed = @account.feature_enabled?('jrc_crm') && (membership.administrator? || membership.crm_enabled?)
    raise Pundit::NotAuthorizedError unless allowed

    @context = { user: @actor, account: @account, account_user: membership }
  end

  def existing_lead(contact)
    leads = @account.jrc_crm_leads.where(contact_id: contact.id).order(:id).limit(2).to_a
    raise ActiveRecord::RecordNotFound if leads.any? { |lead| !JrcCrm::LeadPolicy.new(@context, lead).show? }
    raise AmbiguousContact if leads.size > 1

    leads.first
  end

  def create_lead(contact)
    lead = @account.jrc_crm_leads.new(
      contact: contact, owner: @actor, name: contact.name.presence || "Contato ##{contact.id}",
      email: contact.email, phone: contact.phone_number,
      company_name: contact.additional_attributes.to_h['company_name'],
      source: 'contacts', idempotency_key: "contact:#{contact.id}"
    )
    raise Pundit::NotAuthorizedError unless JrcCrm::LeadPolicy.new(@context, lead).create?

    lead.save!
    JrcCrm::AuditLoggerService.new(
      account: @account, actor: @actor, resource: lead, event_type: 'lead_created',
      from_value: nil, to_value: lead.public_status, metadata: { source: 'contacts', contact_id: contact.id }
    ).call
    lead
  end
end
