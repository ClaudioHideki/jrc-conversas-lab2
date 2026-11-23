# frozen_string_literal: true

# Validates stored structure, never current authorization or historical scope inference.
class JrcContactCenter::EndingActions::RuleDefinition
  TIMINGS = %w[call_end acw_completed].freeze
  EXECUTION_MODES = %w[automatic agent_confirmation].freeze
  FIELDS = %w[code name reason_code queue_id timing active actions conditions scope].freeze
  SCOPE_FIELDS = %w[queue_scope_version_id integrity_sha256 unit_id issuer_company_id business_unit_id].freeze

  def call(value)
    validate_keys!(value, %w[entries version])
    invalid! unless value['version'].is_a?(Integer) && value['version'].between?(1, 2_147_483_647)

    entries = value.fetch('entries')
    validate_entries!(entries)
    invalid! unless value.to_json.bytesize <= 262_144
    value
  rescue JSON::GeneratorError
    invalid!
  end

  private

  def validate_keys!(value, fields)
    invalid! unless value.is_a?(Hash) && value.keys.all?(String) && value.keys.sort == fields.sort
  end

  def validate_entries!(entries)
    invalid! unless entries.is_a?(Array) && entries.length <= 100

    entries.each { |entry| validate_entry!(entry) }
    invalid! unless entries.pluck('code').uniq.length == entries.length
  end

  def validate_entry!(row)
    validate_entry_keys!(row)
    invalid! unless text?(row['code'], 100) && text?(row['name'], 120) && text?(row['reason_code'], 100)
    invalid! unless identifier?(row['queue_id']) && [true, false].include?(row['active']) && TIMINGS.include?(row['timing'])
    validate_scope!(row.fetch('scope'), active: row.fetch('active'))
    validate_actions!(row.fetch('actions'), active: row.fetch('active'))
    validate_conditions!(row.fetch('conditions'), timing: row.fetch('timing'))
  end

  # Legacy immutable definitions remain readable byte for byte. Absence of this
  # field never grants an executor permission to run a historical rule.
  def validate_entry_keys!(row)
    fields = row.is_a?(Hash) && row.key?('execution_mode') ? FIELDS + ['execution_mode'] : FIELDS
    validate_keys!(row, fields)
    invalid! if row.key?('execution_mode') && !EXECUTION_MODES.include?(row['execution_mode'])
  end

  def validate_scope!(scope, active:)
    validate_keys!(scope, SCOPE_FIELDS)
    invalid! unless identifier?(scope['queue_scope_version_id']) && identifier?(scope['unit_id'])
    invalid! unless digest?(scope['integrity_sha256'])

    validate_optional_scope!(scope)
    invalid! if active && !identifier?(scope['issuer_company_id'])
  end

  def validate_optional_scope!(scope)
    %w[issuer_company_id business_unit_id].each { |key| invalid! unless scope[key].nil? || identifier?(scope[key]) }
  end

  def validate_actions!(actions, active:)
    invalid! unless actions.is_a?(Array) && actions.length <= 5
    invalid! if active && actions.empty?

    actions.each { |action| validate_action!(action) }
    invalid! unless actions.pluck('kind').uniq.length == actions.length
  end

  def validate_action!(action)
    validate_keys!(action, %w[kind parameters])
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action['kind'] == 'project_task'

    normalized = JrcContactCenter::EndingActions::TaskDefinition.new.call(action.fetch('parameters'))
    invalid! unless normalized == action.fetch('parameters')
  end

  def validate_conditions!(conditions, timing:)
    invalid! unless conditions.is_a?(Hash) && conditions.keys == ['outcome_codes']
    codes = conditions.fetch('outcome_codes')
    validate_condition_codes!(codes)
    invalid! if codes.any? && timing != 'acw_completed'
  end

  def validate_condition_codes!(codes)
    invalid! unless codes.is_a?(Array) && codes.length <= 10 && codes.all? { |code| text?(code, 100) }
    invalid! unless codes.uniq.sort == codes
  end

  def digest?(value)
    value.is_a?(String) && value.valid_encoding? && value.match?(/\A[0-9a-f]{64}\z/)
  end

  def identifier?(value)
    value.is_a?(String) && value.valid_encoding? && value.match?(/\A[1-9][0-9]{0,18}\z/) && value.to_i <= 9_223_372_036_854_775_807
  end

  def text?(value, maximum)
    value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000") &&
      value.strip.present? && value == value.strip && value.length <= maximum
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_definition'
  end
end
