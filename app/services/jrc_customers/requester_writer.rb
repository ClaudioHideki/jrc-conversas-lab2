# frozen_string_literal: true

# Writes canonical Contacts and the existing master audit. The current master
# supports one company per Contact: linking must never silently reassign it.
class JrcCustomers::RequesterWriter
  class ReviewRequired < StandardError; end
  class Duplicate < StandardError
    attr_reader :records, :allow_distinct

    def initialize(records, allow_distinct: false)
      @records = records
      @allow_distinct = allow_distinct
      super('Review existing contacts before registering a person')
    end
  end

  def initialize(account:, actor:)
    @account, @actor = account, actor
    @serializer = JrcCustomers::Serializer.new(account: account)
  end

  def create!(company:, attributes:, request_key:, confirm_distinct: false)
    values = attributes.stringify_keys.slice('name', 'email', 'phone_number')
    raise ArgumentError, 'Text fields required' unless values.values.all? { |value| value.nil? || value.is_a?(String) }
    raise ArgumentError, 'Person name required' if values['name'].blank? || values['name'].length > 255
    values['name'] = values['name'].to_s.strip
    values['email'] = JrcCustomers::Identity.email(values['email']) || values['email'] if values['email'].present?
    values['phone_number'] = JrcCustomers::Identity.phone(values['phone_number'], country: 'BR') || values['phone_number'] if values['phone_number'].present?
    values = values.transform_values { |value| value.presence }
    fingerprint = Digest::SHA256.hexdigest(JSON.generate(values.sort.to_h.merge('company_id' => company.id)))
    Contact.transaction do
      # Serialize retries across units/processes without a new registry/table.
      lock_id = Digest::SHA256.hexdigest("sd-requester:#{@account.id}:#{@actor.id}:#{request_key}").first(15).to_i(16)
      Contact.connection.execute("SELECT pg_advisory_xact_lock(#{lock_id})")
      previous = JrcCrm::AuditEvent.where(account_id: @account.id, actor_type: 'User', actor_id: @actor.id,
                                         event_type: 'customer_contact_updated', resource_type: 'Contact')
        .where("metadata ->> 'requester_request_key' = ?", request_key).first
      if previous
        raise ReviewRequired, 'Request key already used for different data' unless previous.metadata['requester_fingerprint'] == fingerprint

        next @account.contacts.find(previous.resource_id)
      end
      identities = JrcCustomers::IdentityResolver.new(account: @account).call(email: values['email'], phone: values['phone_number'], country: 'BR').to_a
      raise Duplicate.new(identities) if identities.any?

      names = @account.contacts.where('lower(trim(name)) = ?', values['name'].to_s.downcase).limit(50).to_a
      raise Duplicate.new(names, allow_distinct: true) if names.any? && !confirm_distinct

      contact = @account.contacts.create!(values.merge(company_id: company.id, registration_status: 'registered',
                                                       additional_attributes: { 'entity_type' => 'person' }))
      JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: contact, event_type: 'customer_contact_updated',
                                  to_value: @serializer.contact(contact),
                                  metadata: { requester_request_key: request_key, requester_fingerprint: fingerprint, source: 'service_desk' })
      contact
    end
  end

  def link!(contact:, company:)
    contact.with_lock do
      raise ReviewRequired, 'Imported or organization contact requires review' if JrcCustomers::RequesterIdentity.reason(contact)
      raise ReviewRequired, 'Person already belongs to another company; review the existing link' if contact.company_id && contact.company_id != company.id
      next contact if contact.company_id == company.id

      previous = @serializer.contact(contact)
      contact.update!(company_id: company.id)
      JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: contact, event_type: 'customer_contact_linked',
                                  from_value: previous, to_value: @serializer.contact(contact), metadata: { source: 'service_desk' })
      contact
    end
  end
end
