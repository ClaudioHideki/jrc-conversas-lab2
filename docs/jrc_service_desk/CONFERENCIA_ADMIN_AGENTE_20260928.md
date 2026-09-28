# Conferência final — Admin × Agente

Base conferida antes de alterar: branch `codex/service-desk-candidato-r2-20260928`,
HEAD `62dec3c5f21446e7aa3487c54f7b2d3b1b20d84a`, Git limpo.
Escopo: auditoria de autorização e correção pontual de navegação. Sem publicação.

## Resultado da auditoria

A separação de autorização no backend já estava implementada: capacidades
administrativas não implicam `tickets_view`, e UnitMembership não concede capacidades.
A administração estrutural pode ser exercida sem vínculo operacional do autor.
Não foi encontrada necessidade de alterar políticas, modelos, serviços ou RBAC.

Foi encontrada uma lacuna de navegação: `screenAccessible` consultava apenas a
capacidade de leitura do recurso para subrotas `settings/*`. Um agente com
`lookups_view` precisava consultar categorias/status/prioridades para trabalhar em
chamados e, por isso, também conseguia abrir diretamente essas páginas de
Configurações. A página era somente leitura, sem bypass de escrita no backend,
mas contrariava a separação de telas aprovada.

Correção: subrotas `settings/*` também exigem `capabilities.settings.index === true`,
obtida do backend. A mesma função protege entrada por URL, visibilidade e renderização
da tela. A rota raiz Configurações já exigia essa capacidade. Não foi retirada
a consulta operacional dos catálogos usada nos formulários de chamados.

## Comportamento final

| Perfil explicitamente configurado | Administração | Chamados / Minha Fila |
| --- | --- | --- |
| Somente Admin estrutural, sem UnitMembership | Estrutura, unidades/operadoras e vínculos conforme capacidades estruturais; entrada independente no menu principal | Negados; conceder vínculo a outra pessoa não concede vínculo ao autor |
| Somente Admin de configuração, com escopo da unidade | Configurações e catálogos autorizados; serviços e políticas conforme capacidades de gestão | Negados sem capacidades de chamados, mesmo tendo vínculo |
| Somente Agente, com vínculo ativo | Configurações, subrotas administrativas e APIs de gestão negadas; consultas operacionais continuam disponíveis | Permitidos somente conforme capacidade e escopo; Minha Fila filtra atribuições do próprio usuário |
| Admin + Agente | Ambas as áreas conforme capacidades e unidades concedidas | Sem acesso a outra conta ou unidade não concedida |
| Sem capacidades, sem vínculo operacional ou com vínculo inativo | Nenhuma concessão automática; estrutura só com autoridade estrutural independente | Negados |

Distinção preservada: configurações **por unidade** continuam exigindo vínculo ativo
na unidade pela arquitetura CP6. Isso não autoriza chamados sem `tickets_view`.
A administração **estrutural por conta** usa `StructureContext`, não exige esse
vínculo do autor e não passa seu contexto para APIs operacionais. Nenhum administrador
recebe implicitamente todas as unidades. Equipes e responsáveis não substituem vínculos.

### Perfis nativos e Custom Roles

“Administrador do Service Desk” não é um novo papel nem sinônimo do papel nativo
`administrator`. Os defaults nativos preexistentes de `Capabilities` incluem
permissões de configuração **e** de operação para o administrador. Ele ainda precisa
de UnitMembership para operar. Para testar ou atribuir **somente Admin**, usar
CustomRole explícita sem `tickets_view` e suas capacidades operacionais dependentes.
Essa semântica de defaults não foi alterada silenciosamente nesta conferência.

## Capacidades e políticas verificadas

Prefixo das capacidades: `jrc_service_desk_`.

- Entrada/configurações: `module_view`, `settings_view`, `lookups_view`.
- Gestão por recurso: `statuses_manage`, `priorities_manage`, `categories_manage`,
  `queues_manage`, `services_manage`, `lifecycle_policies_manage`.
- Estrutura: `structure_view`, `operator_companies_manage`, `units_manage`,
  `unit_memberships_manage`; permanecem os requisitos de cliente confirmado,
  AccountUser administrador, CustomRole explícita, flag e bootstrap.
- Operação: `tickets_view`, `tickets_create`, `tickets_edit`, `tickets_assign`,
  `tickets_transfer` e demais capacidades de ação; `dashboard_view` depende de
  leitura de chamados. Dependências são avaliadas pelo backend.
- `ModulePolicy`, `ConfigurationPolicy`, `LifecyclePolicyPolicy`, `StructurePolicy`,
  `TicketPolicy`, `LookupPolicy` e policies nativas continuam aplicadas.
- `TicketPolicy::Scope` restringe conta/unidade e vínculo com o chamado; mesmo
  `tickets_view_all` não permite unidades não concedidas.
- `OperationalContext` relê identidade, flag, capacidades e vínculos. A API aplica
  sua própria autorização, independentemente de o menu aparecer ou não.

## Rotas e APIs

Rotas sob `/app/accounts/:accountId/service-desk/`:

- `settings`, `settings/statuses`, `settings/priorities`, `settings/categories`,
  `settings/units`, `settings/operator-companies`: exigem autorização administrativa
  de navegação, além da leitura do recurso/contexto válido.
