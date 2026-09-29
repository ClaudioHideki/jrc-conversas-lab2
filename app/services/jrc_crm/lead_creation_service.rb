class JrcCrm::LeadCreationService
  def initialize(account:, actor:, attributes:)
    @account = account
    @actor = actor
    @attributes = attributes.to_h.symbolize_keys
  end

  def call
    # Serialize manual creation, including the case where no Contact exists yet.
    # Contact and Lead roll back if either record fails validation.
    @account.with_lock do
      contact = resolve_contact
      yield contact if block_given?
      contact.save! if contact.new_record?
      existing = @account.jrc_crm_leads.where(contact_id: contact.id).order(updated_at: :desc, id: :desc).first
      next { lead: existing, created: false } if existing

      lead = @account.jrc_crm_leads.new(@attributes.except(:identifier, :contact_id))
      lead.contact = contact
      lead.owner ||= @actor
      lead.save!
      JrcCrm::AuditLoggerService.new(
        account: @account, event_type: 'lead_created', actor: @actor, resource: lead,
        from_value: nil, to_value: lead.public_status, metadata: { source: 'contacts', contact_id: contact.id }
      ).call
      { lead: lead, created: true }
    end
  end

  private

  def resolve_contact
    # An explicit Contact ID must never fall back to creating another Contact.
    return @account.contacts.find(@attributes[:contact_id]) if @attributes[:contact_id].present?

    params = contact_identity
    matches = find_contacts(params)
    contact = matches.first || @account.contacts.new(
      params.merge(name: @attributes[:name], contact_type: :lead,
                   additional_attributes: { company_name: @attributes[:company_name] }.compact)
    )
    validate_identity!(contact, params, matches)
    contact
  end

  def contact_identity
    params = {
      identifier: @attributes[:identifier].presence,
      email: @attributes[:email].to_s.strip.downcase.presence,
      phone_number: JrcCampaigns::PhoneNormalizer.call(@attributes[:phone]).presence
    }
    @attributes[:email] = params[:email]
    @attributes[:phone] = params[:phone_number]
    params
  end

  def find_contacts(params)
    # Reuse the identity lookups used by contact imports without overwriting an
    # existing person's data with the commercial form's snapshot.
    manager = DataImport::ContactManager.new(@account)
    [manager.find_contact_by_identifier(params), manager.find_contact_by_email(params),
     manager.find_contact_by_phone_number(params)].compact.uniq(&:id)
  end

  def validate_identity!(contact, params, matches)
    if matches.size > 1
      contact.errors.add(:base, 'E-mail, telefone ou identificador pertencem a contatos diferentes. Selecione o contato correto na Central.')
      raise ActiveRecord::RecordInvalid, contact
    end
    return unless params.values.all?(&:blank?)

    contact.errors.add(:base, 'Informe e-mail ou telefone com código do país para identificar o contato.')
    raise ActiveRecord::RecordInvalid, contact
  end
end
