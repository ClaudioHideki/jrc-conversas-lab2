# frozen_string_literal: true

class JrcServiceDesk::LifecycleRules
  ACTIONS = %w[pause resume resolve close cancel reopen work_status].freeze
  CLOCKS = %w[first_response resolution].freeze
  EFFECTS = %w[keep complete stop].freeze
  PHASES = %w[open waiting resolved closed cancelled].freeze
  attr_reader :definition

  def initialize(definition)
    @definition = JrcServiceDesk::Input.attributes(definition, %w[schema_version transitions pause_reasons reopen sla])
    validate!
  end

  def rule(key)
    definition.fetch('transitions').find { |item| item['key'] == key } || raise(ArgumentError, 'No configured transition')
  end

  def reason(code, status_id)
    definition.fetch('pause_reasons').find { |item| item['code'] == code && item['status_ids'].include?(status_id) } ||
      raise(ArgumentError, 'Pause reason is not configured for this status')
  end

  def reopen_check!(now:, anchor:)
    value = definition.fetch('reopen')
    raise ArgumentError, 'Reopening is not configured' unless value['allowed'] && anchor
    raise ArgumentError, 'Invalid reopening timestamp' if now < anchor
    if now - anchor > value.fetch('window_seconds')
      raise ArgumentError, value.fetch('expired') == 'require_new_ticket' ? 'Reopening expired; create a separate ticket through the normal authorized flow' : 'Reopening expired'
    end
    value
  end

  def validate_payload!(rule, payload, classified:)
    req = rule.fetch('requirements')
    %w[note solution].each do |key|
      val = payload[key]
      raise ArgumentError, "Invalid #{key}" unless val.nil? || (val.is_a?(String) && val.bytesize <= 20_000)
      raise ArgumentError, "Required #{key}" if req[key] && (val.nil? || val.strip.empty?)
    end
    ids = payload.fetch('evidence_note_ids', [])
    raise ArgumentError, 'Invalid evidence' unless ids.is_a?(Array) && ids.length <= 50 && ids.uniq == ids && ids.all? { |id| JrcServiceDesk::Input.id(id) == id }
    raise ArgumentError, 'Resolution evidence required' if req['evidence'] && ids.empty?
    raise ArgumentError, 'Classification required' if req['classification'] && !classified
    fields = payload.fetch('fields', {})
    raise ArgumentError, 'Invalid required fields' unless fields.is_a?(Hash) && (fields.keys - req['fields'].keys).empty?
    req['fields'].each do |key, spec|
      val = fields[key]
      raise ArgumentError, "Missing field #{key}" if spec['required'] && (val.nil? || (val.is_a?(String) && val.strip.empty?))
      next if val.nil?
      valid = case spec['type']
              when 'text' then val.is_a?(String) && val.bytesize <= 4000
              when 'integer' then val.is_a?(Integer) && val.abs <= 2**53 - 1
              when 'boolean' then [true, false].include?(val)
              end
      raise ArgumentError, "Invalid field #{key}" unless valid
      raise ArgumentError, "Required value for #{key}" if spec.key?('equals') && val != spec['equals']
    end
    true
  end

  private

  def exact(value, fields)
    data = JrcServiceDesk::Input.attributes(value, fields)
    raise ArgumentError, 'Incomplete explicit configuration' unless data.keys.sort == fields.sort
    data
  end

  def bool(value)
    raise ArgumentError, 'Boolean configuration required' unless [true, false].include?(value)
  end

  def token(value)
    raise ArgumentError, 'Invalid rule key' unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_.-]{1,80}\z/) && !%w[__proto__ constructor prototype].include?(value)
  end

  def validate!
    raise ArgumentError, 'Unsupported lifecycle format' unless definition['schema_version'] == 1
    exact(definition, %w[schema_version transitions pause_reasons reopen sla])
    sla = exact(definition['sla'], %w[mode initial_start])
    raise ArgumentError, 'Explicit SLA mode required' unless %w[not_applicable calendar_snapshot].include?(sla['mode']) && sla['initial_start'] == 'opened_at'
    rules = definition['transitions']
    raise ArgumentError, 'Transition list required' unless rules.is_a?(Array) && rules.length.between?(1, 100)
    rules.each { |rule| validate_rule(rule) }
    raise ArgumentError, 'Duplicate rule' unless rules.map { |r| r['key'] }.uniq.length == rules.length
    validate_reasons
    validate_reopening
    JrcServiceDesk::CanonicalJson.dump(definition)
  end

  def validate_rule(rule)
    r = exact(rule, %w[key action from_status_ids to_status_id requirements clocks end_pause])
    token(r['key'])
    raise ArgumentError, 'Unknown action' unless ACTIONS.include?(r['action'])
    ids = r['from_status_ids']
    raise ArgumentError, 'Source statuses required' unless ids.is_a?(Array) && ids.length.between?(1, 100) && ids.uniq == ids
    (ids + [r['to_status_id']]).each { |id| raise ArgumentError, 'Integer status IDs required' unless JrcServiceDesk::Input.id(id) == id }
    bool(r['end_pause'])
    req = exact(r['requirements'], %w[note solution evidence classification fields])
    %w[note solution evidence classification].each { |key| bool(req[key]) }
    raise ArgumentError, 'Field configuration required' unless req['fields'].is_a?(Hash) && req['fields'].size <= 30
    req['fields'].each do |key, field|
      token(key)
      f = JrcServiceDesk::Input.attributes(field, %w[label type required equals])
      raise ArgumentError unless (%w[label type required] - f.keys).empty?
      bool(f['required'])
      raise ArgumentError, 'Invalid field definition' unless %w[text integer boolean].include?(f['type']) && f['label'].is_a?(String) && f['label'].size.between?(1, 255)
    end
    req['fields'].each_value do |spec|
      next unless spec.key?('equals')
      value = spec['equals']
      valid = case spec['type']
              when 'text' then value.is_a?(String) && value.bytesize <= 4000
              when 'integer' then value.is_a?(Integer) && value.abs <= 2**53 - 1
              when 'boolean' then [true, false].include?(value)
              end
      raise ArgumentError, 'Invalid equality requirement' unless valid && spec['required']
    end
    clocks = exact(r['clocks'], CLOCKS)
    raise ArgumentError, 'Unknown clock effect' unless clocks.values.all? { |effect| EFFECTS.include?(effect) }
    # An internal transition is not evidence of an actual first public response.
    raise ArgumentError, 'First response needs an actual channel event' if clocks['first_response'] == 'complete'
    raise ArgumentError, 'Only resolution may complete its clock' if clocks['resolution'] == 'complete' && r['action'] != 'resolve'
    if definition['sla']['mode'] == 'not_applicable' && clocks.values.any? { |v| v != 'keep' }
      raise ArgumentError, 'Non-applicable SLA cannot mutate clocks'
    end
    if %w[pause resume reopen work_status].include?(r['action'])
      raise ArgumentError, 'Clock effect belongs to pause/reopen configuration' unless clocks.values.all? { |v| v == 'keep' }
    end
  end

  def validate_reasons
    reasons = definition['pause_reasons']
    raise ArgumentError, 'Pause reasons must be a list' unless reasons.is_a?(Array) && reasons.length <= 100
    reasons.each do |reason|
      r = exact(reason, %w[code name status_ids clocks]); token(r['code'])
      raise ArgumentError, 'Pause reason name required' unless r['name'].is_a?(String) && r['name'].size.between?(1, 255)
      raise ArgumentError, 'Pause statuses required' unless r['status_ids'].is_a?(Array) && r['status_ids'].any? && r['status_ids'].all? { |id| JrcServiceDesk::Input.id(id) == id }
      raise ArgumentError, 'Explicit clock list required' unless r['clocks'].is_a?(Array) && r['clocks'].uniq == r['clocks'] && (r['clocks'] - CLOCKS).empty?
      raise ArgumentError, 'Non-applicable SLA cannot pause clocks' if definition['sla']['mode'] == 'not_applicable' && r['clocks'].any?
    end
    raise ArgumentError, 'Duplicate pause reason' unless reasons.map { |r| r['code'] }.uniq.length == reasons.length
  end

  def validate_reopening
    r = exact(definition['reopen'], %w[allowed window_seconds anchor_action expired sla_cycle inactive_time resume_clocks new_cycle_snapshot])
    bool(r['allowed'])
    return unless r['allowed']
    raise ArgumentError, 'Explicit positive reopening window required' unless r['window_seconds'].is_a?(Integer) && r['window_seconds'].positive? && r['window_seconds'] <= 2**53 - 1
    raise ArgumentError, 'Explicit reopening rule required' unless %w[resolve close cancel].include?(r['anchor_action']) && %w[deny require_new_ticket].include?(r['expired'])
    raise ArgumentError, 'Explicit SLA cycle choice required' unless %w[continue_cycle new_cycle].include?(r['sla_cycle'])
    raise ArgumentError, 'Explicit inactive time rule required' unless %w[count exclude].include?(r['inactive_time'])
    raise ArgumentError, 'Explicit clock selection required' unless r['resume_clocks'].is_a?(Array) && (r['resume_clocks'] - CLOCKS).empty? && r['resume_clocks'].uniq == r['resume_clocks']
    raise ArgumentError, 'Explicit snapshot choice required' unless %w[same_snapshot latest_snapshot].include?(r['new_cycle_snapshot'])
  end
end
