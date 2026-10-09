# frozen_string_literal: true

# Closed transport contract. No class/table/column is resolved from a client name.
class JrcServiceDesk::ConfigurationContract
  FIELDS = {
    'queues' => %w[name code active team_id distribution_mode required_skills ola_budget_seconds ola_time_basis ola_pause_waiting
                   ola_escalation_policy],
    'categories' => %w[name code active parent_id form_fields], 'ticket_types' => %w[name code active form_fields],
    'priorities' => %w[name code active position], 'statuses' => %w[name code active phase position initial],
    'services' => %w[name code active description form_fields default_priority_id default_queue_id approval_required portal_enabled
                     portal_inbox_id portal_execution_membership_id default_category_id default_ticket_type_id default_assignee_membership_id
                     allowed_company_ids allowed_contract_ids portal_history_days portal_access_until]
  }.transform_values(&:freeze).freeze
  PHASES = %w[open waiting resolved closed cancelled].freeze
  VALIDATORS = {
    'name' => :text, 'code' => :text, 'active' => :boolean, 'initial' => :boolean, 'ola_pause_waiting' => :boolean,
    'approval_required' => :boolean, 'portal_enabled' => :boolean, 'phase' => :choice, 'position' => :position,
    'team_id' => :reference, 'default_priority_id' => :reference, 'default_queue_id' => :reference,
    'portal_inbox_id' => :reference, 'portal_execution_membership_id' => :reference, 'distribution_mode' => :choice,
    'required_skills' => :array, 'form_fields' => :array, 'ola_budget_seconds' => :budget, 'ola_time_basis' => :choice,
    'description' => :description,
    'parent_id' => :reference, 'default_category_id' => :reference, 'default_ticket_type_id' => :reference,
    'default_assignee_membership_id' => :reference, 'allowed_company_ids' => :ids, 'allowed_contract_ids' => :ids,
    'portal_history_days' => :budget, 'portal_access_until' => :timestamp, 'ola_escalation_policy' => :escalation_policy
  }.freeze
  CHOICES = { 'phase' => PHASES, 'distribution_mode' => %w[manual round_robin least_load skill priority_sla],
              'ola_time_basis' => %w[business calendar] }.transform_values(&:freeze).freeze

  def self.attributes(resource, value, create:)
    allowed = FIELDS.fetch(resource.to_s)
    allowed -= ['code'] unless create
    data = JrcServiceDesk::Input.attributes(value, allowed)
    raise ArgumentError, 'No configuration fields' if data.empty?

    raise ArgumentError, 'Explicit configuration required' if create && (required_fields(resource) - data.keys).any?

    # Dispatch only through this closed map; client keys cannot select an arbitrary method.
    data.each { |key, field| data[key] = send(VALIDATORS.fetch(key), key, field) }
    data
  end

  def self.required_fields(resource)
    required = %w[name code active]
    required += %w[position] if resource.to_s == 'priorities'
    required += %w[phase position initial] if resource.to_s == 'statuses'
    required
  end

  def self.revision(value)
    raise ArgumentError, 'Explicit revision required' unless value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)

    value
  end

  def self.text(key, value)
    limit = key == 'code' ? 80 : 255
    raise ArgumentError, 'Invalid text' unless value.is_a?(String) && !value.strip.empty? && value.length <= limit

    value
  end

  def self.boolean(_key, value)
    raise ArgumentError, 'Explicit boolean required' unless [true, false].include?(value)

    value
  end

  def self.choice(key, value)
    return value if key == 'ola_time_basis' && value.nil?
    return value if CHOICES.fetch(key).include?(value)

    raise ArgumentError, 'Unknown phase' if key == 'phase'

    raise ArgumentError
  end

  def self.position(_key, value)
    raise ArgumentError, 'Invalid position' unless value.is_a?(Integer) && value.between?(0, 2_147_483_647)

    value
  end

  def self.reference(_key, value)
    value.nil? ? nil : JrcServiceDesk::Input.id(value)
  end

  def self.array(_key, value)
    raise ArgumentError unless value.is_a?(Array)

    value
  end

  def self.budget(_key, value)
    raise ArgumentError unless value.nil? || (value.is_a?(Integer) && value.positive?)

    value
  end

  def self.description(_key, value)
    raise ArgumentError unless value.nil? || (value.is_a?(String) && value.size <= 20_000)

    value
  end

  def self.ids(_key, value)
    raise ArgumentError unless value.is_a?(Array) && value.size <= 100

    result = value.map { |id| JrcServiceDesk::Input.id(id) }
    raise ArgumentError unless result.uniq == result

    result
  end

  def self.timestamp(_key, value)
    return nil if value.nil?
    raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})\z/)

    Time.iso8601(value).utc.iso8601(6)
  rescue ArgumentError
    raise ArgumentError, 'Explicit ISO8601 date with timezone required'
  end

  def self.escalation_policy(_key, value)
    JrcServiceDesk::ClockEscalationPolicy.new(value).definition
  end

  private_class_method :required_fields, :text, :boolean, :choice, :position, :reference, :array, :budget,
                       :description, :ids, :timestamp, :escalation_policy
end
