require 'openssl'

# Canonical contact identity only. Selecting single/joint proposes a roster;
# documentary powers and the Central's decision are separate prerequisites.
class JrcBackoffice::SignerRosterSource
  COMPANY_FIELDS = %w[id name legal_name trade_name tax_id person_kind].freeze
  def initialize(account:, actor:, request:, contract:)
    @account = account
    @actor = actor
    @request = request
    @contract = contract
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
  end

  def parties
    unit = issuer_unit!
    customer = @account.master_companies.find(@contract.contact&.company_id)
    issuer = @account.master_companies.find(unit.company_id)
    active = customer.active? && issuer.active? && issuer.relationship_type == 'internal'
    raise ArgumentError, 'Selecione empresas ativas do Cadastro Mestre.' unless active
    raise ArgumentError, 'Cliente e emitente devem ser empresas distintas.' if customer.id == issuer.id

    { 'customer' => customer, 'issuer' => issuer }
  end

  def capture(selections:, customer_mode:, issuer_mode:)
    modes = { 'customer' => customer_mode, 'issuer' => issuer_mode }
    rows = JrcBackoffice::SignerSelection.call(selections, modes)
    companies = parties
    people = source_people(rows, companies)
    { 'format_version' => 1, 'account_id' => @account.id, 'contract_id' => @contract.id, 'backoffice_request_id' => @request.id,
      'business_unit_id' => @contract.business_unit_id, 'customer_mode' => customer_mode, 'issuer_mode' => issuer_mode,
      'customer' => companies.fetch('customer').attributes.slice(*COMPANY_FIELDS),
      'issuer' => companies.fetch('issuer').attributes.slice(*COMPANY_FIELDS), 'signers' => people }
  end

  def assert_current!(roster)
    original = roster.snapshot
    current = capture(selections: original.fetch('signers'), customer_mode: roster.customer_mode, issuer_mode: roster.issuer_mode)
    current.fetch('signers').each_with_index do |person, index|
      person.merge!(original.fetch('signers')[index].slice('key', 'anchor'))
    end
    return if self.class.digest(current) == roster.source_digest

    raise ArgumentError, 'Os dados dos assinantes mudaram. Revise a proposta de assinantes antes de gerar a versão.'
  end

  def self.digest(data)
    # A plain public checksum of known identity fields could be brute-forced.
    key = Rails.application.key_generator.generate_key('jrc-contract-signer-roster-v1', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, JrcServiceDesk::CanonicalJson.dump(data))
  end

  private

  def issuer_unit!
    @directory.authorize!
    unit = @contract.business_unit
    valid = unit && unit.id == @request.business_unit_id && unit.id == @contract.sales_order.business_unit_id
    raise ArgumentError, 'Configure a unidade e a empresa emitente do contrato.' unless valid

    JrcCrm::CorporateIssuer.authorize_resource!(@contract, @actor)
    unit
  end

  def source_people(rows, companies)
    contacts = @directory.scope.where(id: rows.pluck('contact_id')).order(:id).lock('FOR SHARE').index_by(&:id)
    raise ActiveRecord::RecordNotFound unless contacts.length == rows.length

    identities = JrcCustomers::SigningIdentity.where(account_id: @account.id, contact_id: contacts.keys)
                                              .order(:contact_id).lock('FOR SHARE').index_by(&:contact_id)
    rows.each_with_index.map { |row, index| signer(row, contacts.fetch(row['contact_id']), identities, companies, index + 1) }
  end

  def signer(row, contact, identities, companies, position)
    company = companies.fetch(row['party'])
    raise ActiveRecord::RecordNotFound unless contact.company_id == company.id

    email = JrcCustomers::Identity.email(contact.email)
    raise ArgumentError, 'Complete nome e e-mail válido do assinante no Cadastro Mestre.' if contact.name.blank? || email.nil? || contact.blocked?

    identity = verified_identity!(contact, identities)
    key = SecureRandom.uuid
    { 'key' => key, 'position' => position, 'party' => row['party'], 'contact_id' => contact.id, 'company_id' => company.id,
      'name' => contact.name, 'email' => email, 'required' => true, 'anchor' => "JRC_SIGN_#{key.delete('-')}" }.merge(identity_fields(identity))
  end

  def verified_identity!(contact, identities)
    identity = identities[contact.id]
    raise ArgumentError, 'Cadastre o CPF protegido do assinante no Cadastro Mestre.' unless identity
    raise ArgumentError, 'Confira o CPF protegido do assinante.' unless JrcCustomers::TaxIdentifier.cpf_valid?(identity.personal_tax_identifier)

    identity
  end

  def identity_fields(identity)
    { 'identity_id' => identity.id, 'identity_revision' => identity.revision,
      'personal_tax_identifier' => identity.personal_tax_identifier, 'personal_tax_identifier_masked' => identity.masked_identifier }
  end
end
