class JrcRelationship::Configuration < ApplicationRecord
  self.table_name = 'jrc_relationship_configurations'
  belongs_to :account
  has_many :versions, class_name: 'JrcRelationship::ConfigurationVersion', dependent: :restrict_with_error

  def capture_version!(values, actor: nil)
    versions.create_or_find_by!(account_id: account_id, version: values.fetch('version')) do |row|
      row.weights = values.fetch('weights')
      row.rules = values.fetch('rules')
      row.actor = actor
    end
  end
  validates :scope_key, uniqueness: { scope: :account_id }, format: { with: /\A(account|segment:\d+|product:\d+|company:\d+|unit:\d+)\z/ }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validate :valid_config
  DEFAULT_WEIGHTS = { 'adoption' => 25, 'relationship' => 15, 'service_desk' => 15, 'finance' => 15,
                      'satisfaction' => 10, 'contract' => 10, 'projects' => 5, 'engagement' => 5, 'sentiment' => 0 }.freeze
  DEFAULT_RULES = { 'no_contact_days' => 30, 'renewal_days' => 120, 'risk_threshold' => 60, 'critical_threshold' => 40,
                    'survey_frequency_days' => 90, 'sla_hours' => 24, 'detractor_sla_hours' => 4, 'healthy_threshold' => 80, 'priority_health' => 0.4,
                    'priority_mrr' => 0.2, 'priority_renewal' => 0.2, 'priority_inactivity' => 0.2,
                    'mrr_priority_ceiling_cents' => 1_000_000, 'critical_priority_codes' => %w[P1 critical urgent],
                    'ticket_penalty' => 30, 'sla_penalty' => 20, 'overdue_finance_score' => 20,
                    'project_penalty' => 30, 'task_penalty' => 10, 'csat_threshold' => 3,
                    'critical_action_priority' => 90, 'ticket_action_priority' => 85, 'detractor_action_priority' => 80,
                    'health_drop_points' => 20, 'health_drop_action_priority' => 70,
                    'auto_handoff' => true, 'missing_factor_policy' => 'renormalize', 'survey_automation_enabled' => false,
                    'renewal_window_days' => [15, 30, 60, 90, 120],
                    'eligibility_mode' => 'legacy_order', 'handoff_acceptance_required' => false, 'playbook_flow_effects_enabled' => false,
                    'playbook_flow_policy' => JrcRelationship::PlaybookFlowPolicy::DEFAULTS,
                    'qbr_agenda_template' => "Objetivos e resultados\nSaúde e satisfação\nSuporte e financeiro\nRiscos e renovação\nPróximos passos",
                    'adoption_metric' => 'adoption', 'recurring_ticket_count' => 3, 'growth_threshold_percent' => 20, 'ces_threshold' => 6,
                    'survey_question_nps' => 'De 0 a 10, quanto você recomendaria nossa empresa?',
                    'survey_question_ces' => 'De 0 a 10, quanto foi fácil alcançar seu objetivo?',
                    'risk_reasons' => ['Baixa adoção', 'Insatisfação', 'Suporte recorrente', 'Financeiro', 'Renovação',
                                       'Cancelamento solicitado'] }.freeze

  BOOLEAN_VALUES = [true, false].freeze
  NON_NUMERIC_RULES = %w[auto_handoff survey_automation_enabled missing_factor_policy critical_priority_codes qbr_agenda_template adoption_metric
                         risk_reasons survey_question_nps survey_question_ces renewal_window_days eligibility_mode handoff_acceptance_required
                         playbook_flow_effects_enabled playbook_flow_policy].freeze

  def effective_weights
    DEFAULT_WEIGHTS.merge(weights)
  end

  def effective_rules
    values = DEFAULT_RULES.merge(rules)
    values['playbook_flow_policy'] = values['playbook_flow_policy'].deep_dup
    values
  end

  private

  def valid_config
    validate_weights
    unless rules.is_a?(Hash) && (rules.keys - DEFAULT_RULES.keys).empty?
      errors.add(:rules, 'unknown rules')
      return
    end
    validate_numeric_rules
    validate_risk_bands
    validate_rule_choices
    validate_flow_policy
    validate_renewal_windows
    validate_rule_lists
    validate_scope
  end

  def validate_weights
    values = weights.is_a?(Hash) ? effective_weights : {}
    return if values.keys.sort == DEFAULT_WEIGHTS.keys.sort && values.values.all? { |value| valid_weight?(value) } && weights_total_valid?(values)

    errors.add(:weights, 'active factor weights must total 100')
  end

  def valid_weight?(value)
    value.is_a?(Numeric) && value.finite? && value >= 0
  end

  def weights_total_valid?(values)
    (values.values.sum - 100).abs < 0.000001
  end

  def validate_numeric_rules
    effective_rules.each do |key, value|
      next if NON_NUMERIC_RULES.include?(key)

      errors.add(:rules, "#{key} must be positive") unless value.is_a?(Numeric) && value.finite? && value.positive?
    end
  end

  def validate_flow_policy
    JrcRelationship::PlaybookFlowPolicy.validate!(effective_rules['playbook_flow_policy'])
  rescue ArgumentError => e
    errors.add(:rules, e.message)
  end

  def validate_risk_bands
    critical = effective_rules['critical_threshold'].to_f
    risk = effective_rules['risk_threshold'].to_f
    healthy = effective_rules['healthy_threshold'].to_f
    errors.add(:rules, 'risk bands must be ordered') unless critical < risk && risk < healthy && healthy <= 100
  end

  def validate_rule_choices
    %w[auto_handoff survey_automation_enabled handoff_acceptance_required playbook_flow_effects_enabled].each do |key|
      errors.add(:rules, "#{key} must be boolean") unless BOOLEAN_VALUES.include?(effective_rules[key])
    end
    errors.add(:rules, 'invalid eligibility mode') unless %w[legacy_order active_contract_product].include?(effective_rules['eligibility_mode'])
    errors.add(:rules, 'invalid missing factor policy') unless %w[renormalize neutral block].include?(effective_rules['missing_factor_policy'])
  end

  def validate_renewal_windows
    windows = effective_rules['renewal_window_days']
    unless windows.is_a?(Array) && windows.size == 5 && windows.all? { |value| value.is_a?(Integer) && value.between?(1, 3650) } &&
           windows == windows.sort.uniq
      errors.add(:rules, 'renewal windows require five increasing integer day limits')
    end
  end

  def validate_rule_lists
    %w[qbr_agenda_template adoption_metric survey_question_nps survey_question_ces].each do |key|
      value = effective_rules[key]
      errors.add(:rules, "#{key} must be bounded text") unless value.is_a?(String) && value.length.between?(1, 4000)
    end
    validate_priority_codes
    validate_risk_reasons
  end

  def validate_priority_codes
    codes = effective_rules['critical_priority_codes']
    errors.add(:rules, 'priority codes must be a finite list') unless codes.is_a?(Array) && codes.size <= 30 && codes.all? do |code|
      code.is_a?(String) && code.length.between?(1, 60)
    end
  end

  def validate_risk_reasons
    reasons = effective_rules['risk_reasons']
    valid = reasons.is_a?(Array) && reasons.size <= 50 && reasons.uniq.size == reasons.size && reasons.all? do |reason|
      reason.is_a?(String) && reason.strip.length.between?(1, 120)
    end
    errors.add(:rules, 'risk reasons must be a finite list') unless valid
  end

  def validate_scope
    kind, id = scope_key.to_s.split(':')
    target = { 'segment' => JrcCustomers::Taxonomy, 'product' => JrcCrm::Product, 'company' => JrcCustomers::Company,
               'unit' => JrcCrm::BusinessUnit }[kind]
    scope = target&.where(account_id: account_id, id: id)
    scope = scope.where(kind: 'segment') if kind == 'segment' && scope
    errors.add(:scope_key, 'scope must belong to this account and kind') if scope && !scope.exists?
  end
end
