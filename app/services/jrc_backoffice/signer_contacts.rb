# A small, paginated view of the existing master contacts for one contract
# party. Caller-provided company/unit/user IDs never choose its scope.
class JrcBackoffice::SignerContacts
  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
    @request_id = request_id
  end

  def call(party:, query: nil, page: 1)
    raise ArgumentError, 'Selecione Cliente ou Emitente.' unless JrcBackoffice::SignerSelection::PARTIES.include?(party)

    contract, source = signing_context!
    company = source.parties.fetch(party)
    digest = JrcBackoffice::ContractSnapshot.digest(contract)
    rows = search(@directory.scope.where(company_id: company.id), query)
    payload = contact_page(rows, page).merge(party: party, company: company.attributes.slice('id', 'name'))
    @directory.authorize!
    fresh = @access.contract!(@access.request(@request_id))
    raise JrcBackoffice::SignerRosters::Changed unless digest == JrcBackoffice::ContractSnapshot.digest(fresh)

    payload
  end

  private

  def signing_context!
    request = @access.writable!(@access.request(@request_id))
    contract = @access.contract!(request)
    raise ArgumentError, 'Os assinantes do contrato enviado ou assinado foram preservados.' if contract.signature_status.in?(%w[sent signed])

    source = JrcBackoffice::SignerRosterSource.new(account: @access.account, actor: @access.actor, request: request, contract: contract)
    [contract, source]
  end

  def search(rows, query)
    raise ArgumentError, 'Use uma pesquisa de até 120 caracteres.' unless query.nil? || (query.is_a?(String) && query.length <= 120)

    term = query.to_s.strip
    return rows if term.empty?

    rows.where('contacts.name ILIKE :q OR contacts.email ILIKE :q', q: "%#{Contact.sanitize_sql_like(term)}%")
  end

  def contact_page(scope, page)
    total = scope.count
    pages = [(total / 10.0).ceil, 1].max
    current_page = page.to_s.to_i.clamp(1, pages)
    rows = scope.order(:name, :id).offset((current_page - 1) * 10).limit(10).to_a
    identities = JrcCustomers::SigningIdentity.where(account_id: @access.account.id, contact_id: rows.map(&:id)).index_by(&:contact_id)
    { data: rows.map { |contact| serialize(contact, identities[contact.id]) },
      meta: { page: current_page, per_page: 10, total: total, pages: pages } }
  end

  def serialize(contact, identity)
    available = !contact.blocked? && contact.name.present? && JrcCustomers::Identity.email(contact.email).present? && identity &&
                JrcCustomers::TaxIdentifier.cpf_valid?(identity.personal_tax_identifier)
    { id: contact.id, name: contact.name, email: contact.email, personal_tax_identifier_masked: identity&.masked_identifier,
      identity_registered: identity.present?, selectable: available.present?, signing_authority_verified: false }
  end
end
