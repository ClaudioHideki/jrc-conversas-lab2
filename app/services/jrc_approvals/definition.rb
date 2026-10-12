class JrcApprovals::Definition
  KEYS = %w[schema_version condition selection execution completion steps expires_in_seconds
            allow_self_approval delegation_allowed reopen_mode].freeze
  STEP_KEYS = %w[code mode quorum assignees authority actions on_reject].freeze
  ACTIONS = %w[approved rejected returned escalated].freeze

  def self.validate!(definition, entry)
    data = JrcServiceDesk::CanonicalJson.normalize(definition)
    JrcServiceDesk::CanonicalJson.dump(data)
    invalid! unless data.is_a?(Hash) && data.keys.sort == KEYS.sort && data['schema_version'] == 1
    invalid! unless %w[sequential parallel].include?(data['execution']) && data['completion'] == 'all_steps'
    invalid! unless %w[disabled restart_all].include?(data['reopen_mode'])
    invalid! unless %w[allow_self_approval delegation_allowed].all? { |key| [true, false].include?(data[key]) }
    invalid! unless data['expires_in_seconds'].is_a?(Integer) && data['expires_in_seconds'].between?(1, 31_536_000)
    selection = data['selection']
    invalid! unless selection.is_a?(Hash) && selection.keys.sort == %w[mode priority] &&
      %w[exclusive accumulate].include?(selection['mode']) && selection['priority'].is_a?(Integer)
    conditions = JrcApprovals::Conditions.new(entry.fields)
    conditions.validate!(data['condition'])
    steps = data['steps']
    invalid! unless steps.is_a?(Array) && steps.size.between?(1, 16)
    invalid! unless steps.map { |s| s['code'] }.uniq.size == steps.size
    steps.each do |step|
      invalid! unless step.is_a?(Hash) && step.keys.sort == STEP_KEYS.sort && step['code'].is_a?(String) &&
        step['code'].match?(/\A[a-z][a-z0-9_]{0,63}\z/) && %w[all any quorum].include?(step['mode'])
      invalid! unless step['quorum'].is_a?(Integer) && step['quorum'].positive?
      invalid! if step['mode'] == 'any' && step['quorum'] != 1
      invalid! unless step['actions'].is_a?(Array) && step['actions'].uniq == step['actions'] &&
        step['actions'].include?('approved') && (step['actions'] - ACTIONS).empty?
      invalid! unless %w[rejected returned escalated].include?(step['on_reject'])
      rules = step['assignees']
      invalid! unless rules.is_a?(Array) && rules.size.between?(1, 32) && rules.uniq == rules
      rules.each do |rule|
        invalid! unless rule.is_a?(Hash) && rule.keys.sort == %w[id type] &&
          %w[account_user team custom_role].include?(rule['type']) && rule['id'].is_a?(Integer) && rule['id'].positive?
      end
      conditions.validate!(step['authority'])
    end
    data
  rescue ArgumentError, NoMethodError, KeyError, TypeError
    invalid!
  end

  def self.invalid!
    raise JrcApprovals::Error, 'INVALID_DEFINITION'
  end
end
