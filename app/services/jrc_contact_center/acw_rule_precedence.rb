# frozen_string_literal: true

# Selection only. The caller must supply its authorized native attendance/team snapshot,
# never IDs from a request as access authority. No endpoint or policy activation here.
class JrcContactCenter::AcwRulePrecedence
  ORDER = %w[queue team general].freeze
  FIELDS = %w[id reason_code scope scope_id active limit_seconds].freeze

  class Conflict < JrcContactCenter::OperationError
    attr_reader :level

    def initialize(level)
      @level = level
      super('conflicting_acw_rules', status: :conflict)
    end
  end

  def initialize(rules:)
    raise JrcContactCenter::OperationError, 'invalid_acw_rules' unless rules.is_a?(Array)

    raise JrcContactCenter::OperationError, 'invalid_acw_rules' if rules.length > 100 || rules.to_json.bytesize > 131_072

    @rules = rules.deep_dup.map { |rule| validated_rule(rule) }
    ids = @rules.pluck('id')
    raise JrcContactCenter::OperationError, 'invalid_acw_rules' unless ids.uniq.length == ids.length
  end

  def call(reason_code:, queue_id:, team_ids:)
    valid = reason_code.is_a?(String) && reason_code.strip.present? && reason_code.length <= 100 && team_ids.is_a?(Array)
    raise JrcContactCenter::OperationError, 'invalid_acw_rule_context' unless valid

    queue = queue_id.nil? ? nil : identifier(queue_id, 'invalid_acw_rule_context')
    teams = team_ids.map { |id| identifier(id, 'invalid_acw_rule_context') }.uniq
    candidates = @rules.select { |row| row.fetch('active') && row.fetch('reason_code') == reason_code }
    select_rule(candidates, queue, teams)
  end

  def rules
    @rules.deep_dup
  end

  private

  def select_rule(candidates, queue, teams)
    ORDER.each do |level|
      matches = candidates.select { |row| row.fetch('scope') == level && applicable?(row, queue, teams) }
      raise Conflict, level if matches.length > 1
      return matches.sole.deep_dup if matches.one?
    end
    nil # Preserve the native global snapshot when no rule applies.
  end

  def validated_rule(input)
    raise JrcContactCenter::OperationError, 'invalid_acw_rules' unless input.is_a?(Hash)

    row = input.deep_stringify_keys
    validate_fields!(row)

    if row.fetch('scope') == 'general'
      raise JrcContactCenter::OperationError, 'invalid_acw_rules' unless row['scope_id'].nil?
    else
      row['scope_id'] = identifier(row['scope_id'], 'invalid_acw_rules')
    end
    row
  end

  def validate_fields!(row)
    valid = row.keys.sort == FIELDS.sort && text?(row['id'], 64) && text?(row['reason_code'], 100) &&
            ORDER.include?(row['scope']) && [true, false].include?(row['active'])
    raise JrcContactCenter::OperationError, 'invalid_acw_rules' unless valid

    unless row['limit_seconds'].is_a?(Integer) && row['limit_seconds'].between?(1, 3600)
      raise JrcContactCenter::OperationError, 'invalid_acw_rules'
    end
  end

  def text?(value, maximum)
    value.is_a?(String) && value.strip.present? && value.length <= maximum
  end

  def identifier(value, error)
    string = value.to_s if value.is_a?(Integer) || value.is_a?(String)
    valid = string&.match?(/\A[1-9]\d{0,18}\z/) && string.to_i <= 9_223_372_036_854_775_807
    raise JrcContactCenter::OperationError, error unless valid

    string
  end

  def applicable?(row, queue, teams)
    case row.fetch('scope')
    when 'queue' then queue && row.fetch('scope_id') == queue
    when 'team' then teams.include?(row.fetch('scope_id'))
    else true
    end
  end
end
