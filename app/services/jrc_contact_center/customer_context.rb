# frozen_string_literal: true

class JrcContactCenter::CustomerContext
  def initialize(account:)
    @account = account
  end

  def by_phone(phone)
    normalized = phone.to_s.gsub(/\D/, '')
    return empty_result if normalized.blank?

    contacts = @account.contacts.where("regexp_replace(phone_number, '[^0-9]', '', 'g') = ?", normalized).limit(10).to_a
    company_ids = contacts.filter_map(&:company_id).uniq
    companies = @account.master_companies.where(id: company_ids).index_by(&:id)
    {
      contacts: contacts.map { |contact| contact_payload(contact, companies[contact.company_id]) },
      ambiguous: contacts.size > 1
    }
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
