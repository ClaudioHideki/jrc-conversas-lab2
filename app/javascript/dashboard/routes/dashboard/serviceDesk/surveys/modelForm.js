export const STEPS = [
  'Informações',
  'Perguntas',
  'Canais',
  'Regras de envio',
  'Permissões',
  'Revisão',
];
export const CHANNELS = [
  {
    key: 'whatsapp',
    label: 'WhatsApp',
    icon: 'i-lucide-message-circle',
    tone: 'green',
    hint: 'Mensagem com link, por uma caixa autorizada.',
  },
  {
    key: 'email',
    label: 'E-mail',
    icon: 'i-lucide-mail',
    tone: 'blue',
    hint: 'Mensagem com link e identidade de envio autorizada.',
  },
  {
    key: 'public_link',
    label: 'Portal do cliente',
    icon: 'i-lucide-monitor',
    tone: 'purple',
    hint: 'Pesquisa disponível no contexto autorizado do chamado.',
  },
];
export const ROLES = [
  { key: 'administrator', label: 'Administradores' },
  { key: 'supervisor', label: 'Supervisores' },
  { key: 'agent', label: 'Agentes' },
];
export const DAYS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
export function stable(value) {
  if (Array.isArray(value)) return '[' + value.map(stable).join(',') + ']';
  if (value && typeof value === 'object')
    return (
      '{' +
      Object.keys(value)
        .sort()
        .map(k => JSON.stringify(k) + ':' + stable(value[k]))
        .join(',') +
      '}'
    );
  return JSON.stringify(value);
}
export const clone = value => JSON.parse(JSON.stringify(value));
export const key = () =>
  (typeof crypto !== 'undefined' && crypto.randomUUID?.()) ||
  `model_${Date.now()}_${Math.random().toString(36).slice(2)}_${Math.random().toString(36).slice(2)}`;
