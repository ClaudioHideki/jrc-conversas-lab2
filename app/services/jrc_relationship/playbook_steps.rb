# Finite steps executed through existing CS/CRM workflows, never external sends.
class JrcRelationship::PlaybookSteps
  KINDS = %w[activity action meeting success_plan risk].freeze

  def self.valid?(steps)
    return false unless steps.is_a?(Array) && steps.size.between?(1, 50)
    keys = steps.each_with_index.map { |step, index| step.is_a?(Hash) ? step.fetch('step_key', index.to_s).to_s : index.to_s }
    return false unless keys.uniq.size == keys.size && keys.all? { |key| key.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) }
    steps.all? do |step|
      step.is_a?(Hash) && KINDS.include?(step['kind']) && step['title'].is_a?(String) &&
        step['title'].strip.length.between?(1, 250) &&
        step['after_days'].is_a?(Integer) && step['after_days'].between?(0, 365)
    end
  end

  def self.onboarding
    [
      { 'kind' => 'success_plan', 'title' => 'Plano de sucesso pós-go-live 30/60/90 dias', 'after_days' => 0 },
      { 'kind' => 'meeting', 'title' => 'Reunião de boas-vindas pós-go-live', 'after_days' => 0 },
      *[30, 60, 90].map { |days| { 'kind' => 'activity', 'title' => "Acompanhamento pós-go-live #{days} dias", 'after_days' => days } }
    ]
  end
end
