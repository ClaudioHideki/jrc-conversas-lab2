# frozen_string_literal: true

class JrcContactCenter::CustomerContext
  def initialize(account:, user_context: nil)
    @account = account
    @user_context = user_context
  end

  def by_phone(phone)
    # SIP identities and short PBX extensions are not customer identifiers.
    return empty_result unless phone.to_s.match?(/\A\+?[\d\s().-]+\z/)

    normalized = phone.to_s.gsub(/\D/, '')
    return empty_result unless normalized.length.between?(8, 15)

    contacts = authorized_contacts.where("regexp_replace(phone_number, '[^0-9]', '', 'g') = ?", normalized).limit(10).to_a
    company_ids = contacts.filter_map(&:company_id).uniq
    companies = @account.master_companies.where(id: company_ids).index_by(&:id)
    {
      contacts: contacts.map { |contact| contact_payload(contact, companies[contact.company_id]) },
      ambiguous: contacts.size > 1
    }
  end

  def for_call(call)
    raise ArgumentError, 'call account mismatch' unless call.account_id == @account.id

    return linked_contact(call.contact_id) if call.contact_id

    result = by_phone(call.direction == 'outbound' ? call.dnis : call.ani)
    result.merge(status: identity_status(result), identity_source: result[:contacts].any? ? 'phone_candidates' : 'unidentified')
  end

  def module_context(user_context:, access:)
    policy = JrcContactCenter::ModulePolicy.new(user_context, :contact_center)
    { feature: 'jrc_contact_center', capabilities: module_capabilities(policy), provider: provider_context, counts: module_counts(access),
      acw_policy: JrcContactCenter::AcwPolicy.new(account: @account).call }
  end

  private

  def authorized_contacts
    raise Pundit::NotAuthorizedError unless @user_context && @user_context.fetch(:account).id == @account.id

    member = @account.account_users.find(@user_context.fetch(:account_user).id)
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: member.user)
    relation = corporate_contacts(coverage)
    return relation if unrestricted_native_member?(member, coverage)

    conversations = Conversations::PermissionFilterService.new(@account.conversations, member.user, @account).perform
    calls = JrcContactCenter::AccessScope.new(user_context: @user_context).call_sessions
    relation.where(id: conversations.select(:contact_id)).or(relation.where(id: calls.select(:contact_id)))
  end

  def corporate_contacts(coverage)
    companies = coverage.companies(@account.master_companies).select(:id)
    @account.contacts.where(company_id: nil).or(@account.contacts.where(company_id: companies))
  end

  def unrestricted_native_member?(member, coverage)
    member.administrator? && member.custom_role_id.nil? && (!coverage.configured? || coverage.group?)
  end

  def linked_contact(id)
    contact = authorized_contacts.find_by(id: id)
    return empty_result.merge(status: 'unavailable', identity_source: 'unavailable') unless contact

    company = @account.master_companies.find_by(id: contact.company_id) if contact.company_id
    { contacts: [contact_payload(contact, company)], ambiguous: false, status: 'identified',
      identity_source: 'call_contact_link', directory: directory_link(contact) }
  end

  # Only an explicit, authorized call/contact link may open the native master.
  # A matching telephone number never becomes a directory permission.
  def directory_link(contact)
    directory = JrcCustomers::ContactDirectory.new(account: @account, actor: @user_context.fetch(:user))
    record = directory.find(contact.id)
    { contact_id: record.id.to_s }
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    nil
  end

  def identity_status(result)
    return 'ambiguous' if result[:ambiguous]

    result[:contacts].any? ? 'identified' : 'unidentified'
  end

  def module_capabilities(policy)
    %w[operate supervise configure reports administer monitor recordings_view recordings_listen recordings_download publish approve audit]
      .index_with { |action| policy.public_send("#{action}?") }.symbolize_keys
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
