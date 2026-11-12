# The temporary single-company link stays on Contact. Reuse its native lock,
# coverage, validation and audit; switching a primary never changes the person.
class JrcCustomers::CompanyContactWriter
  FIELDS = %i[name email phone_number company_id job_title department registration_status company_role company_primary company_contact_status
              identifier custom_attributes additional_attributes label_list].freeze

  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
    @serializer = JrcCustomers::Serializer.new(account: account)
  end

  def update!(id:, attributes:, confirm_reassignment: false, confirm_primary_change: false, imported: false)
    JrcCustomers::ImportAccess.new(account: @account, actor: @actor).authorize!(kind: 'contacts') if imported
    @directory.with_locked_contact(id) do |contact|
      target = imported ? contact.becomes(JrcCustomers::ImportContact) : contact
      result = update_contact!(target, attributes, confirm_reassignment, confirm_primary_change)
      imported ? result.becomes(Contact) : result
    end
  end

  def create_imported!(attributes:, confirm_primary_change: false)
    @account.with_lock do
      JrcCustomers::ImportAccess.new(account: @account, actor: @actor).authorize!(kind: 'contacts')
      contact = JrcCustomers::ImportContact.new(account: @account, registration_status: 'registered')
      values = attributes.to_h.symbolize_keys.slice(*FIELDS)
      authorize_transfer!(contact, values, false, false)
      contact.assign_attributes(values)
      raise ActiveRecord::RecordInvalid, contact unless contact.valid?

      replace_primary!(contact, confirm_primary_change) if contact.company_primary?
      contact.save!
      native_contact = contact.becomes(Contact)
      audit!(native_contact, 'customer_contact_updated', {})
      native_contact
    end
  end

  private

  def update_contact!(contact, attributes, confirm_reassignment, confirm_primary_change)
    previous = @serializer.contact(contact)
    values = attributes.to_h.symbolize_keys.slice(*FIELDS)
    transferring = values.key?(:company_id) && values[:company_id].to_s != contact.company_id.to_s
    authorize_transfer!(contact, values, transferring, confirm_reassignment)
    contact.assign_attributes(values)
    raise ActiveRecord::RecordInvalid, contact unless contact.valid?

    replace_primary!(contact, confirm_primary_change) if contact.company_primary?
    contact.save!
    audit!(contact, event_type(contact, previous, values, transferring), previous)
    contact
  end

  def authorize_transfer!(contact, values, transferring, confirmed)
    if transferring && contact.company_id.present? && !confirmed
      raise JrcCustomers::MergePreserver::Conflict, 'Confirm reassignment; the current company and its historical context will change'
    end

    company = @account.master_companies.find_by(id: values[:company_id]) if values[:company_id].present?
    return unless company

    JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies).find(company.id)
  end

  def event_type(contact, previous, values, transferring)
    return 'customer_contact_linked' if transferring
    return 'customer_contact_primary_changed' if previous['company_primary'] != contact.company_primary?

    changed = JrcCustomers::ContactMaster::COMPANY_CONTEXT_FIELDS.any? { |field| previous[field] != contact.public_send(field) }
    return 'customer_contact_context_changed' if changed

    values.key?(:company_id) ? 'customer_contact_linked' : 'customer_contact_updated'
  end

  def replace_primary!(contact, confirmed)
    previous = @directory.scope.where(company_id: contact.company_id, company_primary: true).where.not(id: contact.id).lock.first
    return unless previous
    raise JrcCustomers::MergePreserver::Conflict, 'Confirm replacement of the current primary contact' unless confirmed

    snapshot = @serializer.contact(previous)
    previous.update!(company_primary: false)
    audit!(previous, 'customer_contact_primary_changed', snapshot)
  end

  def audit!(contact, event, previous)
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: contact.becomes(Contact), event_type: event,
                                from_value: previous, to_value: @serializer.contact(contact))
  end
end
