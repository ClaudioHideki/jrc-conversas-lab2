# Finite steps executed through existing CS/CRM workflows, never external sends.
class JrcRelationship::PlaybookSteps
  KINDS = %w[activity action meeting success_plan risk flow].freeze
  FLOW_FIELDS = %w[flow_id flow_lock_version flow_digest conversation_id contact_id business_unit_id message_id].freeze

  def self.valid?(steps)
    return false unless steps.is_a?(Array) && steps.size.between?(1, 50)

    keys = steps.each_with_index.map { |step, index| step.is_a?(Hash) ? step.fetch('step_key', index.to_s).to_s : index.to_s }
    return false unless keys.uniq.size == keys.size && keys.all? { |key| key.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) }

    steps.all? { |step| valid_step?(step) }
  end

  def self.valid_step?(step)
    step.is_a?(Hash) && KINDS.include?(step['kind']) && valid_title?(step) &&
      valid_offset?(step) &&
      (step['kind'] != 'flow' || valid_flow?(step))
  end

  def self.valid_offset?(step)
    step['after_days'].is_a?(Integer) && step['after_days'].between?(0, 365)
  end

  def self.valid_title?(step)
    step['title'].is_a?(String) && step['title'].strip.length.between?(1, 250)
  end

  def self.valid_flow?(step)
    step['step_key'].is_a?(String) && step['step_key'].match?(/\A[a-zA-Z0-9_-]{1,64}\z/) &&
      valid_flow_ids?(step) &&
      valid_flow_pin?(step) && valid_flow_unit?(step) && valid_flow_message?(step) && step['after_days'].zero?
  end

  def self.valid_flow_ids?(step)
    %w[flow_id conversation_id contact_id].all? { |key| step[key].is_a?(Integer) && step[key].positive? }
  end

  def self.valid_flow_pin?(step)
    step['flow_lock_version'].is_a?(Integer) && step['flow_lock_version'] >= 0 &&
      step['flow_digest'].is_a?(String) && step['flow_digest'].match?(/\A[0-9a-f]{64}\z/)
  end

  def self.valid_flow_unit?(step)
    step['business_unit_id'].nil? || (step['business_unit_id'].is_a?(Integer) && step['business_unit_id'].positive?)
  end

  def self.valid_flow_message?(step)
    !step.key?('message_id') || (step['message_id'].is_a?(Integer) && step['message_id'].positive?)
  end

  def self.onboarding
    [
      { 'kind' => 'success_plan', 'title' => 'Plano de sucesso pós-go-live 30/60/90 dias', 'after_days' => 0 },
      { 'kind' => 'meeting', 'title' => 'Reunião de boas-vindas pós-go-live', 'after_days' => 0 },
      *[30, 60, 90].map { |days| { 'kind' => 'activity', 'title' => "Acompanhamento pós-go-live #{days} dias", 'after_days' => days } }
    ]
  end
end
