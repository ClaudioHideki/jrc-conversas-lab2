# frozen_string_literal: true

# Unapplied WIP: validates stored structure, never current authorization or historical scope inference.
class JrcContactCenter::EndingActions::RuleDefinition
  TIMINGS = %w[call_end acw_completed].freeze
  FIELDS = %w[code name reason_code queue_id timing active actions conditions scope].freeze
  SCOPE_FIELDS = %w[queue_scope_version_id integrity_sha256 unit_id issuer_company_id business_unit_id].freeze

  def call(value)
    valid = value.is_a?(Hash) && value.keys.all?(String) && value.keys.sort == %w[entries version]
    invalid! unless valid && value['version'].is_a?(Integer) && value['version'].between?(1, 2_147_483_647)
    entries = value.fetch('entries')
    invalid! unless entries.is_a?(Array) && entries.length <= 100
    entries.each { |entry| validate_entry!(entry) }
    invalid! unless entries.pluck('code').uniq.length == entries.length && value.to_json.bytesize <= 262_144
    value
  rescue JSON::GeneratorError
    invalid!
  end

  private

  def validate_entry!(row)
    valid = row.is_a?(Hash) && row.keys.all?(String) && row.keys.sort == FIELDS.sort
    invalid! unless valid && text?(row['code'], 100) && text?(row['name'], 120) && text?(row['reason_code'], 100)
    invalid! unless identifier?(row['queue_id']) && [true, false].include?(row['active']) && TIMINGS.include?(row['timing'])
    validate_scope!(row.fetch('scope'), active: row.fetch('active'))
    validate_actions!(row.fetch('actions'), active: row.fetch('active'))
    validate_conditions!(row.fetch('conditions'), timing: row.fetch('timing'))
  end

  def validate_scope!(scope, active:)
    valid = scope.is_a?(Hash) && scope.keys.all?(String) && scope.keys.sort == SCOPE_FIELDS.sort
    invalid! unless valid && identifier?(scope['queue_scope_version_id']) && identifier?(scope['unit_id'])
    invalid! unless scope['integrity_sha256'].is_a?(String) && scope['integrity_sha256'].valid_encoding? &&
                    scope['integrity_sha256'].match?(/\A[0-9a-f]{64}\z/)
    %w[issuer_company_id business_unit_id].each do |key|
      invalid! unless scope[key].nil? || identifier?(scope[key])
    end
    invalid! if active && !identifier?(scope['issuer_company_id'])
  end

  def validate_actions!(actions, active:)
    invalid! unless actions.is_a?(Array) && actions.length <= 5 && (!active || actions.any?)
    actions.each do |action|
      invalid! unless action.is_a?(Hash) && action.keys.all?(String) && action.keys.sort == %w[kind parameters]
      raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action['kind'] == 'project_task'

      normalized = JrcContactCenter::EndingActions::TaskDefinition.new.call(action.fetch('parameters'))
      invalid! unless normalized == action.fetch('parameters')
    end
    invalid! unless actions.pluck('kind').uniq.length == actions.length
  end

  def validate_conditions!(conditions, timing:)
    invalid! unless conditions.is_a?(Hash) && conditions.keys == ['outcome_codes']
    codes = conditions.fetch('outcome_codes')
    valid = codes.is_a?(Array) && codes.length <= 10 && codes.all? { |code| text?(code, 100) }
    invalid! unless valid && codes.uniq.sort == codes
    invalid! if codes.any? && timing != 'acw_completed'
  end

  def identifier?(value)
    value.is_a?(String) && value.valid_encoding? && value.match?(/\A[1-9][0-9]{0,18}\z/) && value.to_i <= 9_223_372_036_854_775_807
  end

  def text?(value, maximum)
    value.is_a?(String) && value.valid_encoding? && !value.include?("\u0000") &&
      value.strip.present? && value == value.strip && value.length <= maximum
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_definition'
  end
end
