# CP5 - integracao nativa e capacidades

Baseline exclusiva: JRC-CONVERSAS-SERVICE-DESK-CP4-CONSOLIDADO-20260928.zip.
SHA-256 verificado antes de qualquer alteracao: 6365d93606933d7109e59c924b41b3eaadb5b52b356c951c0cb1cd37e7071c21.
Data: 28/09/2026. Nao reconstruir checkpoints nem aplicar patches. CP6/Projetos fora do escopo.
SD-D01..SD-D05, CP2-D01/D02 e CP4-D01 preservadas.

## Decisao tecnica dentro da autorizacao CP5

O catalogo `CustomRole.permissions` ja existe (enterprise/app/models/custom_role.rb), assim
como AccountUser#permissions, ApplicationPolicy/Pundit e o formulario nativo de roles.
Acrescentar capacidades `jrc_service_desk_*` a esse catalogo. Nenhuma tabela de grants/roles,
segunda autenticacao, seed, habilitacao de Account ou autoconcessao de unidade.
O helper de capacidades somente interpreta os perfis NATIVOS e a lista nativa de permissoes;
nao persiste outro RBAC. Na ausencia da extensao nativa CustomRole, manter os papeis nativos
agent/administrator; nao simular armazenamento de permissoes em JSON ou UnitMembership.

Os perfis padrao mantem as acoes que ja eram permitidas pelas policies CP4, mas agora por uma
matriz nomeada explicita e dependencias. Administrator nao e um atalho: Account, feature,
UnitMembership ativo, capacidade da acao, scope de registro e regra de ciclo sao obrigatorios.
CustomRole substitui os defaults, INCLUSIVE quando AccountUser.role e administrator; nunca
herda o conjunto admin nem acessa todos os tickets implicitamente. CustomRoles anteriores
sem grants do Service Desk continuam negados. Permissao de ver todos os tickets afeta SOMENTE
as unidades explicitamente vinculadas, nunca outras unidades/Accounts.

A flag preservada tem default false/extensao 1/posicao 9/mascara 256. Nem role/grant isolado
habilita a feature. UI recebe capacidades do backend e a sidebar confirma o contexto; acoes
e dados sao bloqueados tambem nos services, nao somente nos controllers/menus.

## Alteracoes previstas

- Distinguir editar dados, mudar prioridade, atribuir e transferir; controlar os campos mesmo
  em PATCH direto e atribuicao durante criacao. Transferencia aqui continua na MESMA unidade.
- Autorizar separadamente historico/notas/SLA/vinculos/gerenciamento de politicas e filtrar
  as opcoes de ciclo por capacidade; reler a capacidade antes de reproduzir idempotencia.
- Reutilizar Contact/Company/Team e Conversation nativos com escopo e policies dos dois lados;
  Company e contexto de cliente, nao operadora; ID de banco e display_id nunca confundidos.
- Projecao minima de cliente e endpoint de navegacao reautorizado para a conversa nativa.
- Conservar queries SQL de KPI e scopes, sem nova fonte ou contador no frontend.
- Preservar auditoria por evento/transicao/versao; distinguir transferencia; auditar alteracoes
  das permissoes Service Desk no log nativo quando a extensao Enterprise existe.
- Sem novos jobs, migrations, tabelas de permissoes ou APIs de autoconcessao de UnitMembership.
- Gerenciamento de filas/categorias/prioridades/status: consolidar as policies/capacidades;
  CRUD nao exposto anteriormente continua pendente, sem simular botoes.

PENDENTE — validação nativa em ambiente Docker/local.
