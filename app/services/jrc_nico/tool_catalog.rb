class JrcNico::ToolCatalog
  # Asterisk marks required fields. Unknown keys are rejected before execution.
  TOOLS = {
    'search_contacts' => ['Buscar contatos por nome, telefone ou email', 'contacts', false, %w[query*]],
    'list_contacts' => ['Listar ate 20 contatos cadastrados na conta', 'contacts', false, []],
    'count_contacts' => ['Contar contatos cadastrados na conta', 'contacts', false, []],
    'create_contact' => ['Cadastrar contato; informe telefone internacional ou email', 'contacts', true, %w[name* phone_number email]],
    'update_contact' => ['Atualizar dados de um contato identificado', 'contacts', true, %w[contact_id* name phone_number email]],
    'list_conversations' => ['Listar até 20 conversas visíveis recentes; filtrar por nome e status', 'conversations', false, %w[query status]],
    'conversation_opportunity_batch' => [
      'Ler lote de 10 conversas visíveis com evidências públicas para analisar oportunidades; ' \
      'todos os status por padrão, page inicia em 1', 'conversations', false, %w[
        page status
      ]
    ],
    'read_conversation' => ['Ler mensagens públicas e metadados da conversa', 'conversations', false, %w[conversation_id*]],
    'open_conversation' => ['Abrir uma conversa visível ao operador', 'conversations', false, %w[conversation_id*]],
    'analyze_conversation_sentiment' => [
      'Gerar relatório de sentimento e qualidade das mensagens públicas de uma conversa; usa o provedor desta conta',
      'conversations', false, %w[conversation_id*]
    ],
    'send_message' => ['Enviar mensagem ao cliente pelo canal da conversa; private=true cria nota interna', 'conversations', true,
                       %w[conversation_id* content* private]],
    'update_conversation' => ['Alterar status (open/resolved/pending/snoozed), prioridade, responsável, equipe ou etiquetas', 'conversations', true,
                              %w[conversation_id* status priority assignee_id team_id labels snoozed_until]],
    'list_team' => ['Consultar usuários e equipes disponíveis na conta', 'conversations', false, []],
    'search_knowledge' => ['Consultar orientações aprovadas na base de conhecimento interna', 'conversations', false, %w[query*]],
    'delegate_conversations' => ['NICO atende automaticamente estas conversas por até 8 horas; informe objetivo e permita CRM explicitamente', 'conversations', true,
                                 %w[conversation_ids* objective* hours allow_crm allowed_actions]],
    'take_over' => ['Interromper o NICO e devolver estas conversas ao operador', 'conversations', true, %w[conversation_ids*]],
    'list_leads' => ['Buscar leads visíveis por nome ou contato', 'crm', false, %w[query contact_id]],
    'create_lead' => ['Criar lead da conversa ou contato; sem esses vínculos informe nome', 'crm', true,
                      %w[name contact_id conversation_id company_name email phone notes]],
    'update_lead' => ['Atualizar lead (status new/in_contact/qualified/unqualified)', 'crm', true,
                      %w[lead_id* name company_name email phone notes status]],
    'convert_lead' => ['Converter lead em negócio usando funil e etapa válidos', 'crm', true, %w[lead_id* deal_title pipeline_id stage_id]],
    'list_deals' => ['Consultar negócios autorizados', 'crm', false, %w[query]],
    'list_pipelines' => ['Consultar funis e etapas', 'crm', false, []],
    'move_deal' => ['Mover negócio de etapa; perda requer lost_reason_id', 'crm', true, %w[deal_id* stage_id* lost_reason_id lost_reason_note]],
    'list_activities' => ['Consultar atividades do operador com datas e estados', 'crm', false, %w[lead_id deal_id]],
    'create_activity' => ['Agendar atividade vinculada a lead ou negócio; activity_type task/call/email/whatsapp/meeting/follow_up', 'crm', true,
                          %w[title* activity_type* due_at* lead_id deal_id description]],
    'update_activity' => ['Reagendar, alterar ou concluir atividade; status scheduled/completed/cancelled', 'crm', true,
                          %w[activity_id* title description due_at status]],
    'list_products' => ['Consultar catálogo interno e preços cadastrados', 'crm', false, %w[query]],
    'create_proposal' => ['Preparar proposta com itens do negócio e cálculos do JRC', 'crm', true, %w[deal_id*]],
    'list_proposals' => ['Consultar propostas autorizadas por título ou negócio', 'crm', false, %w[query deal_id]],
    'read_proposal' => ['Consultar o escopo, itens, quantidades, preços e aprovações de uma proposta antes de alterar ou adicionar produtos', 'crm',
                        false, %w[proposal_id*]],
    'list_campaigns' => ['Consultar campanhas e estados de aprovação', 'campaigns', false, []],
    'create_campaign' => ['Criar rascunho de campanha WhatsApp, sem disparar', 'campaigns', true, %w[name* inbox_id* message_body*]],
    'campaign_action' => ['Ação request_review/launch/pause/resume/cancel; lançamento exige aprovação prévia no módulo', 'campaigns', true,
                          %w[campaign_id* action*]],
    'campaign_report' => ['Consultar relatório de uma campanha', 'campaigns', false, %w[campaign_id*]],
    'operational_report' => ['Resumo com contagens de conversas visíveis e atividades; limitações informadas', 'conversations', false, []],
    'channel_status' => ['Consultar caixas, disponibilidade de ramal e videoconferência sem revelar credenciais', 'conversations', false, []],
    'account_profile' => ['Consultar nome, idioma, email de suporte e fuso da conta, sem credenciais', 'settings_admin', false, []],
    'set_reporting_timezone' => ['Configurar fuso horário IANA da conta para agenda e relatórios, como America/Sao_Paulo', 'settings_admin', true,
                                 %w[timezone*]],
    'call_contact' => ['Discar para contato pelo ramal do operador, no navegador; depende de registro e microfone', 'contacts', true,
                       %w[contact_id*]],
    'call_control' => ['Controlar chamada SIP atual: answer/reject/hangup/mute/unmute/hold/unhold/transfer', 'conversations', true,
                       %w[action* destination]],
    'open_video' => ['Abrir sala de videoconferência configurada para o operador', 'conversations', true, []],
    'open_module' => ['Navegar para um módulo existente usando route_name disponível no contexto', 'navigation', false, %w[route_name*]]
  }.merge(JrcNico::ModuleActions::TOOLS).merge(JrcNico::AutomationActions::TOOLS).merge(JrcNico::DomainToolCatalog::TOOLS)
          .merge(JrcNico::HelpdeskToolCatalog::TOOLS).freeze

  def initialize(access)
    @access = access
  end

  def available
    domain_access = nil
    domain_permissions = {}
    TOOLS.filter_map do |name, (description, group, mutation, fields)|
      next if name == 'delegate_conversations' && @access.account.custom_attributes['nico_customer_delegation_enabled'] != true
      next if group == 'automations' && !(@access.account.feature_enabled?('automations') && @access.policy(AutomationRule).create?)
      next if group == 'crm' && !@access.crm?
      next unless admin_tool_available?(group)
      next if group == 'campaigns' && !@access.campaigns?
      next if group == 'contacts' && !@access.policy(Contact).public_send(name == 'create_contact' ? :create? : :index?)
      next if group == 'service_desk_helpdesk' && !JrcNico::HelpdeskToolCatalog.available?(@access, name)

      if %w[service_desk projects projects_create relationship].include?(group)
        domain_access ||= JrcNico::DomainAccess.new(@access)
        next unless domain_permissions.fetch(group) { domain_permissions[group] = domain_access.available?(group) }
      end

      { name: name, description: description, confirmation: mutation, fields: fields }
    end
  end

  # Models sometimes include null for an optional field they do not need.
  # Omit those fields, while retaining required/unknown keys for validation.
  def normalize_arguments(name, arguments)
    return arguments unless arguments.is_a?(Hash)

    fields = available.find { |item| item[:name] == name }&.fetch(:fields) || []
    optional = fields.reject { |field| field.end_with?('*') }
    arguments.reject { |key, value| value.nil? && optional.include?(key) }
  end

  def validate!(name, arguments)
    definition = available.find { |item| item[:name] == name }
    raise Pundit::NotAuthorizedError unless definition
    raise ArgumentError, 'Parâmetros inválidos.' unless arguments.is_a?(Hash)

    fields = definition[:fields]
    raise ArgumentError, 'Campo não permitido.' if (arguments.keys - fields.map { |field| field.delete_suffix('*') }).any?

    fields.grep(/\*$/).each do |field|
      raise ArgumentError, "Informe #{field.delete_suffix('*')}." if arguments[field.delete_suffix('*')].blank?
    end
    if name == 'create_activity' && arguments['lead_id'].blank? && arguments['deal_id'].blank?
      raise ArgumentError, 'A atividade precisa de lead_id ou deal_id. Consulte os registros deste contato antes de agendar.'
    end

    raise ArgumentError, 'Escolha entre definir ou remover o responsavel/pai da tarefa.' if conflicting_project_assignment?(name, arguments)

    arguments.each do |key, value|
      extension_valid = extension_validity(name, key, value)
      unless extension_valid.nil?
        raise ArgumentError, "Valor inválido: #{key}." unless extension_valid

        next
      end
      valid = case key
              when 'conversation_ids' then value.is_a?(Array) && value.length.between?(1, 20) && value.all? { |id| id.is_a?(Integer) && id.positive? }
              when 'labels' then value.is_a?(Array) && value.length <= 20 && value.all? { |label| label.is_a?(String) && label.length <= 100 }
              when 'allowed_actions' then value.is_a?(Array) && value.length <= 5 && (value - JrcNico::DelegatedActions::GROUPS.keys).empty?
              when 'allow_crm', 'private', 'active', 'greeting_enabled', 'clear_assignee', 'clear_parent' then [true, false].include?(value)
              when 'estimated_minutes' then value.is_a?(Integer) && value >= 0
              when 'page' then value.is_a?(Integer) && value.between?(1, 20)
              when /_id$/, 'hours' then value.is_a?(Integer) && value.positive?
              when /_cents$/ then value.is_a?(Integer) && value >= 0
              when 'quantity' then value.is_a?(Numeric) && value.positive? && value <= 1_000_000
              else value.is_a?(String) && value.length <= 4000
              end
      raise ArgumentError, "Valor inválido: #{key}." unless valid
    end
    definition
  end

  private

  def admin_tool_available?(group)
    case group
    when 'crm_admin' then @access.crm? && @access.membership.administrator?
    when 'settings_admin' then @access.membership.administrator?
    else true
    end
  end

  def conflicting_project_assignment?(name, arguments)
    name == 'update_project_task' && ((arguments['clear_assignee'] && arguments['assignee_id']) ||
      (arguments['clear_parent'] && arguments['parent_id']))
  end

  def extension_validity(name, key, value)
    if JrcNico::HelpdeskToolCatalog::TOOLS.key?(name)
      valid = JrcNico::HelpdeskToolCatalog.valid_value?(key, value)
      return valid unless valid.nil?
    end
    return unless JrcNico::DomainToolCatalog::TOOLS.key?(name) || JrcNico::ModuleActions::PROJECT_TASK_TOOLS.include?(name)

    JrcNico::DomainToolCatalog.valid_value?(key, value)
  end
end
