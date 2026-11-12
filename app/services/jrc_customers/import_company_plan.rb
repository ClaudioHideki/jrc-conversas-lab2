require 'csv'

# Mapping feeds the existing fiscal-identity validator, not a second company engine.
class JrcCustomers::ImportCompanyPlan
  attr_reader :rows, :errors, :targets

  def initialize(account:, actor:, existing:, combined:)
    @account = account
    @actor = actor
    @existing = existing
    @combined = combined
    @rows = []
    @errors = []
    @targets = {}
    @seen = {}
  end

  def call(mapped)
    mapped.each { |source| inspect_row(source) }
    self
  end

  private

  def inspect_row(source)
    attrs = source.fetch(:company).transform_values { |value| value.to_s.strip.presence }.compact
    return if attrs.empty?

    record = identity(attrs)
    attrs = reviewed_attributes(record, attrs)
    previous = repeated(attrs, record)
    return reference!(source, attrs, previous) if previous

    validated = validate(attrs, source.fetch(:line))
    return unless validated

    append!(source.fetch(:line), validated, attrs)
  rescue JrcCustomers::CompanyImport::InvalidImport, ActiveRecord::RecordNotFound, ArgumentError => e
    @errors << exception_error(e, source.fetch(:line))
  end

  def reviewed_attributes(record, attrs)
    return { 'id' => record.id.to_s, 'name' => record.name } if record && @existing == 'skip'

    attrs['name'] ||= record&.name
    attrs
  end

  def identity(attrs)
    record = @account.master_companies.find(Integer(attrs['id'], 10)) if attrs['id'].present?
    tax = JrcCustomers::TaxIdentifier.normalize(attrs['tax_id'])
    by_tax = @account.master_companies.find_by(tax_id: tax) if tax
    conflict = record && by_tax && record.id != by_tax.id
    raise JrcCustomers::CompanyImport::InvalidImport, 'ID and CPF/CNPJ point to different companies' if conflict

    record || by_tax
  end

  def repeated(attrs, record)
    identity_keys(attrs, record).filter_map { |key| @seen[key] }.first
  end

  def identity_keys(attrs, record)
    keys = []
    keys << "id:#{record.id}" if record
    tax = JrcCustomers::TaxIdentifier.normalize(attrs['tax_id'])
    keys << "tax:#{tax}" if tax
    keys << "name:#{attrs['name'].to_s.downcase}" if keys.empty?
    keys << "domain:#{attrs['domain'].downcase}" if attrs['domain'].present?
    keys
  end

  def reference!(source, attrs, previous)
    identified = previous.fetch(:row).fetch(:record_id).present? || JrcCustomers::TaxIdentifier.normalize(attrs['tax_id']).present?
    unless @combined && identified && previous.fetch(:source_attributes) == attrs
      raise JrcCustomers::CompanyImport::InvalidImport, 'Repeated company identity or conflicting company values in this file'
    end

    line = source.fetch(:line)
    original = previous.fetch(:row)
    @rows << original.merge(line: line, action: 'reference', reference_line: original.fetch(:line))
    @targets[line] = @targets.fetch(original.fetch(:line))
  end

  def validate(attrs, line)
    content = CSV.generate do |csv|
      csv << attrs.keys
      csv << attrs.values
    end
    result = JrcCustomers::CompanyImport.new(account: @account, actor: @actor, content: content).preview
    result.fetch(:errors).each do |error|
      @errors << { line: line, entity: 'company', field: error[:field] || 'company', code: error.fetch(:code), message: safe_message(error) }
    end
    result.fetch(:rows).first
  end

  def unavailable_error(line)
    { line: line, entity: 'company', field: 'id', code: 'UNAVAILABLE_RECORD', message: 'Company unavailable in the current account or scope' }
  end

  def exception_error(error, line)
    return unavailable_error(line) if error.is_a?(ActiveRecord::RecordNotFound)
    if error.is_a?(JrcCustomers::CompanyImport::InvalidImport)
      return { line: line, entity: 'company', field: error.field || 'company', code: error.code, message: error.message }
    end

    { line: line, entity: 'company', field: 'id', code: 'INVALID_REFERENCE', message: 'Review the mapped internal ID' }
  end

  def safe_message(error)
    return 'Review the mapped internal ID' if error[:code] == 'INVALID_REFERENCE'
    return 'Company unavailable in the current account or scope' if error[:code] == 'UNAVAILABLE_RECORD'

    error.fetch(:error)
  end

  def append!(line, validated, source_attrs)
    id = validated.fetch(:company_id)
    company = id ? @account.master_companies.find(id) : @account.master_companies.new(relationship_type: 'prospect')
    action = id && @existing == 'skip' ? 'skip' : validated.fetch(:action)
    attrs = action == 'skip' ? {} : validated.fetch(:attributes)
    company.assign_attributes(attrs)
    row = { line: line, entity: 'company', action: action, record_id: id, revision: validated.fetch(:updated_at), attributes: attrs }
    @rows << row
    @targets[line] = company
    identity_keys(source_attrs, company.persisted? ? company : nil).each { |key| @seen[key] = { source_attributes: source_attrs, row: row } }
  end
end
