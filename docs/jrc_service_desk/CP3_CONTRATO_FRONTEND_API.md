# CP3 - Contrato frontend / API de leitura

**CONTRATO PROPOSTO PARA CP4. NENHUM ENDPOINT ABAIXO FOI IMPLEMENTADO NO BACKEND PELO CP3.**

## Transporte e isolamento

Prefixo esperado: `/api/v1/accounts/:accountId/jrc_service_desk`.
Autenticação será a nativa do JRC; Account deve vir do contexto autenticado, nunca apenas da URL.
O cliente usa axios nativo, somente GET, timeout de 15 segundos e cancelamento por instância.
Não herda os métodos mutadores do ApiClient e não aceita URLs fornecidas por dados remotos.

O guard de navegação usa adicionalmente **o endpoint nativo já existente**
`GET /api/v1/accounts/:accountId`, para conferir a feature da Account de destino.
Isso não cria uma API Service Desk nem autoriza seus registros.

## Leituras preparadas

| GET relativo | Uso |
|---|---|
| `/ui_context` | Identidade conferida, unidades efetivamente autorizadas e projeções de capacidades. |
| `/tickets` | Lista paginada com filtros, inclusive `mine=true` aplicado no backend. |
| `/tickets/:ticketId` | Detalhe autorizado e projeção segura de campos. |
| `/queues`, `/priorities`, `/categories`, `/statuses` | Configuração real dentro de unidades autorizadas. |
| `/units`, `/operator_companies` | Estrutura operacional autorizada; operadora continua derivada da unidade. |
| `/assignees` | AccountUsers com vínculo ativo à unidade selecionada. |
| `/requesters` | Contatos nativos autorizados no contexto selecionado; sem duplicar clientes. |
| `/teams` | Equipes nativas permitidas para organização do trabalho, sem conceder acesso à unidade. |

As projeções `/assignees`, `/requesters` e `/teams` exigem seleção explícita de uma unidade.
O frontend não envia essas consultas sem `unit_id`; o backend ainda deverá autorizá-lo.

As três últimas são **projeções** sobre entidades existentes; não novas tabelas.
Nenhuma dessas leituras é encaminhada automaticamente à API genérica de contatos/equipes,
pois isso perderia o contrato de permissão e escopo do Service Desk.
Domínios complementares (SLA configurável, catálogo, base, aprovações, problemas, mudanças,
ativos, contratos, automações, pesquisas, relatórios) não fazem chamadas especulativas.
Seus esquemas visuais mostram disponibilidade pendente.

## Envelope e tipos

`contract_version` deve ser o número 1. Identificadores são strings decimais positivas (ou números
seguros), sem conversão silenciosa de bigint. IDs não aceitam arrays, objetos, sinal, espaços,
zero, expoente, casas decimais ou caminhos. Account nativa também é conferida antes de atualizar o store.

Contexto: `account_id`, `user_id`, `available` booleano, `units` e `capabilities`.
Cada unidade: `id`, `account_id`, `name`, `active: true`, `operator_company` com `id/account_id/name`
e `permissions`. Operadora/unidade devem pertencer à mesma Account. Repetições são recusadas.
`available` somente poderá ser true depois de confirmar autenticação, feature, escopo e policies.
`units` deverá conter apenas vínculos efetivamente ativos e autorizados, inclusive para administrador.
A interface não pode certificar a origem de um payload mal emitido: a barreira é o backend.

`capabilities[recurso].index` e `unit.permissions.create_ticket` são booleans projetados por policies,
**não nomes de novas permissões armazenadas ou roles criados pelo CP3**. `settings.index` é uma
projeção de acesso à configuração; nunca inferir de perfil no navegador. Ausência equivale a negar.
Os nomes de role nativos nas metas de rota habilitam apenas a avaliação da rota, não concedem dados.

