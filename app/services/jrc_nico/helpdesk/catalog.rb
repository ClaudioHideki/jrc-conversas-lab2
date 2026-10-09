class JrcNico::Helpdesk::Catalog
  GROUPS = {
    'A1' => ['Financeiro', 1, %w[billing.contract billing.invoice billing.secure_delivery], 'Financeiro'],
    'A2' => ['Senhas e acessos', 1, %w[identity.otp pabx.secure_reset], 'N1'],
    'A3' => ['Relatórios e gravações', 1, %w[reporter.query reporter.protected_link], 'N2'],
    'A4' => ['Ajustes de voz', 2, %w[pabx.ura pabx.approved_voice pabx.rollback], 'N1'],
    'B1' => ['Usuários e ramais', 2, %w[identity.admin pabx.plan_limit pabx.provision], 'N1'],
    'B2' => ['Softphone e IP Phone', 2, %w[pabx.device_registration], 'N2'],
    'C1' => ['Defeitos de voz', 3, %w[pabx.trunk_health pabx.safe_recovery], 'N2'],
    'C2' => ['WhatsApp e chat', 2, %w[broker.health broker.pair], 'N2'],
    'D1' => ['Classificação de tickets', 1, %w[service_desk.ticket service_desk.lifecycle], 'N1'],
    'D2' => ['Triagem humana', 1, %w[service_desk.ticket projects.task], 'Humano'],
    'E' => ['Base de conhecimento', 3, %w[knowledge.approved_search], 'N2']
  }.freeze
  AVAILABLE = %w[broker.health broker.pair service_desk.ticket service_desk.lifecycle projects.task knowledge.approved_search].freeze

  def self.call
    GROUPS.map do |key, (name, phase, required, handoff)|
      missing = required - AVAILABLE
      { key: key, name: name, phase: phase, required: required, capabilities: required.map { |capability| capability_status(capability) },
        status: missing.empty? ? 'available_with_native_authorization' : 'blocked_dependency', missing: missing,
        human_handoff: handoff, automatic_execution: false, identity_verification: 'required_for_customer_mutation' }
    end
  end

  def self.capability_status(key)
    { key: key, status: AVAILABLE.include?(key) ? 'native_permission_required' : 'missing_api_contract' }
  end
end
