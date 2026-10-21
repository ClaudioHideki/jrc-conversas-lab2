import { localizeVisualScreen } from './localizeVisualScreen';

const metric = (label, value, detail, icon, tone = 'blue', trend = '') => ({
  label,
  value,
  detail,
  icon,
  tone,
  trend,
});

const action = (label, icon, tone = 'primary', routeName = null) => ({
  label,
  icon,
  tone,
  routeName,
});

export const contactCenterVisualCatalog = {
  cockpit: {
    key: 'cockpit',
    eyebrow: 'Atendimento conectado',
    title: 'Cockpit do atendente',
    description:
      'Fila, agenda, chamadas e contexto do cliente em uma única área de trabalho.',
    icon: 'i-lucide-headphones',
    accent: 'blue',
    status: { label: 'Operação assistida', tone: 'emerald' },
    metrics: [
      metric(
        'Atendimentos hoje',
        '24',
        '8 por voz e 16 digitais',
        'i-lucide-messages-square',
        'blue',
        '+12%'
      ),
      metric(
        'Próximas ações',
        '6',
        '2 retornos prioritários',
        'i-lucide-list-checks',
        'violet'
      ),
      metric(
        'Tempo médio',
        '04:32',
        'Atendimento + ACW medidos',
        'i-lucide-timer',
        'teal',
        '-18s'
      ),
      metric(
        'Satisfação',
        '4,7/5',
        'Últimas respostas válidas',
        'i-lucide-smile-plus',
        'amber'
      ),
    ],
    primary: {
      title: 'Fila e minha agenda',
      subtitle: 'Prioridades do turno atual',
      items: [
        {
          title: 'Em atendimento · Ótica Visão Center',
          description: 'SAC Nacional · Pedido #78456',
          meta: '03:12',
          status: 'Em chamada',
          tone: 'emerald',
          icon: 'i-lucide-phone-call',
        },
        {
          title: 'Callback · Ótica Novo Olhar',
          description: 'Confirmar previsão de entrega',
          meta: '10:30',
          status: 'Agendado',
          tone: 'blue',
          icon: 'i-lucide-calendar-clock',
        },
        {
          title: 'Ocorrência · Prime Vision',
          description: 'Divergência de montagem',
          meta: '11:15',
          status: 'Prioridade alta',
          tone: 'ruby',
          icon: 'i-lucide-triangle-alert',
        },
        {
          title: 'Retorno comercial · Ótica Central',
          description: 'Oportunidade em acompanhamento',
          meta: '14:00',
          status: 'CRM',
          tone: 'violet',
          icon: 'i-lucide-handshake',
        },
      ],
    },
    secondary: {
      title: 'Próxima ação',
      items: [
        {
          title: 'Retomar pedido #78456',
          description: 'Cliente aguarda confirmação de montagem',
          icon: 'i-lucide-package-search',
        },
        {
          title: 'Finalizar tabulação',
          description: 'Motivo e desfecho obrigatórios',
          icon: 'i-lucide-clipboard-check',
        },
        {
          title: 'Novo negócio',
          description: 'Registrar oportunidade no CRM',
          icon: 'i-lucide-sparkles',
        },
      ],
    },
    actions: [
      action('Nova ligação', 'i-lucide-phone-outgoing'),
      action('Nova ocorrência', 'i-lucide-clipboard-plus', 'secondary'),
      action('Agendar retorno', 'i-lucide-calendar-plus', 'secondary'),
    ],
  },
  call: {
    key: 'call',
    eyebrow: 'Ligação em andamento',
    title: 'Chamada em atendimento',
    description:
      'Telefonia, jornada da URA, qualificação e Cliente 360° permanecem visíveis durante toda a interação.',
    icon: 'i-lucide-phone-call',
    accent: 'teal',
    status: { label: '00:03:12', tone: 'emerald' },
    metrics: [
      metric(
        'Chamada atual',
        '03:12',
        'Inbound · SAC Nacional',
        'i-lucide-audio-lines',
        'teal'
      ),
      metric(
        'Fila',
        'SAC',
        'Posição atendida: 1',
        'i-lucide-headphones',
        'blue'
      ),
      metric(
        'Pedido',
        '#78456',
        'Status: em montagem',
        'i-lucide-package-check',
        'violet'
      ),
      metric(
        'Cliente',
        'Visão Center',
        'Ótica parceira HOYA',
        'i-lucide-building-2',
        'amber'
      ),
    ],
    primary: {
      title: 'Jornada integrada da chamada',
      subtitle: 'Uma CallSession com contexto preservado',
      items: [
        {
          title: 'Entrada 0800',
          description: 'ANI reconhecido e normalizado',
          meta: '10:13:18',
          status: 'Concluído',
          tone: 'emerald',
          icon: 'i-lucide-log-in',
        },
        {
          title: 'URA · Consulta de pedidos',
          description: 'Opção selecionada e pedido informado',
          meta: '10:13:42',
          status: 'Contexto recebido',
          tone: 'blue',
          icon: 'i-lucide-git-branch',
        },
        {
          title: 'Fila SAC Nacional',
          description: 'Oferta confirmada para Carla Mendes',
          meta: '10:14:05',
          status: 'Atendida',
          tone: 'emerald',
          icon: 'i-lucide-users',
        },
        {
          title: 'Atendimento em andamento',
          description: 'Qualificação e anotações sincronizadas',
          meta: 'Agora',
          status: 'Ao vivo',
          tone: 'ruby',
          icon: 'i-lucide-radio',
        },
      ],
    },
    secondary: {
      title: 'Cliente 360°',
      items: [
        {
          title: 'Carla Mendes',
          description: 'Compras / Administrativo',
          icon: 'i-lucide-user-round',
        },
        {
          title: 'Pedido #78456',
          description: 'Lentes progressivas · Em montagem',
          icon: 'i-lucide-package',
        },
        {
          title: 'Histórico preservado',
          description: '5 pedidos e 8 interações recentes',
          icon: 'i-lucide-history',
        },
      ],
    },
    actions: [
      action('Pausar', 'i-lucide-pause'),
      action('Transferir', 'i-lucide-forward', 'secondary'),
      action('Conferência', 'i-lucide-users-round', 'secondary'),
      action('Encerrar', 'i-lucide-phone-off', 'danger'),
    ],
  },
  afterCall: {
    key: 'afterCall',
    eyebrow: 'Pós-atendimento',
    title: 'Tabulação e encerramento',
    description:
      'O agente conclui motivo, resultado, próximos passos e pesquisa elegível sem perder o histórico da chamada.',
    icon: 'i-lucide-clipboard-check',
    accent: 'violet',
    status: { label: 'ACW 00:42', tone: 'amber' },
    metrics: [
      metric(
        'Tempo em ACW',
        '00:42',
        'Política local de demonstração',
        'i-lucide-timer-reset',
        'amber'
      ),
      metric(
        'Pesquisa',
        'Pendente',
        'Regra por canal ainda não publicada',
        'i-lucide-message-circle-question',
        'violet'
      ),
      metric(
        'Callback',
        'Elegível',
        'Janela sugerida: amanhã',
        'i-lucide-calendar-clock',
        'blue'
      ),
      metric(
        'Ocorrência',
        'JRC-2026-1842',
        'Protocolo gerado',
        'i-lucide-hash',
        'teal'
      ),
    ],
    primary: {
      title: 'Qualificação obrigatória',
      subtitle: 'Dados de encerramento preservados na timeline',
      items: [
        {
          title: 'Motivo do contato',
          description: 'Acompanhamento de pedido',
          status: 'Preenchido',
          tone: 'emerald',
          icon: 'i-lucide-tags',
        },
        {
          title: 'Categoria e subcategoria',
          description: 'Pedidos · Status de entrega',
          status: 'Preenchido',
          tone: 'emerald',
          icon: 'i-lucide-list-tree',
        },
        {
          title: 'Resultado',
          description: 'Orientação fornecida e retorno programado',
          status: 'Pendente de salvar',
          tone: 'amber',
          icon: 'i-lucide-check-circle-2',
        },
        {
          title: 'Observação',
          description: 'Cliente aguarda confirmação da montagem',
          status: 'Registrada',
          tone: 'blue',
          icon: 'i-lucide-notebook-pen',
        },
      ],
    },
    secondary: {
      title: 'Encerramento',
      items: [
        {
          title: 'Resumo automático',
          description: 'Revisão humana antes de salvar',
          icon: 'i-lucide-sparkles',
        },
        {
          title: 'Pesquisa pós-chamada',
          description: 'Somente se houver regra ativa',
          icon: 'i-lucide-star',
        },
        {
          title: 'Liberar agente',
          description: 'Após concluir a tabulação',
          icon: 'i-lucide-user-check',
        },
      ],
    },
    actions: [
      action('Salvar tabulação', 'i-lucide-save'),
      action('Agendar callback', 'i-lucide-calendar-plus', 'secondary'),
    ],
  },
  supervisor: {
    key: 'supervisor',
    eyebrow: 'Operação em tempo real',
    title: 'Supervisor do SAC',
    description:
      'Filas, agentes, estados, alertas e indicadores do escopo autorizado em uma visão executiva.',
    icon: 'i-lucide-monitor-dot',
    accent: 'blue',
    status: { label: 'Atualizado agora', tone: 'emerald' },
    metrics: [
      metric(
        'Agentes',
        '30',
        '21 disponíveis · 7 em chamada',
        'i-lucide-users-round',
        'blue'
      ),
      metric(
        'Chamadas aguardando',
        '4',
        'Maior espera: 01:42',
        'i-lucide-phone-incoming',
        'amber'
      ),
      metric(
        'SLA indicativo',
        '91,2%',
        'Fórmula oficial ainda pendente',
        'i-lucide-gauge',
        'teal',
        '+1,8%'
      ),
      metric(
        'Abandono',
        '2,8%',
        'Base demonstrativa',
        'i-lucide-phone-missed',
        'ruby'
      ),
    ],
    primary: {
      title: 'Painel de filas e agentes',
      subtitle: 'Drilldown por unidade, fila e estado',
      items: [
        {
          title: 'SAC Nacional',
          description: '4 aguardando · 7 em atendimento',
          meta: 'SLA 91,2%',
          status: 'Operação normal',
          tone: 'emerald',
          icon: 'i-lucide-headphones',
        },
        {
          title: 'Financeiro',
          description: '1 aguardando · 3 em atendimento',
          meta: 'TME 00:48',
          status: 'Acesso restrito',
          tone: 'violet',
          icon: 'i-lucide-landmark',
        },
        {
          title: 'COE Sudeste',
          description: '2 agentes disponíveis',
          meta: 'Sem fila',
          status: 'Disponível',
          tone: 'blue',
          icon: 'i-lucide-map-pinned',
        },
        {
          title: 'Carla Mendes',
          description: 'Em chamada · 04:32',
          meta: 'SAC',
          status: 'Em atendimento',
          tone: 'teal',
          icon: 'i-lucide-user-round-check',
        },
      ],
    },
    secondary: {
      title: 'Ações de supervisor',
      items: [
        {
          title: 'Visualizar agente',
          description: 'Abrir jornada e estado atual',
          icon: 'i-lucide-user-search',
        },
        {
          title: 'Acompanhar chamada',
          description: 'Somente leitura no piloto',
          icon: 'i-lucide-eye',
        },
        {
          title: 'Escalonar alerta',
          description: 'Registrar severidade e responsável',
          icon: 'i-lucide-siren',
        },
      ],
    },
    chart: [38, 52, 47, 66, 72, 58, 81, 76, 91, 84, 88, 93],
  },
  controlDesk: {
    key: 'controlDesk',
    eyebrow: 'NOC Contact Center',
    title: 'Control Desk Nacional',
    description:
      'Saúde do JRC PABX, eventos, comandos, integrações e contingências em visão centralizada.',
    icon: 'i-lucide-radar',
    accent: 'ruby',
    status: { label: '1 alerta relevante', tone: 'amber' },
    metrics: [
      metric(
        'COEs monitorados',
        '20',
        'Cobertura nacional prevista',
        'i-lucide-map',
        'blue'
      ),
      metric(
        'Filas',
        '4',
        'SAC, Financeiro e regionais',
        'i-lucide-layers-3',
        'violet'
      ),
      metric(
        'Alertas',
        '2',
        '1 informativo · 1 pendente',
        'i-lucide-triangle-alert',
        'amber'
      ),
      metric(
        'Eventos processados',
        '99,8%',
        'Reentregas deduplicadas',
        'i-lucide-webhook',
        'teal'
      ),
    ],
    primary: {
      title: 'Mapa operacional nacional',
      subtitle: 'Sinais correlacionados por componente',
      items: [
        {
          title: 'JRC PABX',
          description: 'Contrato pendente · monitor local saudável',
          meta: 'Latência 42 ms',
          status: 'Parcial',
          tone: 'amber',
          icon: 'i-lucide-server-cog',
        },
        {
          title: 'Inbox de eventos',
          description: 'Sem backlog relevante',
          meta: '2.184 eventos',
          status: 'Saudável',
          tone: 'emerald',
          icon: 'i-lucide-inbox',
        },
        {
          title: 'Comandos assíncronos',
          description: 'Nenhum estado unknown aberto',
          meta: '12 confirmados',
          status: 'Saudável',
          tone: 'emerald',
          icon: 'i-lucide-terminal',
        },
        {
          title: 'ERP HOYA',
          description: 'Contrato de integração ainda não homologado',
          meta: 'Sem tráfego real',
          status: 'Pendente',
          tone: 'violet',
          icon: 'i-lucide-database-zap',
        },
        {
          title: 'COE Rio de Janeiro',
          description: 'Exemplo de capacidade abaixo do alvo',
          meta: '2 agentes',
          status: 'Atenção',
          tone: 'ruby',
          icon: 'i-lucide-triangle-alert',
        },
      ],
    },
    secondary: {
      title: 'Saúde e contingência',
      items: [
        {
          title: 'Operação do SAC monitorada',
          description: 'Sem desvio automático não confirmado',
          icon: 'i-lucide-shield-check',
        },
        {
          title: 'Alertas com responsável',
          description: 'Severidade, período e reconhecimento',
          icon: 'i-lucide-bell-ring',
        },
        {
          title: 'Reprocessamento auditado',
          description: 'Apenas eventos verificados',
          icon: 'i-lucide-refresh-cw',
        },
      ],
    },
  },
  ivrBuilder: {
    key: 'ivrBuilder',
    eyebrow: 'Telefonia e automação',
    title: 'Construtor de URA',
    description:
      'Editor visual versionado para desenhar menus, saídas humanas e integrações futuras sem publicar rotas não homologadas.',
    icon: 'i-lucide-git-branch',
    accent: 'violet',
    status: { label: 'Rascunho v1.0', tone: 'violet' },
    metrics: [
      metric(
        'Árvore',
        'v1.0',
        'Rascunho não publicado',
        'i-lucide-git-fork',
        'violet'
      ),
      metric('Menus', '6', 'Opções conceituais', 'i-lucide-list-tree', 'blue'),
      metric(
        'Testes',
        '12',
        'Cenários de dry-run',
        'i-lucide-flask-conical',
        'teal'
      ),
      metric(
        'Publicação',
        'Pendente',
        'Exige aprovação formal',
        'i-lucide-shield-alert',
        'amber'
      ),
    ],
    flow: [
      {
        title: 'Entrada 0800',
        detail: 'Saudação vigente',
        icon: 'i-lucide-phone-incoming',
        tone: 'blue',
      },
      {
        title: 'Menu principal',
        detail: 'Teclas a confirmar',
        icon: 'i-lucide-list-tree',
        tone: 'violet',
      },
      {
        title: 'Pedidos',
        detail: 'ERP / saída humana',
        icon: 'i-lucide-package-search',
        tone: 'teal',
      },
      {
        title: 'SAC Nacional',
        detail: 'Fila humana',
        icon: 'i-lucide-headphones',
        tone: 'emerald',
      },
      {
        title: 'Financeiro',
        detail: 'Autenticação obrigatória',
        icon: 'i-lucide-landmark',
        tone: 'amber',
      },
      {
        title: 'Montagem / COE',
        detail: 'DDD + exceção',
        icon: 'i-lucide-map-pinned',
        tone: 'ruby',
      },
    ],
    primary: {
      title: 'Editor da árvore da URA',
      subtitle: 'Estrutura demonstrativa, não publicada',
      items: [
        {
          title: 'Entrada',
          description: 'Saudação · idioma · horário · timeout',
          status: 'Configurável',
          tone: 'blue',
          icon: 'i-lucide-circle-play',
        },
        {
          title: 'Menu de pedidos',
          description: 'Submenu 1/2 continua pendente de definição',
          status: 'Bloqueado',
          tone: 'amber',
          icon: 'i-lucide-package-search',
        },
        {
          title: 'SAC Nacional',
          description: 'Saída humana sempre acessível',
          status: 'Pronto para contrato',
          tone: 'emerald',
          icon: 'i-lucide-headphones',
        },
        {
          title: 'Fallback terminal',
          description: 'Mensagem, callback ou encerramento',
          status: 'Rascunho',
          tone: 'violet',
          icon: 'i-lucide-route-off',
        },
      ],
    },
    secondary: {
      title: 'Publicação segura',
      items: [
        {
          title: 'Rascunho',
          description: 'Edição sem impacto operacional',
          icon: 'i-lucide-pencil-ruler',
        },
        {
          title: 'Simulação',
          description: 'Dry-run por cenário',
          icon: 'i-lucide-play',
        },
        {
          title: 'Aprovação',
          description: 'Janela e rollback obrigatórios',
          icon: 'i-lucide-badge-check',
        },
      ],
    },
    actions: [
      action('Salvar rascunho', 'i-lucide-save'),
      action('Executar dry-run', 'i-lucide-play', 'secondary'),
    ],
  },
  orderLookup: {
    key: 'orderLookup',
    eyebrow: 'URA e ERP',
    title: 'Consulta de pedidos na URA',
    description:
      'Jornada ilustrativa para identificar a ótica, validar o pedido e apresentar somente informações autorizadas.',
    icon: 'i-lucide-package-search',
    accent: 'teal',
    status: { label: 'ERP futuro', tone: 'violet' },
    metrics: [
      metric(
        'Pedido',
        '#78456',
        'Identificador de demonstração',
        'i-lucide-hash',
        'blue'
      ),
      metric(
        'Status',
        'Montagem',
        'Resposta publicável',
        'i-lucide-package-cog',
        'teal'
      ),
      metric(
        'Consultas',
        '01',
        'Uma tentativa válida',
        'i-lucide-search-check',
        'violet'
      ),
      metric(
        'Fallback',
        'Humano',
        'Nunca inventar previsão',
        'i-lucide-user-round-check',
        'amber'
      ),
    ],
    flow: [
      {
        title: 'Identificar ótica',
        detail: 'ANI, CNPJ ou código',
        icon: 'i-lucide-building-2',
        tone: 'blue',
      },
      {
        title: 'Coletar pedido',
        detail: 'Entrada validada',
        icon: 'i-lucide-key-round',
        tone: 'violet',
      },
      {
        title: 'Consultar ERP',
        detail: 'Contrato autenticado',
        icon: 'i-lucide-database',
        tone: 'teal',
      },
      {
        title: 'Responder por voz',
        detail: 'Somente campos autorizados',
        icon: 'i-lucide-volume-2',
        tone: 'emerald',
      },
      {
        title: 'Nova consulta',
        detail: 'Limite de tentativas',
        icon: 'i-lucide-rotate-cw',
        tone: 'amber',
      },
      {
        title: 'Atendimento humano',
        detail: 'Saída segura',
        icon: 'i-lucide-headphones',
        tone: 'ruby',
      },
    ],
    primary: {
      title: 'Consulta de pedidos integrada',
      subtitle: 'Contrato visual preparado para a integração ERP',
      items: [
        {
          title: 'Identidade da ótica',
          description: 'Ótica Visão Center · CNPJ mascarado',
          status: 'Confirmada',
          tone: 'emerald',
          icon: 'i-lucide-badge-check',
        },
        {
          title: 'Pedido #78456',
          description: 'Lentes progressivas HOYA',
          status: 'Localizado',
          tone: 'blue',
          icon: 'i-lucide-package-check',
        },
        {
          title: 'Previsão',
          description: 'Não exibida sem campo publicável no ERP',
          status: 'Protegida',
          tone: 'amber',
          icon: 'i-lucide-lock-keyhole',
        },
        {
          title: 'Saída humana',
          description: 'Transferência ou callback preservando contexto',
          status: 'Disponível',
          tone: 'violet',
          icon: 'i-lucide-user-round-cog',
        },
      ],
    },
    secondary: {
      title: 'Tratamento de exceções',
      items: [
        {
          title: 'ERP indisponível',
          description: 'Rota humana; chamada preservada',
          icon: 'i-lucide-cloud-off',
        },
        {
          title: 'Pedido ambíguo',
          description: 'Não selecionar silenciosamente',
          icon: 'i-lucide-git-compare-arrows',
        },
        {
          title: 'Limite de tentativas',
          description: 'Evitar chamadas presas em loop',
          icon: 'i-lucide-shield-alert',
        },
      ],
    },
  },
  coes: {
    key: 'coes',
    eyebrow: 'Cobertura regional',
    title: 'Gestão dos 20 COEs',
    description:
      'Visão nacional de unidades, horários, cobertura DDD, exceções e fallback único para o SAC.',
    icon: 'i-lucide-map',
    accent: 'blue',
    status: { label: '20 unidades planejadas', tone: 'blue' },
    metrics: [
      metric(
        'COEs',
        '20',
        'Cobertura nacional prevista',
        'i-lucide-map-pinned',
        'blue'
      ),
      metric(
        'Fallback',
        'SAC',
        'Destino terminal de contingência',
        'i-lucide-route',
        'ruby'
      ),
      metric(
        'Roteamento',
        'DDD',
        'Com exceções por ótica',
        'i-lucide-signpost-big',
        'violet'
      ),
      metric(
        'Disponibilidade',
        '94%',
        'Base demonstrativa',
        'i-lucide-gauge',
        'teal'
      ),
    ],
    primary: {
      title: 'Matriz de roteamento regional',
      subtitle: 'COE previsto, efetivo e destino final',
      items: [
        {
          title: 'COE São Paulo',
          description: 'DDD 11, 12, 13, 14, 15, 16, 17, 18, 19',
          meta: '8 agentes',
          status: 'Operando',
          tone: 'emerald',
          icon: 'i-lucide-map-pin',
        },
        {
          title: 'COE Rio de Janeiro',
          description: 'DDD 21, 22, 24',
          meta: '4 agentes',
          status: 'Capacidade reduzida',
          tone: 'amber',
          icon: 'i-lucide-triangle-alert',
        },
        {
          title: 'COE Belo Horizonte',
          description: 'DDD 31, 32, 33, 34, 35, 37, 38',
          meta: '5 agentes',
          status: 'Operando',
          tone: 'emerald',
          icon: 'i-lucide-map-pin',
        },
        {
          title: 'Exceção Ótica Premium',
          description: 'Override explícito antes do DDD genérico',
          meta: 'COE SP',
          status: 'Versionada',
          tone: 'blue',
          icon: 'i-lucide-git-compare-arrows',
        },
        {
          title: 'Fallback nacional',
          description: 'Uma única transferência COE → SAC',
          meta: 'Anti-loop',
          status: 'Protegido',
          tone: 'ruby',
          icon: 'i-lucide-shield-check',
        },
      ],
    },
    secondary: {
      title: 'Unidade selecionada',
      items: [
        {
          title: 'Horário',
          description: 'Seg–Sex · 08:00–18:00',
          icon: 'i-lucide-clock-3',
        },
        {
          title: 'Capacidade',
          description: '8 agentes · espera máxima configurável',
          icon: 'i-lucide-users-round',
        },
        {
          title: 'Política de fallback',
          description: 'SAC Nacional, sem retorno automático',
          icon: 'i-lucide-route-off',
        },
      ],
    },
  },
  finance: {
    key: 'finance',
    eyebrow: 'Atendimento restrito',
    title: 'Atendimento Financeiro',
    description:
      'Fila, ocorrências e contexto financeiro segregados por perfil, com dados sensíveis mascarados.',
    icon: 'i-lucide-landmark',
    accent: 'violet',
    status: { label: 'RBAC restrito', tone: 'violet' },
    metrics: [
      metric(
        'Fila',
        'Financeiro',
        'Operação separada do SAC',
        'i-lucide-layers-3',
        'violet'
      ),
      metric(
        'Em espera',
        '3',
        'Maior espera: 00:52',
        'i-lucide-users',
        'amber'
      ),
      metric(
        'Ocorrências',
        '1',
        'Retorno até 16:00',
        'i-lucide-file-warning',
        'ruby'
      ),
      metric(
        'Acesso ERP',
        'Pendente',
        'Contrato futuro autenticado',
        'i-lucide-database-zap',
        'blue'
      ),
    ],
    primary: {
      title: 'Fila e contexto financeiro',
      subtitle: 'Somente agentes expressamente autorizados',
      items: [
        {
          title: 'Ótica Visão Center',
          description: 'Consulta de documento · identidade confirmada',
          meta: '00:41',
          status: 'Em atendimento',
          tone: 'emerald',
          icon: 'i-lucide-phone-call',
        },
        {
          title: 'Ótica Novo Olhar',
          description: 'Boleto e vencimento',
          meta: '00:32',
          status: 'Aguardando',
          tone: 'amber',
          icon: 'i-lucide-receipt-text',
        },
        {
          title: 'Ótica Prime Vision',
          description: 'Comprovante de pagamento',
          meta: '00:52',
          status: 'Prioridade',
          tone: 'ruby',
          icon: 'i-lucide-landmark',
        },
        {
          title: 'Ocorrência FIN-2026-031',
          description: 'Documento pendente de validação',
          meta: 'Hoje',
          status: 'Restrita',
          tone: 'violet',
          icon: 'i-lucide-lock-keyhole',
        },
      ],
    },
    secondary: {
      title: 'Permissões',
      items: [
        {
          title: 'Financeiro: contexto restrito',
          description: 'Valores mascarados fora do perfil',
          icon: 'i-lucide-shield-check',
        },
        {
          title: 'SAC sem acesso transversal',
          description: 'Backend confirma escopo',
          icon: 'i-lucide-user-x',
        },
        {
          title: 'Trilha de acesso',
          description: 'Consulta e exportação auditadas',
          icon: 'i-lucide-scroll-text',
        },
      ],
    },
  },
  customer360: {
    key: 'customer360',
    eyebrow: 'CRM e atendimento',
    title: 'Cliente e Ótica 360°',
    description:
      'Uma ficha única para contato, ótica, pedidos, oportunidades, atendimentos e próximos passos.',
    icon: 'i-lucide-building-2',
    accent: 'teal',
    status: { label: 'Cliente ativo', tone: 'emerald' },
    metrics: [
      metric(
        'Ótica',
        'Visão Center',
        'São Paulo · Sudeste',
        'i-lucide-store',
        'blue'
      ),
      metric('Pedidos', '5', '2 em andamento', 'i-lucide-package', 'teal'),
      metric(
        'Oportunidades',
        '3',
        'Pipeline R$ 84.500',
        'i-lucide-handshake',
        'violet'
      ),
      metric(
        'Próxima ação',
        '21/10',
        'Visita comercial',
        'i-lucide-calendar-check-2',
        'amber'
      ),
    ],
    primary: {
      title: 'Ficha cliente / ótica',
      subtitle: 'Timeline única sem duplicar cadastro por canal',
      items: [
        {
          title: 'Contato principal',
          description: 'Carla Mendes · Compras / Administrativo',
          status: 'Confirmado',
          tone: 'emerald',
          icon: 'i-lucide-user-round-check',
        },
        {
          title: 'Pedido #78456',
          description: 'Lentes progressivas · Em montagem',
          status: 'Em andamento',
          tone: 'blue',
          icon: 'i-lucide-package-cog',
        },
        {
          title: 'Atendimento SAC',
          description: 'Protocolo JRC-2026-1842',
          status: 'Finalizado',
          tone: 'teal',
          icon: 'i-lucide-headphones',
        },
        {
          title: 'Oportunidade Linha Premium',
          description: 'R$ 32.000 · Proposta em preparação',
          status: 'Negociação',
          tone: 'violet',
          icon: 'i-lucide-sparkles',
        },
        {
          title: 'Visita comercial',
          description: '21/10 às 10:30 · Carlos Silva',
          status: 'Agendada',
          tone: 'amber',
          icon: 'i-lucide-map-pin-check',
        },
      ],
    },
    secondary: {
      title: 'Relacionamento',
      items: [
        {
          title: 'Carteira Sudeste',
          description: 'Responsável: Carlos Silva',
          icon: 'i-lucide-briefcase-business',
        },
        {
          title: 'COE preferencial',
          description: 'São Paulo · regra versionada',
          icon: 'i-lucide-map-pinned',
        },
        {
          title: 'WhatsApp corporativo',
          description: 'Canal elegível conforme consentimento',
          icon: 'i-ri-whatsapp-fill',
        },
      ],
    },
    timeline: [
      {
        title: 'Ligação SAC concluída',
        description: 'Pedido #78456 consultado e callback agendado',
        time: 'Hoje · 10:18',
        status: 'Atendimento',
        tone: 'blue',
        icon: 'i-lucide-phone-call',
      },
      {
        title: 'Pedido em montagem',
        description: 'Evento de demonstração do ERP',
        time: 'Ontem · 17:42',
        status: 'Pedido',
        tone: 'teal',
        icon: 'i-lucide-package-check',
      },
      {
        title: 'Visita comercial registrada',
        description: 'Linha Premium apresentada à equipe da ótica',
        time: '12/10 · 15:30',
        status: 'CRM Field',
        tone: 'violet',
        icon: 'i-lucide-map-pin-check',
      },
      {
        title: 'Oportunidade atualizada',
        description: 'Próximo passo definido para 21/10',
        time: '10/10 · 09:15',
        status: 'CRM',
        tone: 'amber',
        icon: 'i-lucide-handshake',
      },
    ],
    actions: [
      action(
        'Abrir CRM Field',
        'i-lucide-map-pinned',
        'primary',
        'crm_field_customer_360'
      ),
      action(
        'Ver carteira',
        'i-lucide-briefcase-business',
        'secondary',
        'crm_field_wallet'
      ),
    ],
  },
  pabxMonitor: {
    key: 'pabxMonitor',
    eyebrow: 'Telefonia e infraestrutura',
    title: 'Monitor do JRC PABX',
    description:
      'Saúde operacional, DIDs, trunks, filas, eventos e capacidades disponíveis para a operação.',
    icon: 'i-lucide-server-cog',
    accent: 'blue',
    status: { label: 'Contrato pendente', tone: 'amber' },
    metrics: [
      metric(
        'Registro SIP',
        'Conectado',
        'Monitor local demonstrativo',
        'i-lucide-signal-high',
        'emerald'
      ),
      metric(
        'Qualidade',
        '100%',
        'Sem perda na janela sintética',
        'i-lucide-waves',
        'teal'
      ),
      metric(
        'Gravação',
        'Disponível',
        'Somente mediante política',
        'i-lucide-mic-2',
        'violet'
      ),
      metric(
        'DIDs',
        '4',
        'Inventário futuro',
        'i-lucide-phone-forwarded',
        'blue'
      ),
    ],
    primary: {
      title: 'Saúde da telefonia',
      subtitle: 'Capacidades descobertas e versionadas',
      items: [
        {
          title: 'Tronco principal',
          description: 'Entrada 0800 / DID',
          meta: '42 ms',
          status: 'Monitorado',
          tone: 'emerald',
          icon: 'i-lucide-cable',
        },
        {
          title: 'Fila SAC Nacional',
          description: 'Eventos de fila e agente',
          meta: 'Sem backlog',
          status: 'Saudável',
          tone: 'emerald',
          icon: 'i-lucide-headphones',
        },
        {
          title: 'Chamadas simultâneas',
          description: '12 de capacidade demonstrativa',
          meta: '3 ativas',
          status: 'Normal',
          tone: 'blue',
          icon: 'i-lucide-phone-call',
        },
        {
          title: 'Gravações',
          description: 'URLs curtas e acesso controlado',
          meta: 'Política pendente',
          status: 'Restrito',
          tone: 'violet',
          icon: 'i-lucide-mic-2',
        },
        {
          title: 'Comandos remotos',
          description: 'Originate, hold, transfer e hangup',
          meta: 'Contrato futuro',
          status: 'Bloqueado',
          tone: 'amber',
          icon: 'i-lucide-terminal',
        },
      ],
    },
    secondary: {
      title: 'Observabilidade',
      items: [
        {
          title: 'Latência dos eventos',
          description: 'Percentis e backlog',
          icon: 'i-lucide-timer',
        },
        {
          title: 'Falhas de autenticação',
          description: 'Nenhum segredo exibido',
          icon: 'i-lucide-shield-alert',
        },
        {
          title: 'Reconciliação CDR',
          description: 'Pendente do contrato oficial',
          icon: 'i-lucide-git-compare-arrows',
        },
      ],
    },
  },
  recordings: {
    key: 'recordings',
    eyebrow: 'Qualidade e compliance',
    title: 'Gravações e Qualidade',
    description:
      'Biblioteca autorizada de chamadas, avaliações, retenção e trilha completa de acesso.',
    icon: 'i-lucide-audio-waveform',
    accent: 'violet',
    status: { label: 'Política controlada', tone: 'violet' },
    metrics: [
      metric(
        'Gravações',
        '128',
        'Janela demonstrativa',
        'i-lucide-audio-lines',
        'blue'
      ),
      metric(
        'Avaliações',
        '18',
        'Amostras revisadas',
        'i-lucide-clipboard-check',
        'teal'
      ),
      metric(
        'Nota média',
        '92%',
        'Critérios de qualidade',
        'i-lucide-star',
        'amber'
      ),
      metric(
        'Retenção',
        'Política',
        'Prazo ainda a aprovar',
        'i-lucide-shield-check',
        'violet'
      ),
    ],
    primary: {
      title: 'Biblioteca de gravações',
      subtitle: 'Acesso, reprodução e download sempre auditados',
      items: [
        {
          title: 'Ligação SAC · Ótica Visão Center',
          description: '04:32 · Agente Carla Mendes',
          meta: 'Hoje 10:14',
          status: 'Avaliada 96%',
          tone: 'emerald',
          icon: 'i-lucide-circle-play',
        },
        {
          title: 'Ligação Financeiro · Novo Olhar',
          description: '02:18 · Agente Paulo Ribeiro',
          meta: 'Hoje 09:52',
          status: 'Restrita',
          tone: 'violet',
          icon: 'i-lucide-lock-keyhole',
        },
        {
          title: 'Callback · Prime Vision',
          description: '03:05 · Agente Marina Costa',
          meta: 'Ontem 17:30',
          status: 'Pendente de avaliar',
          tone: 'amber',
          icon: 'i-lucide-audio-waveform',
        },
        {
          title: 'Transferência COE → SAC',
          description: '06:44 · Duas pernas correlacionadas',
          meta: 'Ontem 15:12',
          status: 'Avaliada 88%',
          tone: 'blue',
          icon: 'i-lucide-git-compare-arrows',
        },
      ],
    },
    secondary: {
      title: 'Auditoria',
      items: [
        {
          title: 'Acesso restrito por papel',
          description: 'Qualidade e auditoria',
          icon: 'i-lucide-shield-check',
        },
        {
          title: 'URL com expiração',
          description: 'Sem mídia pública persistente',
          icon: 'i-lucide-clock-3',
        },
        {
          title: 'Política de retenção',
          description: 'Prazo e descarte governados',
          icon: 'i-lucide-shield-check',
        },
      ],
    },
  },
  reports: {
    key: 'reports',
    eyebrow: 'BI Contact Center',
    title: 'Relatórios de Operação',
    description:
      'Indicadores reconciliáveis por período, unidade, fila, agente, canal e jornada.',
    icon: 'i-lucide-chart-no-axes-combined',
    accent: 'blue',
    status: { label: '27 visões previstas', tone: 'blue' },
    metrics: [
      metric(
        'Chamadas',
        '1.284',
        'Oferecidas no período',
        'i-lucide-phone-call',
        'blue',
        '+8,4%'
      ),
      metric(
        'Abandono',
        '2,8%',
        'Após política de short-abandon',
        'i-lucide-phone-missed',
        'ruby',
        '-0,6%'
      ),
      metric(
        'TMA',
        '04:32',
        'Conversa + hold + ACW',
        'i-lucide-timer',
        'teal',
        '-18s'
      ),
      metric(
        'NPS',
        '8,7',
        'Respostas válidas',
        'i-lucide-star',
        'amber',
        '+0,4'
      ),
    ],
    primary: {
      title: 'Indicadores com filtros',
      subtitle: 'SAC · Financeiro · COEs · agentes · canais',
      items: [
        {
          title: 'Executivo nacional',
          description: 'Volume, SLA, abandono, satisfação e contingência',
          status: 'Disponível',
          tone: 'emerald',
          icon: 'i-lucide-presentation',
        },
        {
          title: 'Fila por período',
          description: 'Oferecidas, atendidas, abandonadas e tempos',
          status: 'Disponível',
          tone: 'blue',
          icon: 'i-lucide-chart-column',
        },
        {
          title: 'Atividade dos agentes',
          description: 'Estados, ocupação, pausas e ACW',
          status: 'Disponível',
          tone: 'teal',
          icon: 'i-lucide-users-round',
        },
        {
          title: 'Contingência COE → SAC',
          description: 'Origem, causa, destino final e impacto',
          status: 'Contrato futuro',
          tone: 'violet',
          icon: 'i-lucide-route',
        },
        {
          title: 'Saúde de integrações',
          description: 'PABX, ERP, eventos, comandos e reconciliação',
          status: 'Disponível',
          tone: 'amber',
          icon: 'i-lucide-heart-pulse',
        },
      ],
    },
    secondary: {
      title: 'Exportação',
      items: [
        {
          title: 'CSV e PDF',
          description: 'Mesmo escopo da consulta',
          icon: 'i-lucide-file-down',
        },
        {
          title: 'Agendamento',
          description: 'Entrega recorrente autorizada',
          icon: 'i-lucide-calendar-clock',
        },
        {
          title: 'Drilldown',
          description: 'Fila → chamada → eventos',
          icon: 'i-lucide-search',
        },
      ],
    },
    chart: [42, 56, 49, 65, 72, 61, 80, 75, 86, 91, 84, 94],
  },
  surveys: {
    key: 'surveys',
    eyebrow: 'Relacionamento e qualidade',
    title: 'Pesquisa de Satisfação',
    description:
      'Regras, versões, canais, frequência e resultados reutilizando o motor de pesquisas existente.',
    icon: 'i-lucide-message-circle-heart',
    accent: 'violet',
    status: { label: 'Ativação configurável', tone: 'violet' },
    metrics: [
      metric(
        'NPS',
        '4,6/5',
        'Exemplo de escala ativa',
        'i-lucide-star',
        'amber'
      ),
      metric('Envios', '310', 'Chamadas elegíveis', 'i-lucide-send', 'blue'),
      metric(
        'Regras',
        'Ativas',
        'Por canal e fila',
        'i-lucide-list-checks',
        'teal'
      ),
      metric(
        'Resposta',
        '38%',
        'Taxa demonstrativa',
        'i-lucide-message-circle-check',
        'violet'
      ),
    ],
    primary: {
      title: 'Regras de pesquisa',
      subtitle: 'Uma decisão idempotente por interação elegível',
      items: [
        {
          title: 'Voz · SAC Nacional',
          description: 'Após chamada atendida e encerrada',
          meta: 'Versão 3',
          status: 'Ativa',
          tone: 'emerald',
          icon: 'i-lucide-phone-call',
        },
        {
          title: 'WhatsApp · Atendimento',
          description: 'Link autorizado após encerramento',
          meta: 'Versão 2',
          status: 'Ativa',
          tone: 'emerald',
          icon: 'i-ri-whatsapp-fill',
        },
        {
          title: 'Financeiro',
          description: 'Somente mediante consentimento',
          meta: 'Versão 1',
          status: 'Pausada',
          tone: 'amber',
          icon: 'i-lucide-landmark',
        },
        {
          title: 'Cliente bloqueado',
          description: 'Respeitar frequência e opt-out',
          meta: 'Regra global',
          status: 'Protegido',
          tone: 'violet',
          icon: 'i-lucide-shield-check',
        },
      ],
    },
    secondary: {
      title: 'Resultados',
      items: [
        {
          title: 'Respostas válidas',
          description: '310 entregues · 118 respondidas',
          icon: 'i-lucide-message-circle-check',
        },
        {
          title: 'Alerta detrator',
          description: 'Ocorrência nativa opcional',
          icon: 'i-lucide-triangle-alert',
        },
        {
          title: 'Segmentação',
          description: 'Canal, fila, unidade e período',
          icon: 'i-lucide-filter',
        },
      ],
    },
  },
  security: {
    key: 'security',
    eyebrow: 'Governança e LGPD',
    title: 'Segurança e Perfis',
    description:
      'Matriz de acesso por papel, unidade, fila e operação, com auditoria e revogação imediata.',
    icon: 'i-lucide-shield-check',
    accent: 'ruby',
    status: { label: 'RBAC por escopo', tone: 'emerald' },
    metrics: [
      metric(
        'Perfis',
        '6',
        'Padrões de operação',
        'i-lucide-users-round',
        'blue'
      ),
      metric(
        'Auditoria',
        '100%',
        'Mudanças críticas registradas',
        'i-lucide-scroll-text',
        'teal'
      ),
      metric(
        'Acessos',
        'RBAC',
        'Perfil + unidade + fila',
        'i-lucide-key-round',
        'violet'
      ),
      metric(
        'Revisões',
        '2',
        'Pendências de aprovação',
        'i-lucide-shield-alert',
        'amber'
      ),
    ],
    primary: {
      title: 'Perfis e unidades',
      subtitle: 'Acesso mínimo necessário por função',
      items: [
        {
          title: 'Agente SAC',
          description: 'Atender, consultar CRM e registrar ocorrências',
          status: 'SAC Nacional',
          tone: 'blue',
          icon: 'i-lucide-headphones',
        },
        {
          title: 'Supervisor SAC',
          description: 'Filas, agentes, ocorrências e relatórios',
          status: 'Gestão operacional',
          tone: 'teal',
          icon: 'i-lucide-monitor-dot',
        },
        {
          title: 'Supervisor Financeiro',
          description: 'Contexto restrito e dados mascarados',
          status: 'Financeiro',
          tone: 'violet',
          icon: 'i-lucide-landmark',
        },
        {
          title: 'Supervisor COE',
          description: 'Somente unidades expressamente associadas',
          status: 'Regional',
          tone: 'amber',
          icon: 'i-lucide-map-pinned',
        },
        {
          title: 'Control Desk Nacional',
          description: 'Leitura transversal e ações críticas aprovadas',
          status: 'Nacional',
          tone: 'ruby',
          icon: 'i-lucide-radar',
        },
        {
          title: 'Auditoria / Qualidade',
          description: 'Relatórios e gravações autorizadas',
          status: 'Somente leitura',
          tone: 'emerald',
          icon: 'i-lucide-user-search',
        },
      ],
    },
    secondary: {
      title: 'Segurança',
      items: [
        {
          title: 'MFA e sessões',
          description: 'Quando aplicável ao perfil',
          icon: 'i-lucide-smartphone',
        },
        {
          title: 'Logs sem segredos',
          description: 'Tokens, CPF/CNPJ e áudio protegidos',
          icon: 'i-lucide-file-lock-2',
        },
        {
          title: 'Revogação imediata',
          description: 'Novos comandos bloqueados',
          icon: 'i-lucide-user-x',
        },
      ],
    },
  },
  migration: {
    key: 'migration',
    eyebrow: 'Transição controlada',
    title: 'Painel de Migração',
    description:
      'Ondas, checklist, riscos, go/no-go e rollback real antes de qualquer mudança de número ou rota.',
    icon: 'i-lucide-workflow',
    accent: 'amber',
    status: { label: 'Piloto planejado', tone: 'amber' },
    metrics: [
      metric(
        'Fase atual',
        'Piloto',
        'SAC em rota de teste',
        'i-lucide-flag',
        'blue'
      ),
      metric(
        'Go/No-Go',
        'Pendente',
        'Evidências e assinaturas',
        'i-lucide-circle-help',
        'amber'
      ),
      metric(
        'Rollback',
        'Previsto',
        'Retorno real a comprovar',
        'i-lucide-undo-2',
        'violet'
      ),
      metric(
        'Critérios',
        '8/12',
        'Itens de entrada concluídos',
        'i-lucide-list-checks',
        'teal'
      ),
    ],
    phases: [
      {
        title: 'Diagnóstico',
        detail: 'URA, números, DDD, relatórios e baseline',
        state: 'Concluído',
        tone: 'emerald',
      },
      {
        title: 'Piloto SAC',
        detail: 'Rota de teste, agentes e métricas',
        state: 'Em preparação',
        tone: 'blue',
      },
      {
        title: 'Financeiro',
        detail: 'Fila restrita e ERP',
        state: 'Planejado',
        tone: 'violet',
      },
      {
        title: '2 COEs',
        detail: 'DDD, overrides e fallback',
        state: 'Planejado',
        tone: 'amber',
      },
      {
        title: '20 COEs',
        detail: 'Expansão em ondas',
        state: 'Futuro',
        tone: 'slate',
      },
      {
        title: 'Corporativo / Field / WhatsApp',
        detail: 'Ondas posteriores',
        state: 'Futuro',
        tone: 'slate',
      },
    ],
    primary: {
      title: 'Cronograma e controle de virada',
      subtitle: 'Cada onda exige baseline, teste seco, canário e estabilização',
      items: [
        {
          title: 'Preparar janela',
          description: 'Agentes, filas, números, áudio e versão',
          status: 'Em andamento',
          tone: 'blue',
          icon: 'i-lucide-calendar-range',
        },
        {
          title: 'Baseline operacional',
          description: 'Métricas da solução atual por fila/COE',
          status: 'Concluído',
          tone: 'emerald',
          icon: 'i-lucide-chart-spline',
        },
        {
          title: 'Teste seco',
          description: 'DDD, timeout, blackout e transferência',
          status: 'Pendente',
          tone: 'amber',
          icon: 'i-lucide-flask-conical',
        },
        {
          title: 'Ativar canário',
          description: 'Grupo pequeno e monitoramento dedicado',
          status: 'Bloqueado',
          tone: 'violet',
          icon: 'i-lucide-bird',
        },
        {
          title: 'Rollback real',
          description: 'Operadora e rota anterior recuperáveis',
          status: 'A comprovar',
          tone: 'ruby',
          icon: 'i-lucide-undo-2',
        },
      ],
    },
    secondary: {
      title: 'Critérios de NO-GO',
      items: [
        {
          title: 'Entrada 0800 indisponível',
          description: 'Interromper onda imediatamente',
          icon: 'i-lucide-phone-off',
        },
        {
          title: 'Divergência de CDR',
          description: 'Não liberar painel oficial',
          icon: 'i-lucide-git-compare-arrows',
        },
        {
          title: 'Violação de anti-loop',
          description: 'Acionar contingência validada',
          icon: 'i-lucide-route-off',
        },
      ],
    },
  },
};

export const contactCenterScreen = (key, t) =>
  localizeVisualScreen(
    contactCenterVisualCatalog[key] || contactCenterVisualCatalog.cockpit,
    t
  );