- `tickets`, `my-queue`, detalhes/edição: exigem leitura de chamados; formulário e
  API verificam a capacidade da mutação, não apenas acesso à página.
- Filas e Responsáveis operacionais não foram convertidos em gestão de acesso.
- `service-desk-structure` mantém seu guard estrutural independente, inclusive a
  tela de UnitMembership entregue no commit-base.

APIs sob `/api/v1/accounts/:account_id/jrc_service_desk/`:

- `ui_context`: autoridade e unidades reais; não infere privilégios do menu.
- `configuration/{statuses,priorities,categories,queues,services}`: leitura
  administrativa e escritas exigem capacidade de gestão e unidade autorizada.
- Políticas de ciclo de vida/publicação: `LifecyclePolicyPolicy` e capacidades próprias.
- `structure/context`, `structure/members`, unidades/operadoras/vínculos e recibos:
  `StructurePolicy`; sem autorizar chamados ao administrador estrutural.
- `tickets` e ações: `TicketPolicy`, capacidades de ação e escopo.
- GETs de catálogos operacionais continuam permitidos a agentes com `lookups_view`
  no escopo. Essa leitura não é a API administrativa `configuration/*`.

SLA já implementado permanece nas políticas/serviços e configurações existentes.
As páginas planejadas sem API não foram habilitadas ou declaradas concluídas.

## Evidências automatizadas

Testes novos:

- `adminAgentAccess.spec.js`: 11 casos de menu/landing, Admin, Agente, perfil combinado,
  acesso direto às seis rotas administrativas e ausência de escopo/capacidade.
- `admin_agent_access_spec.rb`: cinco jornadas de API com capacidades explícitas;
  configuração sem chamados, estrutura sem vínculo próprio, agente negado em gestão,
  combinação de perfis, cross-account, cross-unit, flag e vínculo inativo.

As regressões de `unit_access_spec.rb` e `unitAccess.spec.js` verificam concessão,
revogação, reativação, auditoria, releitura e nova montagem da tela. As regressões
CP4/CP5/CP6 incluem atribuição, Minha Fila, ações, segurança e equipe sem concessão
de unidade. O bootstrap é testado separadamente de acesso operacional.

Resultados:

| Verificação | Resultado |
| --- | --- |
| RSpec regressões e perfis, excluindo o grupo não transacional `sd_concurrency` | 376 exemplos, zero falhas |
| RSpec concorrência, em execução separada | Quatro exemplos, zero falhas |
| Vitest completo do Service Desk | 418 testes em 16 arquivos, todos aprovados |
| Zeitwerk | All is good |
| Build frontend Vite production | Aprovado, 2m19s; não é imagem Docker |
| RuboCop/ESLint dos testes novos | Zero ocorrências |
| git diff --check | Aprovado |

Na primeira execução, os casos não transacionais de concorrência foram misturados
à suíte transacional. Dois testes antigos de contagem global falharam porque havia
dois chamados persistidos pelas fixtures de concorrência (esperado 0/1, obtido 2/3).
Não houve falha de negação de autorização. O schema descartável foi recriado e os
376 exemplos transacionais passaram sem alterar código ou expectativas. Os quatro
casos de concorrência passaram separadamente; resultado registrado
em `admin-agent-concurrency.log`.

Logs locais: `output/service-desk-r2-20260928/admin-agent-*.log`. Banco utilizado:
PostgreSQL descartável de testes; nenhum acesso ao banco do LAB/produção.
Permanecem avisos preexistentes de depreciação Rails, Browserslist antigo e chunks
grandes. O helper existente não foi reformatado globalmente; somente as linhas da
condição nova foram verificadas, sem ocorrência de lint nessas linhas.

## Arquivos e preservação

Modificado somente em produção:
`app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/nativeIntegration.js`
(condição de autorização de subrotas administrativas).

Adicionados:
- `app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/adminAgentAccess.spec.js`
- `spec/requests/api/v1/accounts/jrc_service_desk/admin_agent_access_spec.rb`
- este relatório.

Nenhum arquivo removido, migration criada ou dependência alterada. A correção do
commit `62dec3c` permanece integralmente. Não foram alterados QR/Broker, CRM,
softphone, Conversas, NICO, Calling, Campanhas, Cockpit, Email Center ou Calls Center.
Não houve trabalho em GoPure ou Projetos.
Flags preservadas: Service Desk ext_1 posição 9/máscara 256/default false;
Broker posição 11/máscara 1024; Flows inalterado. Nenhuma Account real habilitada.
Sem limpeza global de RuboCop/ESLint.

## Homologação posterior no LAB

Pendente de autorização de publicação e de execução humana por HTTPS:

1. Administrador estrutural autorizado → Acessos → Matriz → Thiago → conceder,
   salvar, recarregar e consultar o vínculo persistido.
2. Thiago com vínculo e capacidades operacionais → Chamados → Minha Fila.
3. Verificar Configurações ocultas e URL/API administrativa negadas para o agente.
4. Testar separadamente Admin sem capacidades de chamados e Admin + Agente.
5. Conversa → chamado → atribuição → Minha Fila → status → persistência → SLA → Dashboard.

Os testes automatizados não homologam essa jornada real. Não gerar imagem,
publicar, fazer deploy ou executar migrations em produção nesta etapa.
