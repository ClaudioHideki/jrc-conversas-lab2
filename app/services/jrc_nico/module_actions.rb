class JrcNico::ModuleActions
  PROJECT_TASK_TOOLS = %w[create_project_task update_project_task].freeze
  # These operations deliberately use the existing authenticated module endpoints:
  # approval rules, item pricing, delivery checks and Enterprise overlays remain authoritative.
  TOOLS = {
    'create_product' => ['Cadastrar produto ou serviço no catálogo (administrador CRM)', 'crm_admin', true,
                         %w[name* unit_price_cents* description sku billing_model currency scope_included scope_excluded]],
    'update_product' => ['Atualizar produto ou serviço e sua disponibilidade (administrador CRM)', 'crm_admin', true,
                         %w[product_id* name unit_price_cents description sku billing_model currency active scope_included scope_excluded]],
    'create_project_task' => ['Criar tarefa pela tela autenticada de Projetos; execução única na aba, sem repetir automaticamente se o resultado for desconhecido', 'projects', true,
                              %w[project_id* title* description priority board_column_id assignee_id parent_id estimated_minutes starts_on due_on labels]],
    'update_project_task' => ['Editar tarefa pela tela autenticada usando lock_version consultado. Para concluir ou mudar estado, use move_project_task e uma coluna real', 'projects', true,
                              %w[project_id* task_id* lock_version* title description priority assignee_id parent_id estimated_minutes starts_on due_on labels clear_assignee clear_parent]],
    'update_inbox_settings' => ['Configurar nome, saudação e mensagem fora do expediente de uma caixa (administrador)', 'settings_admin', true,
                                %w[inbox_id* name greeting_enabled greeting_message out_of_office_message timezone]],
    'update_account_profile' => ['Atualizar nome, idioma e email de suporte da conta (administrador)', 'settings_admin', true,
                                 %w[name locale support_email]],
    'create_deal' => ['Criar negócio com funil e etapa existentes', 'crm', true, %w[title* pipeline_id* stage_id* contact_id value_cents description]],
    'update_deal' => ['Atualizar título, descrição, valor ou previsão do negócio', 'crm', true, %w[deal_id* title description value_cents expected_close_at]],
    'update_proposal' => ['Revisar proposta e recalcular pelas regras do CRM', 'crm', true, %w[proposal_id* title solution_description commercial_notes customer_notes valid_until discount_cents]],
    'add_proposal_item' => ['Adicionar produto cadastrado à proposta; preço e condições vêm do catálogo', 'crm', true, %w[proposal_id* product_id* quantity*]],
    'request_proposal_approval' => ['Solicitar aprovação interna da proposta', 'crm', true, %w[proposal_id*]],
    'approve_proposal' => ['Aprovar/reprovar proposta: approval_type commercial/financial/technical; decision approved/rejected', 'crm_admin', true,
                           %w[proposal_id* approval_type* decision*]],
    'send_proposal' => ['Enviar proposta pelos controles atuais de aprovação e canal (auto/email/whatsapp)', 'crm', true, %w[proposal_id* channel*]],
    'proposal_pdf' => ['Gerar e baixar PDF da proposta', 'crm', true, %w[proposal_id*]],
    'update_campaign' => ['Editar rascunho de campanha pelas regras de revisão atuais', 'campaigns', true, %w[campaign_id* name message_body inbox_id]],
    'approve_campaign' => ['Aprovar exatamente a revisão de campanha identificada pelo digest', 'campaigns', true, %w[campaign_id* digest*]],
    'export_campaign' => ['Baixar relatório CSV da campanha', 'campaigns', true, %w[campaign_id*]],
    'create_email' => ['Iniciar email para contato em caixa de email configurada', 'conversations', true, %w[contact_id* inbox_id* subject* content*]],
    'whatsapp_call' => ['Iniciar chamada WhatsApp nesta conversa; se necessário o canal solicitará permissão ao cliente', 'conversations', true, %w[conversation_id*]],
    'set_availability' => ['Alterar disponibilidade: online/offline/busy/meeting/feedback/end_shift/training/bathroom_break/lunch_break/manual_call', 'conversations', true, %w[availability*]]
  }.freeze

  def initialize(access)
    @access = access
  end

  def prepare(name, args)
    if PROJECT_TASK_TOOLS.include?(name)
      domain = JrcNico::DomainAccess.new(@access)
      project = domain.project(args.fetch('project_id'), capability: name == 'create_project_task' ? 'projects.task.create' : 'projects.task.update')
      domain.authorize_project!(project, 'projects.task.view')
      task = domain.task(project.id, args.fetch('task_id'), capability: 'projects.task.update') if name == 'update_project_task'
      resources = [['JrcProjects::Project', project.id], ['JrcNico::ProjectTasks', project.id]]
      resources << ['JrcProjects::Task', task.id] if task
      return { browser_action: 'module_action', operation: name, parameters: args, resources: resources,
               message: 'Tarefa revisada. A aba aplica as regras de Projetos uma vez; se o resultado ficar desconhecido, confira o projeto antes de preparar outro comando.' }
    end

    @access.crm_scope(JrcCrm::Deal).find(args['deal_id']) if args['deal_id']
    @access.crm_scope(JrcCrm::Proposal).find(args['proposal_id']) if args['proposal_id']
    @access.account.jrc_campaigns.find(args['campaign_id']) if args['campaign_id']
    products = @access.account.jrc_crm_products
    products = products.where(active: true) unless name == 'update_product'
    products.find(args['product_id']) if args['product_id']
    @access.account.jrc_crm_pipelines.find(args['pipeline_id']) if args['pipeline_id']
    @access.account.jrc_crm_stages.find(args['stage_id']) if args['stage_id']
    @access.contact(args['contact_id']) if args['contact_id']
    if args['inbox_id']
      inbox = @access.account.inboxes.find(args['inbox_id'])
      raise Pundit::NotAuthorizedError unless @access.inbox_visible?(inbox)
    end
    if name == 'create_email'
      raise ArgumentError, 'Selecione uma caixa de email configurada.' unless inbox.channel_type == 'Channel::Email'
      raise ArgumentError, 'O contato precisa de email cadastrado.' if @access.contact(args['contact_id']).email.blank?
    elsif name == 'whatsapp_call'
      conversation = @access.conversation(args['conversation_id'])
      unless conversation.inbox.channel_type == 'Channel::Whatsapp' && conversation.inbox.channel.voice_enabled?
        raise ArgumentError, 'WhatsApp Calling não está habilitado nesta caixa.'
      end
    elsif name == 'set_availability'
      raise ArgumentError, 'Disponibilidade inválida.' unless AccountUser.availabilities.key?(args['availability'])
    end
    { browser_action: 'module_action', operation: name, parameters: args,
      message: 'Ação revisada. Execute nesta aba para aplicar as regras do módulo e acompanhar o resultado.' }
  end
end
