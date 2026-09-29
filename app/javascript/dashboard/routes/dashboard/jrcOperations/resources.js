const text = (key, label, required = false) => ({
  key,
  label,
  required,
  type: 'text',
});
const area = (key, label) => ({ key, label, type: 'textarea' });
const number = (key, label, min = 0, value = 0) => ({
  key,
  label,
  type: 'number',
  min,
  default: value,
});
const select = (key, label, choices, required = false) => ({
  key,
  label,
  type: 'select',
  choices,
  required,
});
const option = (key, label, source, required = false) => ({
  key,
  label,
  type: 'option',
  source,
  required,
});
const date = (key, label) => ({ key, label, type: 'date' });
const active = {
  key: 'active',
  label: 'Ativo',
  type: 'checkbox',
  default: true,
};
const owner = option('owner_id', 'Responsavel', 'users');
export const templateResource = {
  key: 'project_templates',
  title: 'Modelos de projeto',
  help: 'Uma tarefa por linha. Criar um projeto copia o modelo; edicoes posteriores nao alteram entregas em andamento.',
  fields: [
    text('name', 'Nome', true),
    number('version', 'Versao', 1, 1),
    {
      key: 'definition',
      label: 'Tarefas iniciais: uma por linha',
      type: 'tasks',
    },
    active,
  ],
};
export const projectResources = [
  {
    key: 'members',
    title: 'Equipe e responsabilidades',
    fields: [
      { ...option('user_id', 'Usuario', 'users', true), readOnlyOnEdit: true },
      select(
        'role',
        'Papel',
        {
          manager: 'Gerente',
          member: 'Membro',
          contributor: 'Colaborador (tarefas proprias)',
          viewer: 'Observador',
        },
        true
      ),
      {
        ...number('allocation_percent', 'Alocacao prevista (%)', 0, 100),
        max: 100,
      },
    ],
  },
  {
    key: 'milestones',
    title: 'Marcos de entrega',
    fields: [
      text('name', 'Nome', true),
      date('due_on', 'Prazo'),
      select(
        'status',
        'Situacao',
        { open: 'Aberto', completed: 'Concluido', canceled: 'Cancelado' },
        true
      ),
    ],
  },
  {
    key: 'sprints',
    title: 'Ciclos de trabalho',
    fields: [
      text('name', 'Nome', true),
      date('starts_on', 'Inicio'),
      date('ends_on', 'Termino'),
      select(
        'status',
        'Situacao',
        {
          planned: 'Planejado',
          active: 'Em andamento',
          completed: 'Concluido',
        },
        true
      ),
    ],
  },
  ...[
    ['risks', 'Riscos'],
    ['issues', 'Impedimentos'],
    ['decisions', 'Decisoes'],
  ].map(([key, title]) => ({
    key,
    title,
    fields: [
      text('title', 'Titulo', true),
      area('description', 'Descricao'),
      owner,
      select(
        'status',
        'Situacao',
        {
          open: 'Aberto',
          monitoring: 'Em acompanhamento',
          resolved: 'Resolvido',
          closed: 'Encerrado',
        },
        true
      ),
      select('severity', 'Severidade', {
        low: 'Baixa',
        medium: 'Media',
        high: 'Alta',
        critical: 'Critica',
      }),
    ],
  })),
];
