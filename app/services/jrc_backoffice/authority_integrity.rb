# Fresh comparison of the exact proposed people and legal source. Callers first
# authorize the version or its native Central case. Existing corporate coverage
# bounds these reads; no directory listing or CPF editing capability is granted.
class JrcBackoffice::AuthorityIntegrity
  def initialize(version:, actor:)
    @version = version
    @actor = actor
    @account = version.account
    @coverage = JrcCrm::CorporateCoverage.new(account: @account, user: actor)
  end

  def call
    roster = @version.signer_roster
    source = roster.snapshot
    request = @version.backoffice_request.reload
    contract = @version.contract.reload
    { version_current: request.contract_id == contract.id && latest_version(contract)&.id == @version.id,
      roster_current: latest_roster(request, contract)&.id == roster.id,
      source_current: JrcBackoffice::ContractSnapshot.digest(contract, signer_roster: roster) == @version.source_digest,
      parties_current: parties_current?(source, request, contract), people_current: people_current?(source),
      party_identifiers_configured: party_identifiers_configured?(source) }
  end

  private

  def latest_version(contract)
    JrcBackoffice::ContractVersion.where(account_id: @account.id, contract_id: contract.id).order(number: :desc).first
  end

  def latest_roster(request, contract)
    JrcBackoffice::SignerRoster.where(account_id: @account.id, contract_id: contract.id,
                                      backoffice_request_id: request.id).order(revision: :desc).first
  end

  def party_identifiers_configured?(source)
    %w[customer issuer].all? do |party|
      company = source.fetch(party)
      identifier = JrcCustomers::TaxIdentifier.normalize(company['tax_id'])
      identifier.present? && JrcCustomers::TaxIdentifier.valid?(identifier, person_kind: company.fetch('person_kind'))
    end
  end

  def parties_current?(source, request, contract)
    unit_id = source.fetch('business_unit_id')
    return false unless [request.business_unit_id, contract.business_unit_id, contract.sales_order.business_unit_id].all?(unit_id)
    return false unless @coverage.unit_allowed?(unit_id)

    companies = @coverage.companies(@account.master_companies)
    %w[customer issuer].all? do |party|
      expected = source.fetch(party)
      current = companies.find_by(id: expected.fetch('id'))
      current&.active? && current.attributes.slice(*JrcBackoffice::SignerRosterSource::COMPANY_FIELDS) == expected
    end
  end

  def people_current?(source)
    proposed = source.fetch('signers')
    ids = proposed.pluck('contact_id')
    contacts = JrcCustomers::ContactDirectory.covered_scope(account: @account, actor: @actor).where(id: ids).index_by(&:id)
    # Only immutable identity references/revisions are read for comparison. The
    # protected CPF value is not read from the directory or emitted in the DTO.
    identities = JrcCustomers::SigningIdentity.where(account_id: @account.id, contact_id: ids)
                                              .pluck(:contact_id, :id, :revision).to_h { |contact_id, id, revision| [contact_id, [id, revision]] }
    proposed.all? { |person| same_person?(person, contacts[person.fetch('contact_id')], identities) }
  end

  def same_person?(person, contact, identities)
    return false unless contact && !contact.blocked?

    actual = [contact.company_id, contact.name, JrcCustomers::Identity.email(contact.email), identities[contact.id]]
    expected = [person.fetch('company_id'), person.fetch('name'), person.fetch('email'),
                [person.fetch('identity_id'), person.fetch('identity_revision')]]
    actual == expected
  end
end
