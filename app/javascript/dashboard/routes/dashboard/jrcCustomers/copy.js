export const RELATIONSHIPS = Object.freeze({
  prospect: 'Prospect',
  lead: 'Lead',
  customer: 'Cliente',
  former_customer: 'Ex-cliente',
  partner: 'Parceiro',
  supplier: 'Fornecedor',
  internal: 'Interno',
  other: 'Outro',
});
export const PERSON_KINDS = Object.freeze({
  organization: 'Pessoa jur\u00eddica',
  individual: 'Pessoa f\u00edsica',
});
export const SIZE_OPTIONS = Object.freeze({
  mei: 'MEI',
  me: 'ME',
  epp: 'EPP',
  medium: 'Médio porte',
  large: 'Grande porte',
});
export const SOURCE_OPTIONS = Object.freeze({
  referral: 'Indicação',
  inbound: 'Inbound',
  outbound: 'Outbound',
  website: 'Site',
  campaign: 'Campanha',
  event: 'Evento',
  partner: 'Parceiro',
  import: 'Importação',
  manual: 'Cadastro manual',
  other: 'Outra',
});
export const ADDRESS_TYPES = Object.freeze({
  tax: 'Fiscal',
  billing: 'Cobran\u00e7a',
  business: 'Comercial',
  installation: 'Instala\u00e7\u00e3o',
  branch: 'Filial',
  other: 'Outro',
});
export const POINT_TYPES = Object.freeze({
  email: 'E-mail',
  corporate_email: 'E-mail corporativo',
  alternate_email: 'E-mail alternativo',
  phone: 'Telefone',
  mobile: 'Celular',
  whatsapp: 'WhatsApp',
  whatsapp_business: 'WhatsApp Business',
  extension: 'Ramal',
});
export const FIELD_LABELS = Object.freeze({
  customer_code: 'Código da empresa',
  name: 'Raz\u00e3o social / nome',
  trade_name: 'Nome fantasia',
  tax_id: 'CNPJ / CPF',
  state_registration: 'Inscri\u00e7\u00e3o estadual',
  municipal_registration: 'Inscri\u00e7\u00e3o municipal',
  segment: 'Segmento',
  size: 'Porte',
  website: 'Site',
  domain: 'Dom\u00ednio',
  email: 'E-mail',
  phone_number: 'Telefone',
  source: 'Origem',
  economic_group: 'Grupo econ\u00f4mico',
  relationship_tags: 'Relacionamentos secundários',
  tags: 'Tags',
  created_by_name: 'Criado por',
  updated_by_name: 'Atualizado por',
  created_at: 'Data de cadastro',
  updated_at: 'Última atualização',
  last_activity_at: 'Última atividade',
  description: 'Observa\u00e7\u00f5es',
  job_title: 'Cargo',
  department: 'Departamento',
  postal_code: 'CEP',
  street: 'Logradouro',
  number: 'N\u00famero',
  complement: 'Complemento',
  district: 'Bairro',
  city: 'Cidade',
  state: 'UF',
  country: 'Pa\u00eds',
});
export const T = Object.freeze({
  secondsShort: 's',
  servedCompany: 'Empresa atendida',
  serviceDeskUnavailable:
    'Tarefas nativas do Service Desk ainda nao estao disponiveis nesta agenda. Chamados e SLA permanecem no Service Desk.',
  tickets: 'Chamados',
  projects: 'Projetos',
  project_tasks: 'Tarefas dos projetos',
  contracts: 'Contratos comerciais',
  orders: 'Pedidos',
  follow_ups: 'Follow-ups',
  openTickets: 'Chamados abertos',
  slaBreached: 'Chamados com SLA vencido',
  activeProjects: 'Projetos em andamento',
  activeContracts: 'Contratos ativos',
  agenda: 'Minha Agenda',
  customers: 'Clientes',
  master: 'Cadastro Mestre',
  companies: 'Empresas',
  contacts: 'Contatos',
  segments: 'Segmentos',
  groups: 'Grupos',
  imports: 'Importa\u00e7\u00f5es',
  newCompany: 'Nova empresa',
  editCompany: 'Editar empresa',
  newContact: 'Cadastrar contato',
  linkContact: 'Vincular contato existente',
  overview: 'Vis\u00e3o 360º',
  registration: 'Cadastro',
  relationshipArea: 'Relacionamento',
  commercial: 'Comercial',
  operation: 'Operação',
  service: 'Atendimento',
  general: 'Dados gerais',
  addresses: 'Endere\u00e7os',
  timeline: 'Linha do tempo',
  conversations: 'Conversas',
  deals: 'Neg\u00f3cios',
  leads: 'Leads',
  proposals: 'Propostas',
  activities: 'Atividades',
  calls: 'Telefonia',
  campaigns: 'Campanhas',
  loading: 'Carregando...',
  saving: 'Salvando...',
  save: 'Salvar',
  cancel: 'Cancelar',
  close: 'Fechar',
  edit: 'Editar',
  remove: 'Remover',
  detach: 'Desvincular',
  search: 'Buscar',
  clear: 'Limpar sele\u00e7\u00e3o',
  refresh: 'Atualizar',
  next: 'Pr\u00f3xima',
  previous: 'Anterior',
  more: 'Carregar mais',
  searchCompany: 'Nome, CNPJ/CPF, telefone, e-mail ou contato',
  searchContact: 'Nome, telefone ou e-mail',
  searchPicker: 'Buscar e selecionar empresa',
  all: 'Todos',
  active: 'Ativo',
  inactive: 'Inativo',
  relationship: 'Relacionamento principal',
  secondaryRelationships: 'Relacionamentos secundários',
  tags: 'Tags',
  addSegment: 'Adicionar segmento',
  segmentName: 'Nome do segmento',
  taxonomyAdminHelp:
    'Segmentos passam a ser parametrizados aqui e reutilizados no cadastro de empresas.',
  owner: 'Respons\u00e1vel',
  noOwner: 'Sem respons\u00e1vel',
  parent: 'Matriz',
  noCompany: 'Sem empresa vinculada',
  noResults: 'Nenhum registro encontrado.',
  noData: 'Sem dados registrados para este filtro e seu perfil de acesso.',
  count: 'Contatos',
  city: 'Cidade',
  openConversations: 'Conversas abertas',
  opportunities: 'Oportunidades abertas',
  openOpportunityValue: 'Valor em oportunidades abertas',
  monthlyRevenue: 'MRR dos contratos ativos',
  pendingActivities: 'Atividades pendentes',
  lastConversation: 'Última conversa',
  nextActivity: 'Próxima atividade',
  noNextActivity: 'Nenhuma atividade futura agendada',
  lastInteraction: '\u00daltima intera\u00e7\u00e3o registrada',
  directoryHelp:
    'Empresa n\u00e3o \u00e9 sin\u00f4nimo de cliente. O relacionamento comercial \u00e9 definido separadamente.',
  permissionsHelp:
    'Totais e hist\u00f3ricos respeitam seu acesso. M\u00f3dulos ausentes nesta base n\u00e3o s\u00e3o apresentados como zero.',
  timelineHelp:
    'Eventos existentes, sem copiar mensagens para uma nova base. Mensagens privadas n\u00e3o aparecem aqui.',
  provisional: 'Contato provis\u00f3rio',
  registered: 'Cadastro confirmado',
  provisionalHelp:
    'Receber uma conversa cria o contato t\u00e9cnico, mas n\u00e3o transforma a pessoa em cliente.',
  contactName: 'Nome do contato',
  contactPoints: 'Outros meios de contato',
  addPoint: 'Adicionar meio de contato',
  value: 'Valor',
  label: 'Identifica\u00e7\u00e3o',
  kind: 'Tipo',
  pointHelp:
    'Use +DDI nos telefones. Estes dados n\u00e3o substituem os identificadores dos canais.',
  duplicates: 'Verificar duplicidades',
  possibleDuplicates: 'Poss\u00edveis duplicidades',
  noDuplicates: 'Nenhuma correspond\u00eancia por identificador encontrada.',
  useExisting: 'Usar existente',
  merge: 'Mesclar neste contato',
  confirmMerge:
    'Mesclar o contato selecionado neste cadastro? O hist\u00f3rico ser\u00e1 preservado. Revise empresa e identidade antes de confirmar.',
  confirmReassignment:
    'Confirmar a mudan\u00e7a do v\u00ednculo? Os registros hist\u00f3ricos do CRM n\u00e3o ser\u00e3o reescritos.',
  confirmRemove:
    'Confirmar remo\u00e7\u00e3o? A altera\u00e7\u00e3o ficar\u00e1 registrada na auditoria.',
  saveLink: 'Salvar cadastro e v\u00ednculo',
  openCompany: 'Abrir ficha 360\u00ba',
  openContact: 'Abrir contato',
  addAddress: 'Adicionar endere\u00e7o',
  branches: 'Filiais',
  requestFailed:
    'N\u00e3o foi poss\u00edvel concluir. Verifique os dados e tente novamente.',
  saved: 'Altera\u00e7\u00e3o salva.',
  nativeSegments: 'Filtros salvos dos contatos',
  companySegments: 'Segmentos das empresas',
  nativeGroups: 'Etiquetas e grupos dos contatos',
  economicGroups: 'Grupos econ\u00f4micos',
  taxonomiesHelp:
    'Segmentos e grupos econ\u00f4micos s\u00e3o editados na ficha da empresa. Filtros e etiquetas existentes dos contatos continuam sendo usados.',
  companyImport: 'Importar empresas',
  contactImport: 'Importar contatos',
  preview: 'Validar e visualizar pr\u00e9via',
  apply: 'Aplicar pr\u00e9via aprovada',
  importHelp:
    'CSV UTF-8, separado por v\u00edrgulas, at\u00e9 500 linhas e 1 MiB. A pr\u00e9via n\u00e3o altera dados. ID ou CPF/CNPJ identifica atualiza\u00e7\u00f5es; nomes nunca provocam mescla autom\u00e1tica.',
  contactImportHelp:
    'Usa o importador nativo do Chatwoot. A fila processa o arquivo e envia o resultado pelos mecanismos existentes.',
  nativeContacts: 'Abrir contatos e importador nativo',
  importApplied: 'Importa\u00e7\u00e3o aplicada.',
  line: 'Linha',
  action: 'A\u00e7\u00e3o',
  errors: 'Erros',
  create: 'Criar',
  update: 'Atualizar',
  template: 'Baixar modelo CSV',
  review: 'Revise todas as linhas antes de aplicar.',
  campaignFilters: 'Filtrar pelo Cadastro Mestre',
  campaignHelp:
    'Os filtros complementam a audi\u00eancia. Consentimento, bloqueios e deduplica\u00e7\u00e3o continuam obrigat\u00f3rios.',
});
export const inputClass =
  'mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12';
export const buttonClass =
  'rounded-lg border border-n-strong px-3 py-2 text-sm text-n-slate-12 disabled:opacity-50';
export const primaryClass =
  'rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50';
export function errorMessage(error) {
  const data = error?.response?.data;
  const details = data?.details
    ? Object.entries(data.details)
        .map(
          ([field, messages]) =>
            `${FIELD_LABELS[field] || field}: ${Array(messages).join(', ')}`
        )
        .join('; ')
    : '';
  return (
    details || (typeof data?.error === 'string' ? data.error : T.requestFailed)
  );
}
