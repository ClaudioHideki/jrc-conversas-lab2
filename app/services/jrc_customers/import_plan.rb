class JrcCustomers::ImportPlan
  attr_reader :rows, :errors, :totals, :mapping, :options

  def initialize(account:, actor:, file:, mapping:, options:)
    values = options.stringify_keys
    existing = values.fetch('existing')
    confirmations = values.fetch('confirmations', {})
    raise JrcCustomers::ImportFile::InvalidFile, 'Choose update or skip for existing records' unless %w[update skip].include?(existing)
    unless confirmations.is_a?(Hash) && (confirmations.keys - %w[reassignment primary_change]).empty? &&
           confirmations.values.all? { |value| [true, false].include?(value) }
      raise JrcCustomers::ImportFile::InvalidFile, 'Review the explicit company-context confirmations'
    end

    @account = account
    @actor = actor
    @file = file
    @kind = file.kind
    @mapping = mapping
    @options = { existing: existing, confirmations: confirmations }
  end

  def call
    JrcCustomers::ImportAccess.new(account: @account, actor: @actor).authorize!(kind: @file.kind)
    mapped = @file.mapped_rows(@mapping)
    entities = plan_entities(mapped)
    @rows = entities.flat_map(&:rows).sort_by { |row| [row.fetch(:line), row.fetch(:entity)] }
    @errors = entities.flat_map(&:errors).sort_by { |error| [error.fetch(:line), error.fetch(:entity)] }
    @totals = counts(mapped)
    self
  end

  def digest
    data = { rows: rows, errors: errors, totals: totals, mapping: mapping, options: options }
    Digest::SHA256.hexdigest(JSON.generate(JrcServiceDesk::CanonicalJson.normalize(data)))
  end

  def public_rows
    rows.map do |row|
      safe = row.except(:personal_identifier, :identity_revision).deep_dup
      attributes = safe.fetch(:attributes)
      tax = JrcCustomers::TaxIdentifier.normalize(attributes['tax_id'])
      attributes['tax_id'] = "***.***.***-#{tax[-2, 2]}" if tax&.length == 11
      safe
    end
  end

  def lock_targets
    %w[company contact].index_with { |entity| rows.select { |row| row.fetch(:entity) == entity }.filter_map { |row| row[:record_id] }.uniq.sort }
  end

  private

  def plan_entities(mapped)
    companies = JrcCustomers::ImportCompanyPlan.new(account: @account, actor: @actor, existing: options.fetch(:existing), combined: @kind == 'both')
    companies.call(mapped)
    contacts = JrcCustomers::ImportContactPlan.new(account: @account, actor: @actor, existing: options.fetch(:existing),
                                                   confirmations: options.fetch(:confirmations)).call(mapped, companies: companies)
    [companies, contacts]
  end

  def counts(mapped)
    invalid = errors.pluck(:line).uniq
    actions = rows.group_by { |row| "#{row.fetch(:entity)}_#{row.fetch(:action)}" }.transform_values(&:size)
    ignored = mapped.count { |source| source.fetch(:company).values.all?(&:blank?) && source.fetch(:contact).values.all?(&:blank?) }
    actions.merge('total_rows' => mapped.size, 'valid_rows' => mapped.size - invalid.size, 'invalid_rows' => invalid.size,
                  'ignored_rows' => ignored, 'error_count' => errors.size)
  end
end
