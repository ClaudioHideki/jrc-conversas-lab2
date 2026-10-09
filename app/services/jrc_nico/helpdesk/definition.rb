class JrcNico::Helpdesk::Definition
  RULE_KEYS = (1..16).map { |n| format('R%02d', n) }.freeze
  ROLES = %w[n2 thiago supervisor cs management director ceo legal].freeze
  KEYS = %w[format unit_ids company_ids operator_ids priority_order roles hourly_limit approval_ttl_seconds rules daily].freeze
  GROUP_KEYS = %w[A1 A2 A3 A4 B1 B2 C1 C2 D1 D2 E].freeze
  DEFAULTS = {
    'R01' => { 'window_days' => 14 }, 'R02' => { 'count' => 3, 'window_days' => 30 },
    'R03' => { 'count' => 5, 'window_days' => 60, 'confirmed' => false },
    'R04' => { 'count' => 4, 'window_minutes' => 60 },
    'R05' => { 'percent' => 80, 'confirmed' => false }, 'R06' => {},
    'R07' => { 'hours' => 24, 'basis' => 'calendar', 'confirmed' => false },
    'R08' => { 'hours' => 72, 'basis' => 'calendar', 'confirmed' => false },
    'R09' => { 'days' => 7, 'basis' => 'calendar', 'confirmed' => false },
    'R10' => { 'keywords' => %w[novamente absurdo reclamação cancelar], 'phrases' => ['mesmo problema'] },
    'R11' => { 'keywords' => %w[procon anatel advogado processo], 'phrases' => ['notificação extrajudicial'] },
    'R12' => { 'critical_company_ids' => [], 'priority_ids' => {} }, 'R13' => { 'days' => [2, 5, 15] },
    'R14' => {}, 'R15' => {}, 'R16' => {}
  }.freeze

  def self.defaults
    { 'format' => 'nico-helpdesk-v1', 'unit_ids' => [], 'company_ids' => [], 'operator_ids' => [],
      'priority_order' => {}, 'roles' => ROLES.index_with { [] }, 'hourly_limit' => 10, 'approval_ttl_seconds' => 600,
      'rules' => DEFAULTS.transform_values { |rule| rule.deep_dup.merge('enabled' => false, 'recipients' => [], 'channels' => ['nico']) },
      'daily' => { 'enabled' => false, 'timezone' => 'America/Sao_Paulo', 'hour' => 18, 'recipients' => [], 'channels' => ['nico'] },
      'groups' => GROUP_KEYS.index_with { { 'enabled' => false } } }
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JrcServiceDesk::CanonicalJson.dump(value))
  end

  def self.validate!(value)
    header!(value)
    %w[unit_ids company_ids operator_ids].each { |key| ids!(value.fetch(key)) }
    priorities!(value.fetch('priority_order'), value.fetch('unit_ids'))
    roles!(value.fetch('roles'))
    bounded_integer!(value['hourly_limit'], 1, 1000)
    bounded_integer!(value['approval_ttl_seconds'], 30, 900)
    rules!(value.fetch('rules'))
    required_priority_targets!(value)
    daily!(value.fetch('daily'))
    daily_recipients!(value)
    groups!(value['groups']) if value.key?('groups')
    JrcServiceDesk::CanonicalJson.dump(value)
    true
  end

  def self.header!(value)
    return if value.is_a?(Hash) && value.except('groups').keys.sort == KEYS.sort && value['format'] == 'nico-helpdesk-v1'

    raise ArgumentError,
          'Unsupported policy contract'
  end

  def self.groups!(groups)
    raise ArgumentError, 'Explicit finite HelpDesk groups required' unless groups.is_a?(Hash) && groups.keys.sort == GROUP_KEYS.sort

    groups.each_value do |entry|
      raise ArgumentError, 'Unexpected group configuration' unless entry.is_a?(Hash) && entry.keys == ['enabled']

      boolean!(entry['enabled'])
    end
  end

  def self.priorities!(order, unit_ids)
    raise ArgumentError, 'Explicit Unit priority ordering required' unless order.is_a?(Hash) &&
                                                                           order.keys.all? { |id| unit_ids.include?(id.to_i) && id.to_i.to_s == id }

    order.each_value { |ids| ids!(ids) }
  end

  def self.roles!(roles)
    raise ArgumentError, 'Explicit escalation roles required' unless roles.is_a?(Hash) && roles.keys.sort == ROLES.sort

    roles.each_value { |ids| ids!(ids) }
  end

  def self.rules!(rules)
    raise ArgumentError, 'All sixteen rules must be explicit' unless rules.is_a?(Hash) && rules.keys.sort == RULE_KEYS

    rules.each { |key, rule| validate_rule!(key, rule) }
  end

  def self.daily_recipients!(value)
    return unless value.dig('daily', 'enabled') && (value.dig('daily', 'recipients') - value.dig('roles', 'thiago')).any?

    raise ArgumentError, 'Daily recipients must be explicitly designated in the thiago role'
  end

  def self.ids!(value)
    raise ArgumentError, 'Explicit unique record IDs required' unless value.is_a?(Array) && value.size <= 1000 &&
                                                                      value.uniq == value && value.all? { |n| n.is_a?(Integer) && n.positive? }
  end

  def self.channels!(value)
    raise ArgumentError, 'Explicit supported channels required' unless value.is_a?(Array) && value.uniq == value &&
                                                                       (value - %w[nico email whatsapp]).empty?
  end

  def self.bounded_integer!(value, minimum, maximum)
    raise ArgumentError, 'Policy number outside bounds' unless value.is_a?(Integer) && value.between?(minimum, maximum)
  end

  def self.boolean!(value)
    raise ArgumentError, 'Explicit boolean required' unless [true, false].include?(value)
  end

  def self.validate_rule!(key, rule)
    expected = DEFAULTS.fetch(key).keys + %w[enabled recipients channels]
    raise ArgumentError, 'Unexpected rule fields' unless rule.is_a?(Hash) && rule.keys.sort == expected.sort

    boolean!(rule.fetch('enabled'))
    ids!(rule.fetch('recipients'))
    channels!(rule.fetch('channels'))
    rule.slice('count', 'window_days', 'window_minutes', 'hours', 'percent').each_value { |value| bounded_integer!(value, 1, 365) }
    boolean!(rule['confirmed']) if rule.key?('confirmed')
    validate_specific!(key, rule)
    raise ArgumentError, "#{key} requires an explicit resolution of source conflicts" if rule['enabled'] && rule['confirmed'] == false
  end

  def self.validate_specific!(key, rule)
    validate_basis!(rule)
    bounded_integer!(rule['days'], 1, 365) if key == 'R09'
    bounded_integer!(rule['percent'], 1, 99) if key == 'R05'
    ids!(rule['critical_company_ids']) if key == 'R12'
    priority_targets!(rule['priority_ids']) if key == 'R12'
    inactivity!(rule.fetch('days')) if key == 'R13'
    words!(rule)
  end

  def self.priority_targets!(targets)
    raise ArgumentError, 'Explicit per-Unit priority target IDs required' unless targets.is_a?(Hash) && targets.all? do |key, id|
      unit_key?(key) && id.is_a?(Integer) && id.positive?
    end
  end

  def self.unit_key?(key)
    key.is_a?(String) && key.to_i.positive? && key.to_i.to_s == key
  end

  def self.required_priority_targets!(value)
    rule = value.dig('rules', 'R12')
    return unless rule['enabled']

    return if rule['priority_ids'].keys.sort == value['unit_ids'].map(&:to_s).sort && value['unit_ids'].any?

    raise ArgumentError, 'R12 requires an explicit high-priority target for every pilot Unit'
  end

  def self.validate_basis!(rule)
    raise ArgumentError, 'Explicit calendar or business basis required' if rule.key?('basis') && %w[calendar business].exclude?(rule['basis'])
  end

  def self.inactivity!(values)
    raise ArgumentError, 'Three ascending inactivity thresholds required' unless values.is_a?(Array) && values.size == 3 &&
                                                                                 values.uniq.sort == values &&
                                                                                 values.all? { |n| n.is_a?(Integer) && n.between?(1, 365) }
  end

  def self.words!(rule)
    rule.slice('keywords', 'phrases').each_value do |words|
      raise ArgumentError, 'Bounded nonempty keywords required' unless words.is_a?(Array) && words.size <= 100 &&
                                                                       words.all? { |word| word.is_a?(String) && word.size.between?(1, 100) }
    end
  end

  def self.daily!(value)
    raise ArgumentError, 'Explicit daily contract required' unless value.is_a?(Hash) && value.keys.sort == %w[channels enabled hour recipients
                                                                                                              timezone]

    boolean!(value['enabled'])
    bounded_integer!(value['hour'], 18, 18)
    ids!(value['recipients'])
    channels!(value['channels'])
    TZInfo::Timezone.get(value.fetch('timezone'))
  rescue TZInfo::InvalidTimezoneIdentifier
    raise ArgumentError, 'Valid explicit report timezone required'
  end
end
