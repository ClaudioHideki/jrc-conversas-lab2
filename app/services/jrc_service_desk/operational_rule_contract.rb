# frozen_string_literal: true

# Finite intake/deadline configuration. This is not a script or Flow executor.
# No business thresholds, precedence or priority levels are invented here.
class JrcServiceDesk::OperationalRuleContract
  KINDS = %w[routing priority_matrix sla_selection approval_deadline recurrence].freeze
  MATCH_FIELDS = %w[inbox_id channel_type company_id contract_id category_id service_id priority_id ticket_type_id impact urgency].freeze
  APPROVAL_TARGETS = %w[approver_account_user_id approver_team_id approver_role approver_custom_role_id].freeze
  MAX_RULES = 100
  MAX_ID = (2**63) - 1

  def self.validate!(kind, definition)
    raise ArgumentError, 'Unsupported rule family' unless KINDS.include?(kind)
    raise ArgumentError, 'Definition must be an object' unless definition.is_a?(Hash)

    JrcServiceDesk::CanonicalJson.dump(definition)
    case kind
    when 'approval_deadline' then deadline!(definition)
    when 'recurrence' then recurrence!(definition)
    else rules!(kind, definition)
    end
    definition
  end

  def self.rules!(kind, definition)
    fields!(definition, %w[rules])
    rows = definition.fetch('rules')
    raise ArgumentError, 'One to 100 explicit rules required' unless rows.is_a?(Array) && rows.length.between?(1, MAX_RULES)

    rows.each do |row|
      fields!(row, %w[key precedence match output])
      token!(row.fetch('key'))
      integer!(row.fetch('precedence'), 0, 1_000_000)
      predicates!(row.fetch('match'))
      output!(kind, row.fetch('output'))
      next unless kind == 'priority_matrix'

      raise ArgumentError, 'Matrix needs impact and urgency' unless %w[impact urgency].all? { |key| row['match'].key?(key) }
    end
    raise ArgumentError, 'Duplicate rule key' unless rows.map { |row| row['key'] }.uniq.size == rows.size
  end

  def self.predicates!(values)
    fields!(values, MATCH_FIELDS, required: false)
    values.each do |key, value|
      if key.end_with?('_id')
        integer!(value, 1, MAX_ID)
      elsif key == 'channel_type'
        raise ArgumentError, 'Native channel class required' unless value.is_a?(String) && value.match?(/\AChannel::[A-Za-z][A-Za-z0-9]{0,60}\z/)
      else
        token!(value)
      end
    end
  end

  def self.output!(kind, output)
    key = { 'routing' => 'queue_id', 'priority_matrix' => 'priority_id', 'sla_selection' => 'snapshot' }.fetch(kind)
    fields!(output, [key])
    if key == 'snapshot'
      snapshot!(output[key])
    else
      integer!(output.fetch(key), 1, MAX_ID)
    end
  end

  def self.snapshot!(values)
    source = %w[source_system source_reference source_version policy_key policy_version calendar_key calendar_version]
    objects = %w[contract_conditions policy_conditions calendar_conditions]
    fields!(values, source + objects + %w[calendar_scope timezone])
    (source + ['timezone']).each do |key|
      value = values[key]
      raise ArgumentError, 'Snapshot provenance required' unless value.is_a?(String) && value.strip.length.between?(1, 255)
    end
    raise ArgumentError, 'Explicit calendar scope required' unless %w[account operator_company unit].include?(values['calendar_scope'])

    objects.each do |key|
      raise ArgumentError, 'Snapshot conditions must be objects' unless values[key].is_a?(Hash)
      raise ArgumentError, 'Credential fields are not configuration' if credential_key?(values[key])
    end
    budgets = values['policy_conditions']['clock_budgets_seconds']
    unless budgets.is_a?(Hash) && (budgets.keys - %w[first_response attendance resolution]).empty? &&
           %w[first_response resolution].all? { |key| budgets.key?(key) }
      raise ArgumentError, 'Explicit native clock budgets required'
    end

    budgets.each_value { |value| integer!(value, 1, (2**53) - 1) }
  end

  def self.credential_key?(value)
    case value
    when Hash
      value.any? do |key, item|
        key.to_s.match?(/password|secret|credential|access_token|refresh_token|api_key|authorization/i) ||
          %w[__proto__ constructor prototype].include?(key) || credential_key?(item)
      end
    when Array then value.any? { |item| credential_key?(item) }
    else false
    end
  end

  def self.deadline!(values)
    fields!(values, %w[executor_account_user_id after_due_seconds new_due_seconds target reason])
    integer!(values.fetch('executor_account_user_id'), 1, MAX_ID)
    integer!(values.fetch('after_due_seconds'), 0, 31_536_000)
    integer!(values.fetch('new_due_seconds'), 1, 31_536_000)
    fields!(values.fetch('target'), APPROVAL_TARGETS, required: false)
    raise ArgumentError, 'Exactly one target required' unless values['target'].size == 1

    key, target = values['target'].first
    if key == 'approver_role'
      raise ArgumentError, 'Native role required' unless %w[agent administrator].include?(target)
    else
      integer!(target, 1, MAX_ID)
    end
    reason = values.fetch('reason')
    raise ArgumentError, 'Explicit escalation reason required' unless reason.is_a?(String) && reason.strip.length.between?(1, 1000)
  end

  def self.recurrence!(values)
    fields!(values, %w[window_days minimum_occurrences group_by])
    integer!(values.fetch('window_days'), 1, 366)
    integer!(values.fetch('minimum_occurrences'), 2, 1000)
    dimensions = values.fetch('group_by')
    allowed = %w[company_id service_id category_id ticket_type_id normalized_title]
    unless dimensions.is_a?(Array) && !dimensions.empty? && dimensions.uniq == dimensions && (dimensions - allowed).empty?
      raise ArgumentError, 'Explicit supported grouping dimensions required'
    end
  end

  def self.fields!(value, allowed, required: true)
    unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) } && (value.keys - allowed).empty?
      raise ArgumentError, 'Unsupported configuration fields'
    end
    raise ArgumentError, 'Missing configuration fields' if required && !(allowed - value.keys).empty?
  end

  def self.integer!(value, minimum, maximum)
    raise ArgumentError, 'Integer outside allowed range' unless value.is_a?(Integer) && value.between?(minimum, maximum)
  end

  def self.token!(value)
    raise ArgumentError, 'Invalid configuration code' unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}\z/)
  end
end
