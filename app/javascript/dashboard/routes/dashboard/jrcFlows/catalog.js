export const NODE_TYPES = [
  { type: 'start', icon: 'i-lucide-play', group: 'logic', fields: [] },
  {
    type: 'message',
    icon: 'i-lucide-message-square',
    group: 'messages',
    fields: [['text', 'textarea']],
  },
  {
    type: 'media',
    icon: 'i-lucide-image',
    group: 'messages',
    fields: [
      ['url', 'url'],
      ['text', 'textarea'],
    ],
  },
  {
    type: 'input',
    icon: 'i-lucide-text-cursor-input',
    group: 'logic',
    fields: [
      ['variable', 'text'],
      ['timeout', 'number'],
    ],
  },
  { type: 'switch', icon: 'i-lucide-git-branch', group: 'logic', fields: [] },
  {
    type: 'condition',
    icon: 'i-lucide-split',
    group: 'logic',
    fields: [
      ['field', 'text'],
      ['operator', 'operator'],
      ['value', 'text'],
    ],
  },
  {
    type: 'delay',
    icon: 'i-lucide-timer',
    group: 'logic',
    fields: [['seconds', 'number']],
  },
  {
    type: 'variable',
    icon: 'i-lucide-braces',
    group: 'logic',
    fields: [
      ['variable', 'text'],
      ['value', 'text'],
    ],
  },
  {
    type: 'assign',
    icon: 'i-lucide-user-round-check',
    group: 'service',
    fields: [
      ['team_id', 'teams'],
      ['agent_id', 'agents'],
    ],
  },
  {
    type: 'labels',
    icon: 'i-lucide-tags',
    group: 'service',
    fields: [
      ['labels', 'labels'],
      ['operation', 'operation'],
    ],
  },
  {
    type: 'status',
    icon: 'i-lucide-circle-check',
    group: 'service',
    fields: [['status', 'status']],
  },
  {
    type: 'note',
    icon: 'i-lucide-notebook-pen',
    group: 'service',
    fields: [['text', 'textarea']],
  },
  {
    type: 'contact',
    icon: 'i-lucide-contact',
    group: 'service',
    fields: [
      ['field', 'contact'],
      ['value', 'text'],
    ],
  },
  {
    type: 'create_lead',
    icon: 'i-lucide-user-round-plus',
    group: 'crm',
    fields: [],
    capability: 'crm',
  },
  {
    type: 'move_deal',
    icon: 'i-lucide-columns-3',
    group: 'crm',
    fields: [
      ['stage_id', 'stages'],
      ['deal_id', 'text'],
    ],
    capability: 'crm',
  },
  {
    type: 'activity',
    icon: 'i-lucide-calendar-days',
    group: 'crm',
    fields: [
      ['title', 'text'],
      ['description', 'textarea'],
      ['user_id', 'agents'],
      ['hours', 'number'],
    ],
    capability: 'crm',
  },
  {
    type: 'webhook',
    icon: 'i-lucide-webhook',
    group: 'integrations',
    fields: [
      ['url', 'url'],
      ['body', 'textarea'],
    ],
  },
  {
    type: 'nico',
    icon: 'i-lucide-bot',
    group: 'integrations',
    fields: [
      ['objective', 'textarea'],
      ['hours', 'number'],
      ['allowed_actions', 'permissions'],
    ],
    capability: 'nico',
  },
  { type: 'end', icon: 'i-lucide-square', group: 'logic', fields: [] },
];

export const KINDS = ['chatbot', 'workflow', 'sequence', 'voice'];
export const OPERATORS = [
  'equals',
  'contains',
  'starts_with',
  'not_equals',
  'present',
];
export const clone = value => JSON.parse(JSON.stringify(value));

export function nodeDefaults(type) {
  const defaults = {
    input: { variable: 'resposta', timeout: 300 },
    switch: {
      cases: [
        {
          id: 'option1',
          field: 'message',
          operator: 'equals',
          value: '1',
          label: 'Opção 1',
        },
      ],
    },
    condition: { field: 'message', operator: 'equals', value: '' },
    delay: { seconds: 10 },
    variable: { variable: 'interesse', value: '' },
    labels: { labels: [], operation: 'add' },
    status: { status: 'open' },
    contact: { field: 'name', value: '{{resposta}}' },
    activity: { hours: 24, title: 'Retornar ao cliente', user_id: '' },
    nico: {
      hours: 2,
      allowed_actions: [],
      objective:
        'Atenda o cliente com as informações autorizadas. Encaminhe dúvidas que não puder resolver para um atendente.',
    },
  };
  return clone(defaults[type] || {});
}

