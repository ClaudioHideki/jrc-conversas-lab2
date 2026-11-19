# frozen_string_literal: true

# Validates configuration references, not user authority. Callers must retain the native
# global configuration or owned-attendance authorization before exposing this data.
class JrcContactCenter::AcwFormBindings
  FIELDS = %w[rule_id form_id revision required_fields].freeze
  PIN_FIELDS = (FIELDS + ['integrity_sha256']).freeze

  def initialize(account:)
    @account = account
  end

  # New links require an active catalogue identity and an exact active version.
  def validate!(input, rules:, preserved: [])
    allowed = JrcContactCenter::AcwScopedRules.new(account: @account).validate!(rules).pluck('id')
    previous = collection(preserved).map { |row| pinned_reference(row) }
    rows = collection(input).map { |row| new_binding(row, allowed, previous) }
    ordered(rows)
  end

  # Structural validation of server-stored pins. Ownership/schema are checked by
  # resolve! for the selected native attendance; this does not authorize an actor.
  def references!(input, rules:)
    allowed = JrcContactCenter::AcwRulePrecedence.new(rules: rules).rules.pluck('id')
    rows = collection(input).map do |input_row|
      row = pinned_reference(input_row)
      invalid! unless allowed.include?(row.fetch('rule_id'))

      row
    end
    ordered(rows)
  end

  # Hot-path capture reads bounded exact metadata once; the selected schema is resolved on actual use.
  def verify_metadata!(pins)
    rows = collection(pins).map { |row| pinned_reference(row) }
    return if rows.empty?

    indexed = indexed_metadata(rows)
    rows.each do |row|
      actual = indexed.fetch(row.values_at('form_id', 'revision')) { raise ActiveRecord::RecordNotFound }
      invalid! unless actual[2] == 'active' && actual[3] == row.fetch('integrity_sha256')
    end
  end

  # Frozen references resolve their original version even after a newer archive/version.
  # This returns no manager catalogue, historical actor IDs or mutable latest-version data.
  def resolve!(input)
    row = pinned_reference(input)
    version = find_version!(row)
    valid = version.status == 'active' && row['integrity_sha256'] == version.integrity_sha256
    invalid! unless valid

    required = required_fields(row, version)
    definition = version.definition.deep_dup
    definition.fetch('fields').each { |field| field['required'] = required.include?(field.fetch('key')) }
    row.slice('form_id', 'revision', 'integrity_sha256').merge('name' => version.name, 'definition' => definition)
  end

  private

  def indexed_metadata(rows)
    table = JrcContactCenter::AcwFormVersion.arel_table
    pairs = rows.map { |row| table[:acw_form_template_id].eq(row.fetch('form_id')).and(table[:revision].eq(row.fetch('revision'))) }
    metadata = JrcContactCenter::AcwFormVersion.where(account: @account).where(pairs.reduce(&:or))
                                               .pluck(:acw_form_template_id, :revision, :status, :integrity_sha256)
    metadata.index_by { |row| [row[0].to_s, row[1]] }
  end

  def collection(input)
    valid = input.is_a?(Array) && input.length <= 100 && input.to_json.bytesize <= 131_072
    invalid! unless valid

    input
  end

  def attributes(input, fields)
    invalid! unless input.is_a?(Hash)

    row = input.deep_stringify_keys.deep_dup
    invalid! unless row.keys.sort == fields.sort

    row
  end

  def ordered(rows)
    invalid! unless rows.pluck('rule_id').uniq.length == rows.length

    rows.sort_by { |row| row.fetch('rule_id') }.deep_dup
  end

  def pinned_reference(input)
    row = attributes(input, PIN_FIELDS)
    validate_identity!(row)
    digest = row['integrity_sha256']
    valid = digest.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(digest)
    invalid! unless valid

    row.merge('required_fields' => required_names(row['required_fields']))
  end

  def required_names(keys)
    valid = keys.is_a?(Array) && keys.length <= 50 && keys.uniq.length == keys.length
    invalid! unless valid
    invalid! unless keys.all? { |key| key.is_a?(String) && key.length.between?(1, 80) }

    keys.sort
  end

  def new_binding(input, allowed, previous)
    row = attributes(input, FIELDS)
    validate_identity!(row)
    invalid! unless allowed.include?(row.fetch('rule_id'))

    version = find_version!(row)
    invalid! unless version.status == 'active'

    result = row.merge('required_fields' => required_fields(row, version), 'integrity_sha256' => version.integrity_sha256)
    return result if previous.include?(result)

    invalid! unless version.acw_form_template.latest_version.status == 'active'

    result
  end

  def validate_identity!(row)
    rule = row['rule_id']
    valid = rule.is_a?(String) && rule.strip.present? && rule.length <= 64 && rule.exclude?("\0")
    invalid! unless valid

    validate_version_reference!(row)
  end

  def validate_version_reference!(row)
    revision = row['revision']
    valid = revision.is_a?(Integer) && revision.between?(1, 2_147_483_647)
    invalid! unless valid

    identifier = row['form_id']
    valid = identifier.is_a?(String) && /\A[1-9]\d{0,18}\z/.match?(identifier) && identifier.to_i <= 9_223_372_036_854_775_807
    invalid! unless valid
  end

  def find_version!(row)
    JrcContactCenter::AcwFormVersion.where(account: @account, acw_form_template_id: row.fetch('form_id'))
                                    .find_by!(revision: row.fetch('revision'))
  end

  def required_fields(row, version)
    keys = row['required_fields']
    fields = JrcContactCenter::AcwFormDefinition.new(version.definition).call.fetch('fields')
    valid = keys.is_a?(Array) && keys.length <= 50 && keys.uniq.length == keys.length
    invalid! unless valid
    invalid! unless (keys - fields.pluck('key')).empty?

    (keys + fields.select { |field| field.fetch('required') }.pluck('key')).uniq.sort
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_acw_form_bindings'
  end
end
