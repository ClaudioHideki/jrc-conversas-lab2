# frozen_string_literal: true

class JrcContactCenter::CustomerContext
  def initialize(account:)
    @account = account
  end

  def by_phone(phone)
    # SIP identities and short PBX extensions are not customer identifiers.
    return empty_result unless phone.to_s.match?(/\A\+?[\d\s().-]+\z/)

    normalized = phone.to_s.gsub(/\D/, '')
    return empty_result unless normalized.length.between?(8, 15)

    contacts = @account.contacts.where("regexp_replace(phone_number, '[^0-9]', '', 'g') = ?", normalized).limit(10).to_a
    company_ids = contacts.filter_map(&:company_id).uniq
    companies = @account.master_companies.where(id: company_ids).index_by(&:id)
    {
      contacts: contacts.map { |contact| contact_payload(contact, companies[contact.company_id]) },
      ambiguous: contacts.size > 1
    }
  end

  def for_call(call)
    raise ArgumentError, 'call account mismatch' unless call.account_id == @account.id

    if call.contact_id
      contact = @account.contacts.find_by(id: call.contact_id)
      return empty_result.merge(status: 'unavailable') unless contact

      company = @account.master_companies.find_by(id: contact.company_id) if contact.company_id
      return { contacts: [contact_payload(contact, company)], ambiguous: false, status: 'identified' }
    end

    result = by_phone(call.direction == 'outbound' ? call.dnis : call.ani)
    result.merge(status: result[:ambiguous] ? 'ambiguous' : (result[:contacts].any? ? 'identified' : 'unidentified'))
  end

  def module_context(user_context:, access:)
    policy = JrcContactCenter::ModulePolicy.new(user_context, :contact_center)
    { feature: 'jrc_contact_center', capabilities: module_capabilities(policy), provider: provider_context, counts: module_counts(access),
      acw_policy: JrcContactCenter::AcwPolicy.new(account: @account).call }
  end

  private

  def module_capabilities(policy)
    { operate: policy.operate?, supervise: policy.supervise?, configure: policy.configure?, reports: policy.reports? }
  end

  def provider_context
    adapter = JrcContactCenter::Providers::JrcPabxAdapter.new(account: @account)
    { key: adapter.provider_key, capabilities: adapter.capabilities }
  end

  def module_counts(access)
    {
      units: access.units.count,
      queues: access.queues.count,
      active_calls: access.call_sessions.where.not(status: %w[ended failed]).count,
      open_cases: access.cases.where(status: %w[open in_progress waiting]).count,
      pending_callbacks: access.callbacks.where(state: %w[scheduled in_progress]).count
    }
  end

  def empty_result
    { contacts: [], ambiguous: false }
  end

  def contact_payload(contact, company)
    {
      id: contact.id.to_s,
      name: contact.name,
      phone_number: contact.phone_number,
      company: company && { id: company.id.to_s, name: company.name, customer_code: company.customer_code }
    }
  end
end