export function ports(node) {
  if (node.type === 'workflow') return node.data.ports || [];
  if (['end', 'assign', 'nico'].includes(node.type)) return [];
  if (node.type === 'switch')
    return [...(node.data.cases || []).map(c => c.id), 'fallback'];
  if (node.type === 'condition') return ['yes', 'no'];
  if (node.type === 'input') return ['next', 'timeout'];
  return ['next'];
}

export const templateIds = [
  'welcome',
  'triage',
  'commercial',
  'followup',
  'nico',
  'voice',
];

export function makeTemplate(id, name, inboxIds = []) {
  const graph = { nodes: [], edges: [] };
  function add(type, nodeId, x, y, data = {}) {
    graph.nodes.push({
      id: nodeId,
      type,
      label: '',
      position: { x, y },
      data: { ...nodeDefaults(type), ...data },
    });
  }
  function link(source, target, port = 'next') {
    graph.edges.push({ id: `${source}-${port}`, source, target, port });
  }
  add('start', 'start', 70, 170);
  if (id === 'triage') {
    add('message', 'welcome', 370, 170, {
      text: 'Olá, {{contact.name}}! Sou o assistente virtual da JRC. Como podemos ajudar?\n1 — Suporte\n2 — Comercial',
    });
    add('input', 'reply', 670, 170, { variable: 'setor' });
    add('switch', 'sector', 970, 170, {
      cases: [
        {
          id: 'support',
          label: 'Suporte',
          field: 'setor',
          operator: 'equals',
          value: '1',
        },
        {
          id: 'sales',
          label: 'Comercial',
          field: 'setor',
          operator: 'equals',
          value: '2',
        },
      ],
    });
    add('assign', 'support', 1270, 30);
    add('assign', 'sales', 1270, 260);
    add('assign', 'fallback', 1270, 480);
    link('start', 'welcome');
    link('welcome', 'reply');
    link('reply', 'sector');
    link('reply', 'fallback', 'timeout');
    link('sector', 'support', 'support');
    link('sector', 'sales', 'sales');
    link('sector', 'fallback', 'fallback');
  } else if (id === 'commercial') {
    add('message', 'welcome', 370, 170, {
      text: 'Olá, {{contact.name}}! Qual solução você procura para sua empresa?',
    });
    add('input', 'reply', 670, 170, { variable: 'interesse' });
    add('create_lead', 'lead', 970, 170);
    add('note', 'note', 1270, 170, {
      text: 'Interesse informado pelo cliente: {{interesse}}',
    });
    add('assign', 'sales', 1570, 170);
    link('start', 'welcome');
    link('welcome', 'reply');
    link('reply', 'lead');
    link('reply', 'sales', 'timeout');
    link('lead', 'note');
    link('note', 'sales');
  } else if (id === 'followup') {
    add('delay', 'delay', 370, 170, { seconds: 3600 });
    add('message', 'message', 670, 170, {
      text: 'Olá, {{contact.name}}! Posso ajudar com alguma dúvida sobre o que conversamos?',
    });
    add('end', 'end', 970, 170);
    link('start', 'delay');
    link('delay', 'message');
    link('message', 'end');
  } else if (['nico', 'voice'].includes(id)) {
    add('nico', 'nico', 370, 170);
    link('start', 'nico');
  } else {
    add('message', 'welcome', 370, 170, {
      text: 'Olá, {{contact.name}}! Bem-vindo à JRC. Sou o assistente virtual. Como podemos ajudar?',
    });
    add('end', 'end', 670, 170);
    link('start', 'welcome');
    link('welcome', 'end');
  }
  return {
    name,
    description: '',
    kind: { voice: 'voice', followup: 'sequence' }[id] || 'chatbot',
    graph,
    settings: {
      trigger: id === 'followup' ? 'manual' : 'message_created',
      inbox_ids: inboxIds,
      pause_on_agent: true,
      pause_on_team: false,
      stop_on_reply: true,
      restart_on_resolve: true,
      keyword: '',
      business_hours: false,
      timezone: 'America/Sao_Paulo',
      opens_at: '08:00',
      closes_at: '18:00',
      days: [1, 2, 3, 4, 5],
    },
  };
}
