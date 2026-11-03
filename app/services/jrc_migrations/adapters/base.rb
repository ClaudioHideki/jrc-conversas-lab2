class JrcMigrations::Adapters::Base
  attr_reader :account
  attr_writer :migration_item

  def initialize(account:, source:)
    @account = account
    @source = source
  end

  def scope
    model.where(account_id: account.id)
  end

  def build(data, target: nil)
    attributes = data.except('id', 'account_id', 'lock_version', 'created_at', 'updated_at').slice(*assignable_attributes)
    validate_reference_values!(attributes)
    validate_calendar_dates!(attributes)
    record = target || model.new(account_id: account.id)
    record.assign_attributes(attributes)
    assign_dates!(record, data)
    resolve_relations!(record, data)
    raise JrcMigrations::Error, 'INVALID_DESTINATION' unless record.valid?(validation_context(record))

    prepare(record)
    record
  rescue ArgumentError, TypeError
    raise JrcMigrations::Error, 'INVALID_SOURCE_DATES'
  end

  def timestamp!(value)
    format = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/
    raise JrcMigrations::Error, 'INVALID_SOURCE_DATES' unless value.is_a?(String) && format.match?(value)

    Date.iso8601(value.first(10))
    Time.iso8601(value)
  rescue ArgumentError
    raise JrcMigrations::Error, 'INVALID_SOURCE_DATES'
  end

  def digest(record)
    JrcMigrations::Catalog.digest(record.attributes.slice(*model.column_names))
  end

  def update_allowed?
    true
  end

  def rollback_write!(_record); end
  def reserve_media!(_item, _prepared); end

  # The real model is validated by build; callbacks intentionally cannot run on imported history.
  # rubocop:disable Rails/SkipsModelValidations
  def write!(record)
    raise JrcMigrations::Error, 'APPEND_ONLY_DESTINATION' if record.persisted? && !update_allowed?

    # Validate/normalize through the real model above; write only the validated
    # attributes here. No save callbacks, event dispatcher or import jobs run.
    attributes = persistence_attributes(record)
    if record.new_record?
      id = model.insert_all!([attributes], returning: %w[id]).rows.first.first
      scope.find(id)
    else
      scope.where(id: record.id).update_all(attributes)
      scope.find(record.id)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  private

  def assignable_attributes
    model.column_names
  end

  def persistence_attributes(record)
    attributes = record.attributes.slice(*model.column_names).except('id')
    attributes[model.locking_column] = record[model.locking_column] + 1 if record.persisted? && model.locking_enabled?
    attributes
  end

  def validate_reference_values!(attributes)
    attributes.each do |key, value|
      next unless key.end_with?('_id') && value.present?
      next if reference_value?(value)

      raise JrcMigrations::Error, 'INVALID_REFERENCE_VALUE'
    end
  end

  def reference_value?(value)
    (value.is_a?(Integer) || value.is_a?(String)) && /\A[1-9]\d{0,18}\z/.match?(value.to_s) && value.to_i <= 9_223_372_036_854_775_807
  end

  def assign_dates!(record, data)
    created = timestamp!(data['created_at'])
    raise JrcMigrations::Error, 'SOURCE_CREATED_AT_CONFLICT' if record.persisted? && record.created_at != created

    record.created_at = created if record.new_record?
    updated = timestamp!(data['updated_at'])
    raise JrcMigrations::Error, 'INVALID_SOURCE_DATES' if updated < created

    record.updated_at = updated if record.has_attribute?(:updated_at)
  end

  def prepare(_record); end

  def validation_context(_record); end

  def validate_calendar_dates!(attributes)
    attributes.each do |key, value|
      next unless model.type_for_attribute(key).type == :date && value.present?

      raise JrcMigrations::Error, 'INVALID_SOURCE_DATES' unless value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(value)

      Date.iso8601(value)
    end
  rescue ArgumentError
    raise JrcMigrations::Error, 'INVALID_SOURCE_DATES'
  end

  def bind_legacy_reference!(record, data, field:, legacy_field:, domain: 'companies')
    return if data[legacy_field].blank?

    id = relation_id!(data[legacy_field], domain: domain)
    raise JrcMigrations::Error, 'RELATION_CONFLICT' if data[field].present? && data[field].to_i != id

    record.public_send("#{field}=", id)
  end

  def relation_id!(legacy_id, domain: 'companies')
    mapping = JrcMigrations::Mapping.find_by(account_id: account.id, source: @source, domain: domain, legacy_id: legacy_id)
    raise JrcMigrations::Error, 'RELATION_NOT_MAPPED' unless mapping

    mapping.target_id
  end

  def check_company!(id)
    return if id.blank? || JrcCustomers::Company.exists?(account_id: account.id, id: id)

    raise JrcMigrations::Error, 'RELATION_OUTSIDE_ACCOUNT'
  end
end
