class JrcCustomers::ImportContactPlan
  attr_reader :rows, :errors

  def initialize(account:, actor:, existing:, confirmations:)
    @account = account
    @actor = actor
    @existing = existing
    @confirmations = confirmations
    @rows = []
    @errors = []
    @seen = {}
    @primaries = {}
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
    @identity = JrcCustomers::ImportContactIdentity.new(account: account, actor: actor)
  end

  def call(mapped, companies:)
    mapped.each { |source| inspect_row(source, companies.targets[source.fetch(:line)]) }
    self
  end

  private

  def inspect_row(source, company)
    return if source.fetch(:contact).values.all?(&:blank?)

    attributes = JrcCustomers::ImportContactAttributes.new(account: @account, source: source.fetch(:contact))
    contact = @identity.find(attributes)
    check_repeated!(contact, attributes, source.fetch(:line))
    return append_skipped!(source, contact) if contact.persisted? && @existing == 'skip'

    append_validated!(source, contact, attributes, company)
  rescue JrcCustomers::ImportIssue => e
    @errors << { line: source.fetch(:line), entity: 'contact', field: e.field, code: e.code, message: e.message }
  rescue ActiveRecord::RecordNotFound
    @errors << { line: source.fetch(:line), entity: 'contact', field: 'id', code: 'UNAVAILABLE_CONTACT', message: 'Contact or company unavailable' }
  end

  def append_skipped!(source, contact)
    @rows << { line: source.fetch(:line), entity: 'contact', action: 'skip', record_id: contact.id, revision: contact.updated_at.iso8601(6),
               attributes: {}, warnings: ['EXISTING_CONTACT'] }
  end

  def append_validated!(source, contact, attributes, company)
    attributes.validate!
    line = source.fetch(:line)
    revision = contact.updated_at&.iso8601(6)
    identity_revision = persisted_identity_revision(contact)
    values = attributes.values.except('id')
    assign_company!(contact, values, company)
    contact.assign_attributes(values)
    validate_contact!(contact, attributes)
    confirm_reassignment!(contact)
    confirm_primary!(contact)
    check_primary!(contact, line)
    @rows << { line: line, entity: 'contact', action: contact.persisted? ? 'update' : 'create', record_id: contact.id,
               revision: revision, attributes: values.keys.index_with { |field| contact.public_send(field) },
               personal_identifier: attributes.personal_identifier, labels: attributes.labels,
               identity_revision: identity_revision, company_line: company ? line : nil,
               warnings: contact.persisted? ? ['EXISTING_CONTACT'] : [] }
  end

  def assign_company!(contact, values, company)
    if company
      if values['company_id'] && values['company_id'] != company.id
        raise JrcCustomers::ImportIssue.new('Company columns and company_id conflict', field: 'company_id')
      end

      values['company_id'] = company.id
      contact.master_company = company
    elsif values['company_id']
      visible = JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies)
      visible.find(values['company_id'])
    end
  end

  def validate_contact!(contact, attributes)
    unless contact.valid?
      field = contact.errors.attribute_names.first.to_s
      raise JrcCustomers::ImportIssue.new(contact.errors.full_messages.join('; '), field: field)
    end
    return unless attributes.personal_identifier

    identity = contact.signing_identity || JrcCustomers::SigningIdentity.new(account: @account, contact: contact, created_by: @actor)
    identity.personal_tax_identifier = attributes.personal_identifier
    return if identity.valid?

    raise JrcCustomers::ImportIssue.new('Review the personal fiscal identifier and its existing owner', field: 'personal_tax_identifier')
  end

  def persisted_identity_revision(contact)
    identity = contact.signing_identity
    identity&.persisted? ? identity.revision : 0
  end

  def confirm_reassignment!(contact)
    transferring = contact.persisted? && contact.company_id_in_database.present? && contact.will_save_change_to_company_id?
    return unless transferring && !@confirmations.fetch('reassignment', false)

    raise JrcCustomers::ImportIssue.new('Confirm changing the current company and clearing its former context',
                                        field: 'company_id', code: 'CONFIRM_REASSIGNMENT')
  end

  def confirm_primary!(contact)
    return unless contact.company_primary? && contact.company_id
    return unless @directory.scope.where(company_id: contact.company_id, company_primary: true).where.not(id: contact.id).exists?
    return if @confirmations.fetch('primary_change', false)

    raise JrcCustomers::ImportIssue.new('Confirm replacing the current primary contact', field: 'company_primary', code: 'CONFIRM_PRIMARY_CHANGE')
  end

  def check_repeated!(contact, attributes, line)
    keys = attributes.values.slice('identifier', 'email', 'phone_number').map { |field, value| "#{field}:#{value}" }
    keys << "id:#{contact.id}" if contact.persisted?
    digest = JrcCustomers::SigningIdentity.digest_for(account_id: @account.id, value: attributes.personal_identifier)
    keys << "cpf:#{digest}" if digest
    if keys.any? { |key| @seen.key?(key) }
      raise JrcCustomers::ImportIssue.new('Repeated contact identity in this file', field: 'identity', code: 'REPEATED_CONTACT')
    end

    keys.each { |key| @seen[key] = line }
  end

  def check_primary!(contact, line)
    return unless contact.company_primary?

    company = contact.master_company
    raise ActiveRecord::RecordNotFound unless company

    key = company.id || company.tax_id || company.object_id
    raise JrcCustomers::ImportIssue.new('Only one primary contact per company may be selected', field: 'company_primary') if @primaries.key?(key)

    @primaries[key] = line
  end
end
