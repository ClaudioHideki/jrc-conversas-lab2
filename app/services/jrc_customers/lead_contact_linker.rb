class JrcCustomers::LeadContactLinker
  class Conflict < StandardError; end

  def initialize(account:)
    @account = account
  end

  def call(lead, persist: true)
    raise Conflict, 'Lead belongs to another account' unless lead.account_id == @account.id
    return @account.contacts.find(lead.contact_id) if lead.contact_id.present?

    candidates = JrcCustomers::IdentityResolver.new(account: @account).call(email: lead.email, phone: lead.phone, country: 'BR').to_a
    raise Conflict, 'Email/phone match more than one contact; choose contact_id explicitly' if candidates.length > 1
    return candidates.first if candidates.one?

    phone = JrcCustomers::Identity.phone(lead.phone, country: 'BR')
    raise Conflict, 'Use a telephone with country code' if lead.phone.present? && phone.nil?

    contact = @account.contacts.build(name: lead.name, email: JrcCustomers::Identity.email(lead.email), phone_number: phone,
                                      contact_type: 'lead', registration_status: 'registered')
    contact.save! if persist
    contact
  end
end