Coleção: `account_id`, `contract_version`, `items` e `meta: {page, per_page, total}`.
`total` é inteiro não negativo calculado sobre a MESMA consulta autorizada/filtrada que alimenta a
página; nunca substituído por 0 ou `items.length`. Página e tamanho devem corresponder à requisição.
Uma página vazia com total positivo e posição ainda dentro do resultado é incompatível.
Cada registro tem `id`, `account_id`, `unit_id` quando aplicável e `permissions.show: true`.
`Unit.id` é a unidade; `OperatorCompany.id` deve pertencer ao conjunto das unidades autorizadas.
Filtros de unidade e operadora são conferidos novamente no payload antes de exibir registros.

Detalhe: `contract_version`, `account_id`, `ticket` com ID igual ao selecionado.
Nomes e textos são tratados como texto escapado pelo Vue, sem `v-html`.
Campos extras como snapshots financeiros, credenciais, blobs e URLs são descartados pelo decoder.
Isso não autoriza enviar dados sensíveis ao navegador: o serializer deve omití-los no servidor.

## Projeção de chamado e relações existentes

| Campo de apresentação | Origem / regra |
|---|---|
| `id` | Ticket.id; sem nova numeração inventada. |
| `number` | Opcional. Sem valor fornecido, mostrar o ID real. CP2 não tem numeração humana nova. |
| `title`, `description` | Campos nativos do model Ticket CP2, respeitando permissão. |
| `unit_id` | Unidade obrigatória do chamado; operadora derivada pela unidade. |
| `requester` | `{id, name}` de Contact autorizado. Empresa-cliente não é operadora. |
| `status`, `priority`, `category` | `{id, name}` dos registros reais da unidade. |
| `assignee` | `{id, name}` da projeção AccountUser da atribuição; não confundir User.id, AccountUser.id e UnitMembership.id. |
| `queue`, `team` | Projeções das relações existentes. |
| `source` | Nome de apresentação de `origin_channel`; não envia mensagem em canal algum. |
| `lock_version` | Versão existente, quando fornecida. CP3 não envia mutações. |
| `sla` | Somente projeção autorizada: prazos/state quando realmente calculados. Sem cálculo, deixar nulo. |
| `permissions` | Booleans show/update/add_note etc. calculados pelas policies para aquele chamado. |

O formulário CP3 não monta/enviaria automaticamente os argumentos dos comandos CP2.
A API futura deve resolver status inicial ativo explícito e distinguir `assignee_account_user_id`
da membership validada, além de validar versão, idempotência e cada relação. Não mudar
policies/modelagem para encaixar um campo de apresentação. Transferência de unidade e transição
de status não são um PATCH genérico; continuam fluxos posteriores.

## Filtros e paginação

`q` (até 200 caracteres), `page`, `per_page` (1..100), `unit_id`, `operator_company_id`,
`status_id`, `priority_id`, `category_id`, `queue_id`, `assignee_id`, `source`, `mine=true`,
`sort` (updated_at_desc/created_at_desc/created_at_asc). Esses limites são do contrato de
leitura/controles, não dados de configuração do negócio. Cadastros aceitam apenas o subconjunto
q/page/per_page/unit_id/operator_company_id/sort. Campos desconhecidos são recusados.

Aplicação de filtros atualiza a URL, sem filtrar uma página local para fingir consulta global.
A busca textual e `mine` exigem implementação backend. A mudança explícita de unidade limpa
os filtros dependentes. Ordenação por risco SLA só poderá ser adicionada quando houver origem real.

## Erros, concorrência e sigilo

401 remove contexto; 403 remove contexto e todos os dados exibidos; JSON incompatível
remove contexto. 404 em contexto/lista significa API pendente, não uma lista vazia confirmada;
404 em detalhe mostra chamado não encontrado/sem acesso, sem afirmar sua existência.
405/501 significam leitura não disponível; falhas de rede/5xx mostram erro e permitem repetir.
Nenhum erro dispara fallback de conta ou de unidade. Respostas antigas, mesmo se o transporte
ignorar AbortSignal, são descartadas por geração da sessão e sequência da requisição.

Downloads, arquivos, conversas, eventos, notas, snapshots financeiros e integrações futuras
precisam de contratos e policies por campo/registro. Não há lista de URLs de anexos, acesso a
blobs, notas públicas, envios de WhatsApp/e-mail ou ferramentas NICO nesta entrega.
