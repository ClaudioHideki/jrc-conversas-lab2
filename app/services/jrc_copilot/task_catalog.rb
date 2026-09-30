module JrcCopilot
  class TaskCatalog
    DEFAULT_ROUTE = 'jrc_cockpit'.freeze

    ROUTE_GUIDES = {
      'automation_list' => {
        title: 'Automações Inteligentes',
        summary: 'Regras de atendimento: escolha um evento, condições e ações. A delegação temporária ao NICO não cria uma regra recorrente. Configure e acompanhe as regras nesta tela.',
        quick_prompts: ['Explique as automações desta tela', 'Como configurar uma regra de atendimento?'],
        actions: [{ label: 'Abrir Automações Inteligentes', route_name: 'automation_list', icon: 'i-lucide-workflow', tone: 'blue' }]
      },
      'jrc_cockpit' => {
        title: 'Cockpit',
        summary: 'Centraliza a operacao, mostra o que esta acontecendo agora e direciona o usuario para a acao necessaria.',
        quick_prompts: [
          'O que precisa da minha atencao agora?',
          'Organize meu dia por prioridade',
          'Quais agentes de IA encontraram alertas?'
        ],
        actions: [
          { label: 'Abrir Conversas', route_name: 'home', icon: 'i-lucide-messages-square', tone: 'blue' },
          { label: 'Abrir E-mails', route_name: 'jrc_email_center', icon: 'i-lucide-mail', tone: 'amber' },
          { label: 'Abrir Ligações', route_name: 'jrc_calls_center', icon: 'i-lucide-phone-call', tone: 'teal' }
        ]
      },
      'jrc_ai_agents' => {
        title: 'Central de Agentes IA',
        summary: 'Coordena especialistas de Prioridades, Atendimento, Qualidade, Retorno, Comercial, Agenda, SLA e Supervisao.',
        quick_prompts: [
          'Qual agente devo consultar?',
          'Analise as prioridades da operacao',
          'Organize as recomendacoes dos agentes'
        ],
        actions: [
          { label: 'Abrir Cockpit', route_name: 'jrc_cockpit', icon: 'i-lucide-gauge', tone: 'blue' },
          { label: 'Configurar IA', route_name: 'jrc_ai_providers', icon: 'i-lucide-key-round', tone: 'violet' }
        ]
      },
      'jrc_ai_insights' => {
        title: 'Insights de IA',
        summary: 'Transforma alertas operacionais, disciplina de retorno, qualidade e oportunidades em recomendacoes praticas.',
        quick_prompts: [
          'Quais insights tem maior impacto?',
          'O que devo resolver primeiro?',
          'Quais oportunidades comerciais existem?'
        ],
        actions: [
          { label: 'Abrir Cockpit', route_name: 'jrc_cockpit', icon: 'i-lucide-gauge', tone: 'blue' },
          { label: 'Central de Agentes IA', route_name: 'jrc_ai_agents', icon: 'i-lucide-bot', tone: 'violet' }
        ]
      },
      'jrc_ai_providers' => {
        title: 'Provedores de IA',
        summary: 'Cadastre credenciais no backend, escolha modelos, defina limites e acompanhe o consumo sem expor a chave no navegador.',
        quick_prompts: [
          'Como cadastrar uma API Key com seguranca?',
          'Como escolher o modelo padrao?',
          'Como acompanhar tokens e custo?'
        ],
        actions: [
          { label: 'Ver consumo', route_name: 'jrc_ai_usage', icon: 'i-lucide-gauge', tone: 'blue' },
          { label: 'Ver seguranca', route_name: 'jrc_ai_settings', icon: 'i-lucide-shield-check', tone: 'green' }
        ]
      },
      'jrc_service_center' => {
        title: 'Cockpit',
        summary: 'Rota de compatibilidade: Cockpit e Central de Atendimento sao o mesmo modulo operacional.',
        quick_prompts: [
          'O que precisa de atenção agora?',
          'Como localizar um atendimento sem responsável?',
          'Qual canal devo usar para responder o cliente?'
        ],
        actions: [
          { label: 'Abrir Conversas', route_name: 'home', icon: 'i-lucide-messages-square', tone: 'blue' },
          { label: 'Abrir E-mails', route_name: 'jrc_email_center', icon: 'i-lucide-mail', tone: 'amber' },
          { label: 'Abrir Ligações', route_name: 'jrc_calls_center', icon: 'i-lucide-phone-call', tone: 'teal' }
        ]
      },
      'home' => {
        title: 'Conversas',
        summary: 'Atenda mensagens, atribua responsáveis, registre contexto e vincule o atendimento ao CRM.',
        quick_prompts: [
          'Como organizar esta conversa?',
          'Como transformar uma conversa em lead?',
          'Como registrar a próxima ação do cliente?'
        ],
        actions: [
          { label: 'Abrir contatos', route_name: 'contacts_dashboard_index', icon: 'i-lucide-contact', tone: 'violet' },
          { label: 'Abrir leads', route_name: 'crm_leads', icon: 'i-lucide-user-round-plus', tone: 'blue' },
          { label: 'Criar atividade', route_name: 'crm_activities', icon: 'i-lucide-list-checks', tone: 'orange' }
        ]
      },
      'jrc_email_center' => {
        title: 'E-mails',
        summary: 'Trate as caixas de e-mail separadamente das conversas instantâneas e mantenha o histórico vinculado ao cliente.',
        quick_prompts: [
          'Como abrir uma caixa de e-mail?',
          'Como vincular um e-mail a um contato?',
          'Como transformar um e-mail em atividade?'
        ],
        actions: [
          { label: 'Ver contatos', route_name: 'contacts_dashboard_index', icon: 'i-lucide-contact', tone: 'violet' },
          { label: 'Ver atividades', route_name: 'crm_activities', icon: 'i-lucide-list-checks', tone: 'orange' }
        ]
      },
      'jrc_calls_center' => {
        title: 'Ligações',
        summary: 'Centralize Ramal, WhatsApp Calling, retornos e histórico de ligações.',
        quick_prompts: [
          'Como iniciar uma ligação?',
          'O que fazer quando o cliente não atende?',
          'Como registrar o resultado da chamada?'
        ],
        actions: [
          { label: 'WhatsApp Calling', route_name: 'whatsapp_calling_index', icon: 'i-ri-whatsapp-fill', tone: 'green' },
          { label: 'Abrir ramal', route_name: 'ramal_index', icon: 'i-lucide-phone', tone: 'blue' },
          { label: 'Agendar retorno', route_name: 'crm_calendar', icon: 'i-lucide-calendar-plus', tone: 'violet' }
        ]
      },
      'contacts_dashboard_index' => {
        title: 'Central de Relacionamentos',
        summary: 'Entenda quem é o contato, quais canais possui, o último relacionamento e a próxima ação recomendada.',
        quick_prompts: [
          'Como identificar contatos sem interação?',
          'Como abrir o histórico de um contato?',
          'Como vincular um contato a um negócio?'
        ],
        actions: [
          { label: 'Abrir leads', route_name: 'crm_leads', icon: 'i-lucide-user-round-plus', tone: 'blue' },
          { label: 'Abrir negócios', route_name: 'crm_deals', icon: 'i-lucide-handshake', tone: 'orange' }
        ]
      },
      'companies_dashboard_index' => {
        title: 'Empresas',
        summary: 'Organize organizações, pessoas vinculadas, canais, negócios ativos e histórico de relacionamento.',
        quick_prompts: [
          'Como cadastrar ou localizar uma empresa?',
          'Como vincular pessoas a uma empresa?',
          'Como consultar negócios relacionados?'
        ],
        actions: [
          { label: 'Abrir contatos', route_name: 'contacts_dashboard_index', icon: 'i-lucide-contact', tone: 'violet' },
          { label: 'Abrir negócios', route_name: 'crm_deals', icon: 'i-lucide-handshake', tone: 'orange' }
        ]
      },
      'crm_dashboard' => {
        title: 'Visão Geral do CRM',
        summary: 'Use os indicadores para decidir o que fazer hoje, o que está parado e o que pode fechar.',
        quick_prompts: [
          'Quais prioridades devo analisar primeiro?',
          'Como interpretar o pipeline?',
          'Como localizar negócios sem próxima ação?'
        ],
        actions: [
          { label: 'Abrir funil', route_name: 'crm_funnel', icon: 'i-lucide-columns-3', tone: 'violet' },
          { label: 'Minha carteira', route_name: 'crm_wallet', icon: 'i-lucide-briefcase-business', tone: 'blue' },
          { label: 'Ver atividades', route_name: 'crm_activities', icon: 'i-lucide-list-checks', tone: 'orange' }
        ]
      },
      'crm_indicators' => {
        title: 'Indicadores do CRM',
        summary: 'Analise conversão, origem, receita, desempenho e evolução do pipeline.',
        quick_prompts: [
          'Como analisar a conversão por etapa?',
          'Como comparar o desempenho dos vendedores?',
          'Como exportar os indicadores?'
        ],
        actions: [
          { label: 'Abrir visão geral', route_name: 'crm_dashboard', icon: 'i-lucide-layout-dashboard', tone: 'blue' },
          { label: 'Abrir funil', route_name: 'crm_funnel', icon: 'i-lucide-columns-3', tone: 'violet' }
        ]
      },
      'crm_leads' => {
        title: 'Leads',
        summary: 'Qualifique potenciais clientes, registre o próximo contato e converta oportunidades reais em negócios.',
        quick_prompts: [
          'Como cadastrar um novo lead?',
          'Como qualificar ou descartar um lead?',
          'Como converter um lead em negócio?'
        ],
        actions: [
          { label: 'Abrir negócios', route_name: 'crm_deals', icon: 'i-lucide-handshake', tone: 'orange' },
          { label: 'Agendar atividade', route_name: 'crm_activities', icon: 'i-lucide-calendar-plus', tone: 'violet' }
        ]
      },
      'crm_deals' => {
        title: 'Negócios',
        summary: 'Acompanhe valor, probabilidade, etapa, última interação e próxima ação de cada oportunidade.',
        quick_prompts: [
          'Como criar um novo negócio?',
          'Como adicionar produtos e valores?',
          'Como registrar a próxima atividade?'
        ],
        actions: [
          { label: 'Abrir funil', route_name: 'crm_funnel', icon: 'i-lucide-columns-3', tone: 'violet' },
          { label: 'Criar proposta', route_name: 'crm_proposals', icon: 'i-lucide-file-signature', tone: 'pink' },
          { label: 'Ver produtos', route_name: 'crm_products', icon: 'i-lucide-package', tone: 'green' }
        ]
      },
      'crm_funnel' => {
        title: 'Funil Comercial',
        summary: 'Movimente oportunidades entre etapas e elimine negócios sem responsável ou sem próxima ação.',
        quick_prompts: [
          'Como mover um negócio de etapa?',
          'Como configurar o funil?',
          'Como tratar negócios atrasados?'
        ],
        actions: [
          { label: 'Abrir negócios', route_name: 'crm_deals', icon: 'i-lucide-handshake', tone: 'orange' },
          { label: 'Minha carteira', route_name: 'crm_wallet', icon: 'i-lucide-briefcase-business', tone: 'blue' }
        ]
      },
      'crm_wallet' => {
        title: 'Minha Carteira',
        summary: 'Organize o dia do vendedor com negócios, leads, agenda, pendências e fechamentos previstos.',
        quick_prompts: [
          'O que devo fazer primeiro hoje?',
          'Como localizar negócios em risco?',
          'Como acompanhar minha meta?'
        ],
        actions: [
          { label: 'Abrir agenda', route_name: 'crm_calendar', icon: 'i-lucide-calendar-days', tone: 'violet' },
          { label: 'Abrir funil', route_name: 'crm_funnel', icon: 'i-lucide-columns-3', tone: 'blue' }
        ]
      },
      'crm_activities' => {
        title: 'Atividades',
        summary: 'Execute ligações, reuniões, WhatsApp e e-mails, mantendo status, prioridade e resultado atualizados.',
        quick_prompts: [
          'Como criar uma atividade?',
          'Como reagendar uma atividade?',
          'Como concluir e registrar o resultado?'
        ],
        actions: [
          { label: 'Abrir agenda', route_name: 'crm_calendar', icon: 'i-lucide-calendar-days', tone: 'violet' },
          { label: 'Abrir Ligações', route_name: 'jrc_calls_center', icon: 'i-lucide-phone-call', tone: 'teal' }
        ]
      },
      'crm_calendar' => {
        title: 'Agenda Comercial',
        summary: 'Planeje compromissos no tempo sem confundir a agenda com a fila operacional de atividades.',
        quick_prompts: [
          'Como criar um compromisso?',
          'Como reagendar sem perder o vínculo com o CRM?',
          'Como localizar compromissos atrasados?'
        ],
        actions: [
          { label: 'Ver atividades', route_name: 'crm_activities', icon: 'i-lucide-list-checks', tone: 'orange' },
          { label: 'Minha carteira', route_name: 'crm_wallet', icon: 'i-lucide-briefcase-business', tone: 'blue' }
        ]
      },
      'crm_products' => {
        title: 'Produtos e Serviços',
        summary: 'Cadastre produtos, serviços, licenças e projetos com cobrança, custos, recorrência e regras comerciais.',
        quick_prompts: [
          'Como cadastrar um serviço recorrente?',
          'Como configurar implantação e franquia?',
          'Como definir limite de desconto?'
        ],
        actions: [
          { label: 'Abrir propostas', route_name: 'crm_proposals', icon: 'i-lucide-file-signature', tone: 'pink' },
          { label: 'Abrir negócios', route_name: 'crm_deals', icon: 'i-lucide-handshake', tone: 'orange' }
        ]
      },
      'crm_proposals' => {
        title: 'Propostas',
        summary: 'Monte a proposta a partir dos produtos; implantação, recorrência, descontos e total inicial são calculados automaticamente.',
        quick_prompts: [
          'Como criar uma proposta completa?',
          'Como enviar por WhatsApp ou e-mail?',
          'Como acompanhar visualização e aceite?'
        ],
        actions: [
          { label: 'Ver produtos', route_name: 'crm_products', icon: 'i-lucide-package', tone: 'green' },
          { label: 'Abrir negócios', route_name: 'crm_deals', icon: 'i-lucide-handshake', tone: 'orange' }
        ]
      },
      'jrc_campaigns_index' => {
        title: 'Campanhas',
        summary: 'Prepare públicos, conteúdo e acompanhamento antes de iniciar qualquer disparo.',
        quick_prompts: [
          'Como criar uma campanha?',
          'O que preciso validar antes de iniciar?',
          'Como acompanhar resultados?'
        ],
        actions: [
          { label: 'Abrir contatos', route_name: 'contacts_dashboard_index', icon: 'i-lucide-contact', tone: 'violet' },
          { label: 'Abrir relatórios', route_name: 'account_overview_reports', icon: 'i-lucide-chart-spline', tone: 'blue' }
        ]
      },
      'whatsapp_calling_index' => {
        title: 'WhatsApp Calling',
        summary: 'Valide permissão, inicie a chamada e registre resultado, anotações e próxima ação.',
        quick_prompts: [
          'Como solicitar permissão para ligar?',
          'O que fazer se o cliente não atender?',
          'Como registrar um retorno?'
        ],
        actions: [
          { label: 'Agendar retorno', route_name: 'crm_calendar', icon: 'i-lucide-calendar-plus', tone: 'violet' },
          { label: 'Abrir contatos', route_name: 'contacts_dashboard_index', icon: 'i-lucide-contact', tone: 'blue' }
        ]
      },
      'ramal_index' => {
        title: 'Ramal JRC',
        summary: 'Use o softphone para ligar, transferir, pausar, usar teclado e registrar o atendimento.',
        quick_prompts: [
          'Como configurar meu ramal?',
          'Como transferir uma ligação?',
          'Como consultar o histórico?'
        ],
        actions: [
          { label: 'Abrir Ligações', route_name: 'jrc_calls_center', icon: 'i-lucide-phone-call', tone: 'teal' },
          { label: 'Agendar retorno', route_name: 'crm_calendar', icon: 'i-lucide-calendar-plus', tone: 'violet' }
        ]
      },
      'video_conference_index' => {
        title: 'Videoconferência',
        summary: 'Crie ou acesse reuniões por vídeo e registre o compromisso no contexto do cliente e do CRM.',
        quick_prompts: [
          'Como iniciar uma videoconferência?',
          'Como agendar uma reunião por vídeo?',
          'Como vincular a reunião a um negócio?'
        ],
        actions: [
          { label: 'Abrir agenda', route_name: 'crm_calendar', icon: 'i-lucide-calendar-days', tone: 'violet' },
          { label: 'Ver atividades', route_name: 'crm_activities', icon: 'i-lucide-list-checks', tone: 'orange' }
        ]
      },
      'account_overview_reports' => {
        title: 'Relatórios',
        summary: 'Acompanhe atendimento, produtividade, SLA e resultados comerciais antes de tomar decisões.',
        quick_prompts: [
          'Qual relatório devo consultar?',
          'Como analisar desempenho da equipe?',
          'Como exportar os dados?'
        ],
        actions: [
          { label: 'Abrir indicadores do CRM', route_name: 'crm_indicators', icon: 'i-lucide-chart-no-axes-combined', tone: 'blue' },
          { label: 'Abrir visão geral', route_name: 'crm_dashboard', icon: 'i-lucide-layout-dashboard', tone: 'violet' }
        ]
      },
      'general_settings_index' => {
        title: 'Configurações',
        summary: 'Configure canais, usuários, equipes, permissões e integrações sem alterar dados operacionais indevidamente.',
        quick_prompts: [
          'Onde configuro um canal?',
          'Como revisar usuários e permissões?',
          'O que devo validar antes de integrar um serviço?'
        ],
        actions: [
          { label: 'Configurar caixas de entrada', route_name: 'settings_inbox_list', icon: 'i-lucide-inbox', tone: 'blue' },
          { label: 'Configurar equipe', route_name: 'settings_teams_list', icon: 'i-lucide-users', tone: 'violet' }
        ]
      },
      'crm_orders' => {
        title: 'Pedidos', summary: 'Consulte pedidos ou crie um pedido a partir de uma proposta aceita. Revise os valores e vínculos antes de confirmar.',
        quick_prompts: ['Liste meus pedidos', 'Consulte um pedido', 'Crie um pedido da proposta aceita'],
        actions: [{ label: 'Abrir Pedidos', route_name: 'crm_orders', icon: 'i-lucide-shopping-cart', tone: 'blue' }]
      },
      'crm_contracts' => {
        title: 'Contratos', summary: 'Consulte contratos, vigências e estados de assinatura. Renovação, aditivo e registro de assinatura são realizados na tela do contrato.',
        quick_prompts: ['Liste meus contratos', 'Consulte a vigência de um contrato'],
        actions: [{ label: 'Abrir Contratos', route_name: 'crm_contracts', icon: 'i-lucide-file-text', tone: 'blue' }]
      },
      'crm_goals' => {
        title: 'Metas', summary: 'Administradores podem consultar metas e progresso pelo NICO. Criação, distribuição e publicação de metas ficam na tela de Metas.',
        quick_prompts: ['Consulte as metas e o progresso'],
        actions: [{ label: 'Abrir Metas', route_name: 'crm_goals', icon: 'i-lucide-target', tone: 'blue' }]
      },
      'crm_commissions' => {
        title: 'Comissões', summary: 'Consulte as comissões permitidas ao seu perfil. Liberação, pagamento, estorno e edição de programas exigem revisão na tela de Comissões.',
        quick_prompts: ['Liste minhas comissões'],
        actions: [{ label: 'Abrir Comissões', route_name: 'crm_commissions', icon: 'i-lucide-wallet', tone: 'blue' }]
      },
      'crm_backoffice' => {
        title: 'Backoffice', summary: 'Consulte etapa, estado e prazo das solicitações. Documentos, provisionamento e ações financeiras são tratados na tela de Backoffice.',
        quick_prompts: ['Liste minhas solicitações de backoffice'],
        actions: [{ label: 'Abrir Backoffice', route_name: 'crm_backoffice', icon: 'i-lucide-clipboard-list', tone: 'blue' }]
      },
      'crm_management' => {
        title: 'Equipe Comercial', summary: 'Acompanhe indicadores da equipe e seus responsáveis. O NICO orienta a navegação; a gestão comercial da equipe permanece nesta tela.',
        quick_prompts: ['Abra a equipe comercial'],
        actions: [{ label: 'Abrir Equipe Comercial', route_name: 'crm_management', icon: 'i-lucide-users', tone: 'blue' }]
      },
      'jrc_service_desk_tickets' => {
        title: 'Service Desk R2', summary: 'Consulte, crie e atualize chamados nas unidades autorizadas. Atribuições, notas e transições respeitam as permissões, versões e evidências exigidas pelo chamado.',
        quick_prompts: ['Liste meus chamados', 'Consulte minhas unidades de atendimento', 'Consulte as próximas ações deste chamado'],
        actions: [{ label: 'Abrir Chamados', route_name: 'jrc_service_desk_tickets', icon: 'i-lucide-ticket', tone: 'blue' }]
      },
      'jrc_projects_list' => {
        title: 'Projetos', summary: 'Consulte e crie projetos e tarefas, edite o planejamento e mova tarefas entre colunas. Criar ou editar tarefas usa a aba autenticada; revise a versão e as condições de conclusão antes de confirmar.',
        quick_prompts: ['Liste meus projetos', 'Consulte as tarefas do projeto', 'Crie uma tarefa no projeto'],
        actions: [{ label: 'Abrir Projetos', route_name: 'jrc_projects_list', icon: 'i-lucide-folder-kanban', tone: 'blue' }]
      },
      'jrc_operations_agenda' => {
        title: 'Minha Agenda', summary: 'Consolida compromissos do CRM e tarefas de Projetos conforme suas permissões. Prazos de tarefas mantêm a data original; chamados R2 ainda não fornecem tarefas para esta agenda.',
        quick_prompts: ['Consulte minha agenda de hoje', 'Quais compromissos estão atrasados?'],
        actions: [{ label: 'Abrir Minha Agenda', route_name: 'jrc_operations_agenda', icon: 'i-lucide-calendar-days', tone: 'blue' }]
      },
      'jrc_copilot_index' => {
        title: 'Copiloto JRC',
        summary: 'Descreva o objetivo; o Copiloto orienta o módulo, a sequência, as validações e a próxima ação segura.',
        quick_prompts: [
          'O que devo fazer primeiro hoje?',
          'Onde encontro uma função?',
          'Como concluir uma tarefa sem perder o histórico?'
        ],
        actions: [
          { label: 'Abrir Cockpit', route_name: 'jrc_cockpit', icon: 'i-lucide-gauge', tone: 'blue' },
          { label: 'Abrir CRM', route_name: 'crm_dashboard', icon: 'i-lucide-target', tone: 'violet' }
        ]
      }
    }.freeze

    INTENT_GUIDES = [
      {
        pattern: /\b(lead|leads|qualificar|prospec)/i,
        route_name: 'crm_leads',
        message: 'Abra Leads, localize ou crie o registro, confirme responsável e origem, registre a próxima ação e só converta quando houver oportunidade comercial real.'
      },
      {
        pattern: /\b(neg[oó]cio|oportunidade|pipeline|funil)/i,
        route_name: 'crm_deals',
        message: 'No negócio, confirme cliente, etapa, responsável, probabilidade, produtos e previsão de fechamento. Finalize registrando uma próxima atividade.'
      },
      {
        pattern: /\b(produto|servi[cç]o|licen[cç]a|projeto|stir|shaken|franquia)/i,
        route_name: 'crm_products',
        message: 'Cadastre o item no Catálogo, escolha o tipo e o modelo de cobrança, informe preço, custo, implantação, recorrência, franquia, excedente, vigência e limite de desconto. O cadastro permanece concentrado nas regras comerciais internas da JRC.'
      },
      {
        pattern: /\b(proposta|pdf|desconto|aceite|assinatura)/i,
        route_name: 'crm_proposals',
        message: 'Crie a proposta a partir do negócio, adicione os produtos e revise a composição automática: implantação, mensalidade, desconto, total do primeiro mês e recorrência. Depois valide destinatário, gere a prévia e envie.'
      },
      {
        pattern: /\b(agenda|atividade|reuni[aã]o|retorno|lembrete)/i,
        route_name: 'crm_activities',
        message: 'Use Atividades para executar e acompanhar tarefas; use Agenda para planejar no tempo. Mantenha tipo, responsável, data, prioridade, vínculo e resultado atualizados.'
      },
      {
        pattern: /\b(e-?mail|correio|caixa postal)/i,
        route_name: 'jrc_email_center',
        message: 'Abra o módulo E-mails, escolha uma caixa configurada e trate a mensagem dentro do histórico do cliente. Vincule contato, negócio ou atividade quando houver ação comercial.'
      },
      {
        pattern: /\b(liga[cç][aã]o|chamada|ramal|whatsapp calling|telefone)/i,
        route_name: 'jrc_calls_center',
        message: 'Abra Ligações, escolha Ramal ou WhatsApp Calling, valide número e permissão, realize a ligação e registre resultado, anotação e próxima ação.'
      },
      {
        pattern: /\b(v[ií]deo|videoconfer[eê]ncia|reuni[aã]o online)/i,
        route_name: 'video_conference_index',
        message: 'Abra Videoconferência, confirme participantes e horário e registre o compromisso na Agenda ou nas Atividades para manter o histórico vinculado.'
      },
      {
        pattern: /\b(relat[oó]rio|indicador|desempenho|sla|m[eé]trica)/i,
        route_name: 'account_overview_reports',
        message: 'Abra Relatórios ou Indicadores, escolha período e equipe, confira filtros e compare os resultados antes de exportar ou tomar uma decisão.'
      },
      {
        pattern: /\b(agente ia|agentes ia|copiloto|token|api key|modelo de ia|provedor de ia)/i,
        route_name: 'jrc_ai_agents',
        message: 'Use o Copiloto como interface com o usuario e os Agentes IA como especialistas. Para credenciais e modelos, um administrador deve abrir Inteligencia Artificial; a chave fica criptografada no backend e nunca deve ser exposta no frontend.'
      },
      {
        pattern: /\b(configura[cç][aã]o|permiss[aã]o|usu[aá]rio|equipe|canal)/i,
        route_name: 'general_settings_index',
        message: 'Abra Configurações, escolha o módulo correto e revise impacto, permissões e credenciais antes de salvar alterações estruturais.'
      },
      {
        pattern: /\b(conversa|atendimento|mensagem|whatsapp)/i,
        route_name: 'home',
        message: 'Abra Conversas, confirme o contato e o responsável, responda pelo canal correto e registre o próximo passo. Quando houver potencial comercial, crie ou vincule um lead/negócio.'
      }
    ].freeze

    class << self
      def context(route_name)
        guide = ROUTE_GUIDES[route_name.to_s] || ROUTE_GUIDES[DEFAULT_ROUTE]
        deep_dup(guide)
      end

      def fallback_answer(message:, route_name:)
        guide = context(route_name)
        intent = INTENT_GUIDES.find { |item| message.to_s.match?(item[:pattern]) }
        return guide.merge(message: default_message(guide), mode: 'guide') unless intent

        actions = guide[:actions].dup
        route_guide = context(intent[:route_name])
        actions.unshift(route_guide[:actions].first) if route_guide[:actions].first
        actions.unshift(
          label: "Abrir #{route_guide[:title]}",
          route_name: intent[:route_name],
          icon: 'i-lucide-arrow-up-right',
          tone: 'blue'
        )

        guide.merge(
          message: intent[:message],
          mode: 'guide',
          actions: actions.uniq { |action| [action[:label], action[:route_name]] }.first(4)
        )
      end

      def system_context(route_name)
        guide = context(route_name)
        <<~TEXT
          Tela atual: #{guide[:title]}.
          Objetivo da tela: #{guide[:summary]}
          Ações disponíveis: #{guide[:actions].map { |action| action[:label] }.join(', ')}.
        TEXT
      end

      private

      def default_message(guide)
        "Estou acompanhando a tela #{guide[:title]}. #{guide[:summary]} Escolha uma sugestão abaixo ou descreva o que precisa fazer."
      end

      def deep_dup(value)
        Marshal.load(Marshal.dump(value))
      end
    end
  end
end
