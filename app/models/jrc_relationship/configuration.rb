class JrcRelationship::Configuration < ApplicationRecord
  self.table_name = 'jrc_relationship_configurations'
  belongs_to :account
  has_many :versions, class_name: 'JrcRelationship::ConfigurationVersion', foreign_key: :configuration_id, dependent: :restrict_with_error

  def capture_version!(values, actor: nil)
    versions.create_or_find_by!(account_id: account_id, version: values.fetch('version')) do |row|
      row.weights = values.fetch('weights')
      row.rules = values.fetch('rules')
      row.actor = actor
    end
  end
  validates :scope_key, uniqueness: { scope: :account_id }, format: { with: /\A(account|segment:\d+|product:\d+)\z/ }
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
                    'auto_handoff' => true,
                    'qbr_agenda_template' => "Objetivos e resultados\nSaúde e satisfação\nSuporte e financeiro\nRiscos e renovação\nPróximos passos",
                    'adoption_metric' => 'adoption', 'recurring_ticket_count' => 3, 'growth_threshold_percent' => 20, 'ces_threshold' => 6,
                    'survey_question_nps' => 'De 0 a 10, quanto você recomendaria nossa empresa?',
                    'survey_question_ces' => 'De 0 a 10, quanto foi fácil alcançar seu objetivo?',
                    'risk_reasons' => ['Baixa adoção', 'Insatisfação', 'Suporte recorrente', 'Financeiro', 'Renovação', 'Cancelamento solicitado'] }.freeze

  def effective_weights
    DEFAULT_WEIGHTS.merge(weights)
  end

  def effective_rules
    DEFAULT_RULES.merge(rules)
  end

  private

  def valid_config
    values = weights.is_a?(Hash) ? effective_weights : {}
    unless values.keys.sort == DEFAULT_WEIGHTS.keys.sort && values.values.all? { |v| v.is_a?(Numeric) && v.finite? && v >= 0 } && values.values.sum.positive?
      errors.add(:weights, 'must contain valid nonnegative factor weights')
    end
    unless rules.is_a?(Hash) && (rules.keys - DEFAULT_RULES.keys).empty?
      errors.add(:rules, 'unknown rules')
      return
    end
    effective_rules.each do |key, value|
      next if %w[auto_handoff critical_priority_codes qbr_agenda_template adoption_metric risk_reasons survey_question_nps survey_question_ces].include?(key)
      errors.add(:rules, "#{key} must be positive") unless value.is_a?(Numeric) && value.finite? && value.positive?
    end
    errors.add(:rules, 'risk bands must be ordered') unless effective_rules['critical_threshold'].to_f < effective_rules['risk_threshold'].to_f && effective_rules['risk_threshold'].to_f < effective_rules['healthy_threshold'].to_f && effective_rules['healthy_threshold'].to_f <= 100
    errors.add(:rules, 'auto_handoff must be boolean') unless [true, false].include?(effective_rules['auto_handoff'])
    codes = effective_rules['critical_priority_codes']
    %w[qbr_agenda_template adoption_metric survey_question_nps survey_question_ces].each do |key|
      value = effective_rules[key]
      errors.add(:rules, "#{key} must be bounded text") unless value.is_a?(String) && value.length.between?(1, 4000)
    end
    errors.add(:rules, 'priority codes must be a finite list') unless codes.is_a?(Array) && codes.size <= 30 && codes.all? { |code| code.is_a?(String) && code.length.between?(1, 60) }
    reasons = effective_rules['risk_reasons']
    errors.add(:rules, 'risk reasons must be a finite list') unless reasons.is_a?(Array) && reasons.size <= 50 &&
      reasons.uniq.size == reasons.size && reasons.all? { |reason| reason.is_a?(String) && reason.strip.length.between?(1, 120) }
    kind, id = scope_key.to_s.split(':')
    target = { 'segment' => JrcCustomers::Taxonomy, 'product' => JrcCrm::Product }[kind]
    scope = target&.where(account_id: account_id, id: id)
    scope = scope.where(kind: 'segment') if kind == 'segment' && scope
    errors.add(:scope_key, 'scope must belong to this account and kind') if scope && !scope.exists?
  end
end