export const titles = {
  nps: 'Em uma escala de 0 a 10, quanto você recomendaria nosso atendimento?',
  csat: 'Como você avalia o atendimento recebido?',
  ces: 'Quanto foi fácil resolver sua solicitação?',
};
export function newModel(unit, options = {}) {
  return {
    code: `pesquisa_${key()
      .replace(/[^a-z0-9]/gi, '')
      .slice(-12)
      .toLowerCase()}`,
    name: '',
    description: '',
    kind: 'nps',
    active: true,
    unit_id: unit.id,
    operator_id: unit.operator_id || unit.operator_company?.id,
    questions: [
      {
        key: 'score',
        text: titles.nps,
        type: 'scale',
        min: 0,
        max: 10,
        required: true,
      },
      {
        key: 'comment',
        text: 'Deixe seu comentário (opcional)',
        type: 'text',
        required: false,
      },
    ],
    channels: Object.fromEntries(
      CHANNELS.map(({ key: channel }) => [
        channel,
        {
          enabled: false,
          inbox_id: null,
          message:
            'Olá! Como foi seu atendimento? Sua opinião é importante. Responda aqui: {{survey_link}}',
          whatsapp_template: null,
        },
      ])
    ),
    rules: {
      event: 'closed',
      delay_minutes: 0,
      frequency_days: 30,
      expires_hours: 168,
      consent_required: true,
      priority: 100,
      execution_member_id: null,
      channel_order: CHANNELS.map(row => row.key),
      ticket_type_id: null,
      queue_id: null,
      team_id: null,
      priority_id: null,
      send_window: {
        enabled: false,
        timezone: options.timezone || 'America/Sao_Paulo',
        days: [1, 2, 3, 4, 5],
        start: '08:00',
        end: '18:00',
      },
    },
    permissions: {
      team_ids: [],
      edit_roles: ['administrator'],
      publish_roles: ['administrator'],
      response_roles: ['administrator'],
      report_roles: ['administrator'],
      share_relationship: false,
      share_reports: true,
      customer_own_response: true,
    },
    settings: {
      thank_you: 'Obrigado pela sua avaliação!',
      ces_direction: 'higher_is_better',
    },
  };
}
export function setKind(model, kind) {
  const previous = titles[model.kind];
  model.kind = kind;
  const first = model.questions[0];
  if (!first) return;
  if (!first.text || first.text === previous) first.text = titles[kind];
  Object.assign(first, {
    type: 'scale',
    required: true,
    min: kind === 'csat' ? 1 : 0,
    max: kind === 'csat' ? 5 : 10,
  });
  delete first.presentation;
  delete model.settings.low_threshold;
}
export function addQuestion(model, type) {
  let count = model.questions.length + 1;
  const existingKeys = new Set(model.questions.map(row => row.key));
  while (existingKeys.has(`question_${count}`)) count += 1;
  const row = {
    key: `question_${count}`,
    text: '',
    type: type === 'rating' ? 'scale' : type,
    required: false,
  };
  if (row.type === 'scale')
    Object.assign(row, {
      min: type === 'rating' ? 1 : 0,
      max: type === 'rating' ? 5 : 10,
    });
  if (type === 'rating') row.presentation = 'stars';
  if (type === 'choice')
    row.options = [
      { value: 'option_1', label: '' },
      { value: 'option_2', label: '' },
    ];
  model.questions.push(row);
  return model.questions.length - 1;
}
export function moveQuestion(model, index, offset) {
  const target = index + offset;
  if (index <= 0 || target <= 0 || target >= model.questions.length)
    return false;
  const copy = [...model.questions];
  const [row] = copy.splice(index, 1);
  copy.splice(target, 0, row);
  if (
    copy.some(
      (question, position) =>
        question.condition &&
        !copy
          .slice(0, position)
          .some(prior => prior.key === question.condition.question)
    )
  )
    return false;
  model.questions = copy;
  return true;
}
export function validateStep(model, step) {
  const errors = [];
  const fail = (field, message) => errors.push({ step, field, message });
  const integer = (n, min, max) => Number.isInteger(n) && n >= min && n <= max;
  if (step === 0) {
    if (!model.name.trim() || model.name.length > 120)
      fail('name', 'Informe um nome de até 120 caracteres.');
    if (!model.unit_id || !model.operator_id)
      fail('unit_id', 'Selecione a empresa operadora e a unidade autorizada.');
    if (!/^[a-z0-9_-]{1,32}$/.test(model.code))
      fail('code', 'Revise o código do modelo.');
    if (!['nps', 'csat', 'ces'].includes(model.kind))
      fail('kind', 'Selecione o tipo de pesquisa.');
  }
  if (step === 1) {
    if (model.questions.length < 1 || model.questions.length > 20)
      fail('questions', 'Adicione entre uma e vinte perguntas.');
    const seen = new Set();
    model.questions.forEach((q, i) => {
      if (!/^[a-z0-9_-]{1,60}$/.test(q.key) || seen.has(q.key))
        fail(
          `questions.${i}.key`,
          `Pergunta ${i + 1}: código inválido ou repetido.`
        );
      if (q.condition && !seen.has(q.condition.question))
        fail(
          `questions.${i}.condition`,
          `Pergunta ${i + 1}: a condição deve referir uma pergunta anterior.`
        );
      seen.add(q.key);
      if (!q.text.trim() || q.text.length > 1000)
        fail(`questions.${i}.text`, `Preencha o texto da pergunta ${i + 1}.`);
      if (
        q.type === 'scale' &&
        (!integer(q.min, 0, 99) || !integer(q.max, 1, 100) || q.min >= q.max)
      )
        fail(`questions.${i}.scale`, `Revise a escala da pergunta ${i + 1}.`);
      if (
        q.type === 'choice' &&
        (!q.options?.length ||
          q.options.some(o => !o.label.trim()) ||
          new Set(q.options.map(o => o.value)).size !== q.options.length)
      )
        fail(
          `questions.${i}.options`,
          `Preencha as opções da pergunta ${i + 1}.`
        );
    });
    const first = model.questions[0];
    if (
      !first ||
      first.type !== 'scale' ||
      !first.required ||
      (model.kind === 'nps' && (first.min !== 0 || first.max !== 10))
    )
      fail(
        'questions.0',
        'A pergunta principal deve ter escala obrigatória; NPS utiliza 0 a 10.'
      );
  }
  if (step === 2) {
    if (!CHANNELS.some(c => model.channels[c.key].enabled))
      fail('channels', 'Habilite e configure pelo menos um canal.');
    CHANNELS.forEach(c => {
      const row = model.channels[c.key];
      if (!row.enabled || c.key === 'public_link') return;
      if (!row.inbox_id) fail(c.key, `Selecione uma caixa para ${c.label}.`);
      if (!row.message?.includes('{{survey_link}}'))
        fail(c.key, `Inclua {{survey_link}} na mensagem de ${c.label}.`);
    });
  }
  if (step === 3) {
    const r = model.rules;
    if (!r.execution_member_id)
      fail(
        'execution_member_id',
        'Selecione quem autoriza a execução da regra.'
      );
    if (!['closed', 'first_agent_response', 'manual'].includes(r.event))
      fail('event', 'Selecione o evento.');
    if (
      !integer(r.delay_minutes, 0, 52560) ||
      !integer(r.frequency_days, 0, 3650) ||
      !integer(r.expires_hours, 1, 8760)
    )
      fail('timing', 'Revise os intervalos de envio e validade.');
    const w = r.send_window;
    if (
      w.enabled &&
      (!w.days.length ||
        !w.timezone ||
        !/^\d{2}:\d{2}$/.test(w.start) ||
        !/^\d{2}:\d{2}$/.test(w.end) ||
        w.start >= w.end)
    )
      fail('send_window', 'Revise dias, fuso e intervalo de envio.');
  }
  if (step === 4) {
    ['edit_roles', 'publish_roles', 'response_roles', 'report_roles'].forEach(
      k => {
        if (!model.permissions[k].includes('administrator'))
          fail(k, 'Administradores autorizados devem ser mantidos.');
      }
    );
  }
  return errors;
}
export const allErrors = model =>
  [0, 1, 2, 3, 4].flatMap(step => validateStep(model, step));
export function messageErrors(error) {
  if (error?.response?.status === 409)
    return [
      {
        step: -1,
        field: '',
        message:
          'O modelo mudou em outra sessão. Suas alterações foram mantidas; releia a versão antes de tentar novamente.',
      },
    ];
  if ([401, 403, 404].includes(error?.response?.status))
    return [
      {
        step: -1,
        field: '',
        message:
          'O contexto ou a permissão mudou. Feche e atualize a página; nenhum acesso adicional foi concedido.',
      },
    ];
  const rows = error?.response?.data?.errors;
  if (
    Array.isArray(rows) &&
    rows.every(
      row => row && typeof row === 'object' && typeof row.message === 'string'
    )
  )
    return rows;
  return [
    {
      step: -1,
      field: '',
      message:
        'Não foi possível confirmar a operação. Releia o modelo antes de repetir. Seu rascunho permanece nesta janela.',
    },
  ];
}
