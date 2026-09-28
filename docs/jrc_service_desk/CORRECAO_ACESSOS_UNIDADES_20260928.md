# Correção incremental — administração de acessos às unidades

Base: `2318b495cdaecde8055bf480bd10d19d352396e3`.
Branch: `codex/service-desk-candidato-r2-20260928`.
Entrega local para revisão; sem push, imagem ou deploy.

## Diagnóstico e reaproveitamento

O CP6-D01 já implementava `StructureView`, `StructureController`,
`StructureService`, `StructurePolicy`, `StructureAudit` e capacidades estruturais.
O cadastro genérico exibia principalmente IDs de vínculos existentes: não havia
uma visão por unidade que incluísse usuários **sem vínculo**, pesquisa por pessoa,
papel e capacidades efetivas. “Responsáveis” não resolvia essa lacuna.

A correção evolui a tela existente e sua API de consulta. Não cria outro CRUD de
gravação, outro RBAC, outro vínculo ou outra forma de autenticação.

## Caminho na interface

- Configurações do Service Desk → **Unit access / Acessos às unidades**.
- A entrada independente **Estrutura do Service Desk** continua disponível ao
  administrador estrutural sem acesso operacional a nenhuma unidade.
- Rota reutilizada: `/app/accounts/:accountId/service-desk-structure?resource=unit_memberships`.
- Selecionar unidade, visualizar operadora/unidade, pesquisar usuário por nome e
  consultar estado ativo, inativo ou sem vínculo.
- Conceder, revogar ou reativar abre confirmação com pessoa, unidade, ação e
  referência/motivo. O botão Salvar executa a gravação real.
- Sucesso exige resposta da escrita, recibo de auditoria e GET independente do
  registro. A lista é consultada novamente. Falha de confirmação não vira sucesso.
- Ao recarregar, selecionar novamente a unidade consulta o estado persistido;
  os filtros não são gravados como autorização nem armazenados no navegador.
- Autoativação continua proibida. Unidade/operadora inativa impede concessão;
  revogação permanece disponível. Não há exclusão física de vínculos.

Textos novos foram adicionados ao catálogo `en`, conforme `AGENTS.md`.
Em pt-BR, as chaves novas usam o fallback inglês até a tradução pelo fluxo do
projeto. As traduções existentes de estado e confirmação continuam reutilizadas.

## Contratos, segurança e auditoria

Todos os caminhos abaixo têm prefixo
`/api/v1/accounts/:account_id/jrc_service_desk/structure`:

| Endpoint | Uso |
| --- | --- |
| GET `/context` | Autoridade estrutural nativa, revalidada |
| GET `/units?page=&q=` | Seleção paginada de unidades da conta |
| GET `/members?unit_id=&page=&q=` | Consulta ampliada: usuário, papel, CustomRole, capacidades efetivas e vínculo na unidade |
| POST `/unit_memberships` | Criação pelo `StructureService` existente |
| PATCH `/unit_memberships/:id` | Revogação/reativação, com revisão otimista |
| GET `/unit_memberships/:id` | Releitura persistida |
| GET `/unit_memberships/:id/receipts/:audit_id` | Confirmação auditada |

`unit_id` é opcional para manter os consumidores antigos de `/members`.
Quando presente, é resolvido pelo `StructurePolicy::Scope`, limitado à Account
autenticada. A resposta inclui operadora, unidade, `membership` (ou null), papel e
capacidades calculadas pelo `OperationalContext` existente. Não recebe Account,
roles ou capacidades confiáveis do navegador. Resultados são paginados em 25;
`Cache-Control: no-store` continua aplicado.

As capacidades necessárias são `jrc_service_desk_structure_view` e
`jrc_service_desk_unit_memberships_manage`, em CustomRole explícita. Além delas,
`StructureContext` continua exigindo AccountUser administrador, cliente confirmado,
conta correta, flag e bootstrap existente. **Administrador sozinho não basta.**
Nenhuma UnitMembership operacional do autor é exigida para administração estrutural.

`MembershipDirectory` apenas projeta dados. As escritas continuam no
`StructureService`, com Pundit, Account/Unit/AccountUser compatíveis, locks,
idempotência, revisão, motivo e `StructureAudit` na mesma transação. Histórico de
revogação/reativação é preservado. Policies e serviços de escrita não foram alterados.

## Papéis e capacidades — sem segundo RBAC

O CP5 já integrou `SERVICE_DESK_CUSTOM_ROLE_PERMISSIONS` ao formulário nativo
de Custom Roles. O caminho existente é Configurações → Custom Roles para definir
permissões; Configurações → Agentes para atribuir o papel. As dependências entre
capacidades continuam calculadas pelo backend, sem autoconcessão.

A nova consulta mostra papel nativo/personalizado e **capacidades efetivas**,
separadas do vínculo. Os links para configurações nativas aparecem somente com
a permissão nativa `administrator`; o link de Custom Roles também exige sua flag.

Limitação preexistente importante: um administrador com CustomRole não recebe
automaticamente a permissão frontend nativa `administrator`. Ter autoridade
estrutural não autoriza editar roles. Nesse caso, a delegação deve ser feita por
outro administrador autorizado nas configurações nativas. Não foi criado bypass
nem ampliado o poder de `unit_memberships_manage` para gerenciar RBAC.
Para delegar a estrutura a um administrador existente, manter seu papel nativo de
administrador e atribuir a CustomRole estrutural; o editor nativo de agentes
preserva o papel quando envia somente `custom_role_id`.

Bootstrap, funcionário JRC, UnitMembership, responsável, equipe e capacidade
continuam separados. Equipe ou atribuição de chamado não concede unidade.

## Auditoria separada — Responsáveis

Rota: `/app/accounts/:accountId/service-desk/assignees`.

| Item | Estado real |
| --- | --- |
| Lista, busca, unidade, paginação e prévia | Implementados em `CatalogView`, `CatalogQuery` e Presenter |
| Elegibilidade do responsável | AccountUser com UnitMembership ativa e capacidade `tickets_view`; operador só consulta unidades autorizadas |
| Atribuir responsável a chamado | Backend em `AssignTicketService`, validação em `BaseService#assignee`, policy `assign?` e UI `TicketOperations` |
| Transferir chamado | Serviço e fluxo operacional próprios, sem conceder membership |
| Criar/ativar/revogar autorização nessa lista | Não implementado nessa tela e não deve ser confundido com atribuição |
| Campos com “PENDENTE — operação não implementada” | Placeholder genérico de `CatalogView` nos campos desabilitados de prévia; não são comandos persistentes |
| Exclusão de vínculo | Não oferecida; revogação preserva histórico |

O documento CP3 `CP3_TELAS_E_ACOES.md`, seção 8, listava genericamente CRUD de
responsáveis/provisionamento como pendência para CP4. CP6 `CP6_BOTOES_FLUXOS.md`
(B-107 e D01) separou a consulta operacional da administração estrutural e retirou
o antigo controle “Novo registro”. A implementação atual segue essa separação.
Não há backend de “editar cadastro de responsável” dedicado nessa lista; a pessoa
é o AccountUser nativo, a autorização é UnitMembership e a atribuição pertence ao
chamado. Portanto, não se declara aquele CRUD genérico de CP3 concluído nessa tela.
A indicação genérica “PENDENTE” continua como dívida de clareza da prévia; não foi
alterada nesta correção nem usada como evidência de funcionalidade pronta.

## Validações locais

Ambiente Ruby/Rails: imagem de testes existente `jrc-nico-test:local`, Ruby 3.4.4,
PostgreSQL 16 descartável e Redis. Não foi construída imagem. Testes executados
com `RAILS_ENV=test` e `VITE_RUBY_AUTO_BUILD=false`.

| Validação | Resultado |
| --- | --- |
| RSpec requests/services/policies/models do Service Desk | 363 exemplos, zero falhas; quatro casos de concorrência reservados para execução separada |
| RSpec final da correção + concorrência habilitada | 13 exemplos aprovados: nove da correção e quatro de concorrência; zero pendentes |
| Bootstrap Super Admin, controller base, flag, migrations de teste e Custom Roles | 58 exemplos aprovados |
| Vitest Service Desk final | 407 testes, 15 arquivos, todos aprovados |
| Zeitwerk | All is good |
| Build frontend Vite production | Aprovado, 2m18s; não é build de imagem |
| RuboCop dos dois arquivos Ruby novos | Zero ocorrências |
| ESLint dos cinco arquivos JS/Vue tocados | Zero erros, 28 avisos (i18n/chaves dinâmicas/textos e convenções de testes), registrados separadamente |
| git diff --check | Aprovado |

Os testes novos cobrem criação, revogação, reativação, auditoria e releitura;
Account/Unit/AccountUser estrangeiros; administrador sem capacidade;
administração sem acesso operacional do autor; equipe sem vínculo; vínculo sem
capacidade; ambos concedidos; flag desligada. Vitest monta/desmonta a tela para
simular uma nova carga, verifica persistência via API e falha de confirmação.
Isso não substitui F5 e jornada humana em HTTPS no LAB.

RuboCop do controller continua com as 18 ocorrências das mesmas regras já presentes
na base (desconsiderando CRLF do arquivo temporário de comparação). A métrica de
complexidade de `members` aumenta pela projeção adicional. Não houve limpeza geral.
As dívidas globais anteriormente registradas — 655 RuboCop e 1.522 erros/7 avisos
ESLint — não foram reexecutadas nem declaradas corrigidas.
Build mantém avisos de Browserslist antigo, chunks grandes e asset de marca
resolvido em runtime. Versões, lockfiles e Dockerfile não foram alterados.

## Arquivos e preservação

Adicionados:
- `app/services/jrc_service_desk/membership_directory.rb`
- `spec/requests/api/v1/accounts/jrc_service_desk/unit_access_spec.rb`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/unitAccess.spec.js`
- este relatório.

Modificados:
- `app/controllers/api/v1/accounts/jrc_service_desk/structure_controller.rb`
- `app/javascript/dashboard/api/serviceDeskStructureClient.js`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/structure.js`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/views/StructureView.vue`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/views/SettingsView.vue`
- `app/javascript/dashboard/i18n/locale/en/jrcServiceDesk.json`

Nenhum arquivo removido. A formatação ESLint foi aplicada somente aos cinco
arquivos JS/Vue desta correção. Nenhuma migration criada ou alterada.
QR/Broker, CRM, softphone, Conversas, Calling, NICO, Campanhas, Cockpit, Email Center
e Calls Center não têm mudanças de código nesta entrega. Projetos não foi integrado.
Service Desk continua default false, ext_1 posição 9/máscara 256; Broker posição
11/máscara 1024; Flows inalterado. Nenhuma Account real foi modificada.

## Homologação pendente

Após revisão e autorização de publicação/deploy: entrar como administrador
estrutural explicitamente delegado; abrir a área de acessos; selecionar Matriz;
buscar Thiago Ribeiro LAB; conferir/conceder/revogar/reativar com motivo; verificar
recibo, recarregar e consultar novamente. Depois entrar como Thiago e verificar
que apenas unidade e capacidades concedidas permitem operações. Repetir os testes
negativos com outra empresa/usuário. A inicialização existente não deve ser repetida.

Esta etapa termina no commit local. Push, imagem, publicação e deploy dependem
de nova autorização.
