# NICO: conectores nativos e limites de cobertura

Base auditada: `052e439d763ab832ff5943ade8ae8e30cacfae6b`. Este documento descreve os conectores acrescentados na branch de trabalho; não declara implantação em LAB nem resultado de teste. O Service Desk real é **JrcServiceDesk R2**. Não há `JrcSupport` ou tabelas `jrc_support_tickets` para integrar.

## Contrato de execução

`ToolCatalog` incorpora `DomainToolCatalog::TOOLS`; `ToolExecutor#call` encaminha apenas os nomes desse catálogo para `DomainActions#call`. O adaptador usa serviços nativos ou consultas com escopo nativo. Não aceita URL, verbo HTTP, classe Ruby, nome de método, SQL ou chave de idempotência definidos pelo modelo. As ações marcadas como mutação entram na confirmação normal do `OperatorSession`.

Referências: `app/services/jrc_nico/tool_catalog.rb:60`, `app/services/jrc_nico/tool_executor.rb:9`, `app/services/jrc_nico/domain_actions.rb:17`, `app/services/jrc_nico/operator_session.rb:454`.

Os 35 comandos novos (33 do adaptador nativo e duas pontes finitas de tarefa) permanecem fora de `DelegatedActions::GROUPS`. O executor também os recusa quando recebe `customer_notice` ou um comando com `source_notice_id`. Portanto, esta expansão não concede autonomia de atendimento ao cliente, nem transforma um pedido recebido de cliente em autorização do operador.

`*` nas tabelas significa obrigatório. Os campos opcionais não informados permanecem ausentes. IDs são inteiros positivos; `page` aceita 1–20; strings têm limite de 4.000 caracteres. Versões de lock aceitam zero. Campos desconhecidos são recusados antes do dispatch. `fields` de transição é um objeto de até 30 campos escalares; `evidence_note_ids` aceita até 30 IDs, com validação final pelo ciclo de vida nativo. `user_id` da agenda aceita ID ou `all`; `mine` do R2 aceita a string `true`.

Referências: `app/services/jrc_nico/domain_tool_catalog.rb:39`, `app/services/jrc_nico/tool_catalog.rb:89`.

## Matriz dos 33 comandos novos

| Módulo / ferramenta | Argumentos | Execução e autoridade |
|---|---|---|
| R2 `service_desk_context` | nenhum | `UiContextService`; `ModulePolicy` e unidades visíveis |
| R2 `service_desk_lookup` | `resource* unit_id operator_company_id q page` | `CatalogQuery` + `Presenter.catalog`; catálogos finitos: units, operator_companies, queues, priorities, categories, statuses, assignees, requesters, teams; lookups nativos exigem unidade |
| R2 `list_service_tickets` | `unit_id status_id priority_id category_id queue_id assignee_id q mine page` | `TicketQuery`; `TicketPolicy::Scope`; até 20 por página |
| R2 `read_service_ticket` | `ticket_id*` | `JrcOperations::Access.ticket!` + `Presenter.ticket` |
| R2 `create_service_ticket` | `unit_id* title* requester_id* status_id* priority_id* description category_id queue_id team_id assignee_account_user_id service_id conversation_id` | `CreateTicketWorkflowService`; idempotência do comando; criação, serviço e conversa nativos |
| R2 `update_service_ticket` | `ticket_id* expected_lock_version* title description priority_id category_id` | `UpdateTicketService`; política de edição e prioridade; lock otimista |
| R2 `assign_service_ticket` | `ticket_id* expected_lock_version* assignee_account_user_id queue_id team_id` | `AssignTicketService`; permissão e escopo da unidade |
| R2 `transfer_service_ticket` | mesmos campos de atribuição | `TransferTicketService`; permissão própria de transferência |
| R2 `add_service_ticket_note` | `ticket_id* body*` | `AddNoteService`; nota interna e idempotência |
| R2 `read_service_ticket_lifecycle` | `ticket_id* page` | `LifecycleReadService`; `LifecycleActionPolicy.inspect?`; opções reais, versões, SLA e histórico filtrado |
| R2 `transition_service_ticket` | `ticket_id* rule_key* expected_lock_version* expected_policy_version_id* reason_code note solution evidence_note_ids fields` | `LifecycleTransitionService`; regra publicada/aplicável, locks, evidências, permissões e idempotência |
| R2 `link_service_ticket_conversation` | `ticket_id* conversation_id*` | `LinkConversationService`; ambas as pontas autorizadas |
| Projetos `list_projects` | `query status page` | `JrcOperations::Access.projects`; até 20 |
| Projetos `read_project` | `project_id*` | escopo + `Authorization`; dados básicos e até 50 colunas; sem orçamento ou atividade recente |
| Projetos `list_project_tasks` | `project_id* status page` | escopo do projeto + `projects.task.view`, inclusive por registro; até 20 |
| Projetos `read_project_task` | `project_id* task_id*` | mesma autorização; tarefa da conta e do projeto informados |
| Projetos `create_project` | `name* key description visibility contact_id starts_on due_on priority template_id deal_id ticket_id conversation_id` | `Projects::Create`; modelo ativo da conta; no máximo uma origem; negócio ganho quando origem comercial |
| Projetos `update_project` | `project_id* lock_version* name description status visibility contact_id owner_id starts_on due_on acceptance_notes priority` | `Projects::Update`; capacidades nativas, transferência, conclusão, aceite, locks |
| Projetos `move_project_task` | `project_id* task_id* column_id* lock_version* before_task_id` | `Tasks::Move`; coluna real, WIP, dependências, política e versão |
| Agenda `read_operations_agenda` | `from to source view user_id` | `JrcOperations::Agenda`; CRM e Projetos; máximo 366 dias; recusa mais de 50 resultados e pede período menor |
| Vínculos `read_operation_links` | `project_id ticket_id deal_id contact_id conversation_id` | `Related`; exatamente uma origem; `Linker.read` revalida todas as pontas |
| Vínculos `link_project_record` | `project_id* ticket_id task_id deal_id conversation_id` | `Linker.create!`; reutiliza vínculo existente e audita criação |
| Vínculos `unlink_project_record` | `link_id* project_id ticket_id deal_id` | `Linker.destroy!`; exatamente uma origem; recibo auditado permite replay sem nova exclusão |
| Pedidos `list_sales_orders` | `status page` | `OperationalAccess.crm_scope(SalesOrder)`; até 20 |
| Pedidos `read_sales_order` | `sales_order_id*` | mesmo escopo; projeção explícita de IDs, estado e valores |
| Pedidos `convert_proposal_to_order` | `proposal_id*` | proposta autorizada + `ProposalPolicy.update?` + `ProposalToOrderService`; só proposta aceita, reutiliza pedido |
| Contratos `list_contracts` | `status page` | escopo CRM do proprietário ou administrador; até 20 |
| Contratos `read_contract` | `contract_id*` | mesma autorização; vigência, estado e assinatura registrada |
| Comissões `list_commissions` | `status page` | escopo CRM por `user_id`; até 20; sem liberação/pagamento |
| Backoffice `list_backoffice_requests` | `status page` | escopo CRM por `owner_id`; até 20 |
| Backoffice `read_backoffice_request` | `backoffice_request_id*` | mesmo escopo; etapa, estado, prioridade, prazo e IDs |
| Metas `list_sales_goals` | `status page` | administrador com acesso CRM; `GoalProgressService`; até 20 |
| Comissões `list_commission_programs` | `page` | administrador com acesso CRM; projeção básica; até 20 |

Fonte exata dos schemas: `app/services/jrc_nico/domain_tool_catalog.rb:4`. Dispatch e serviços: `app/services/jrc_nico/domain_actions.rb:17`. Resolução de permissões e recursos do histórico: `app/services/jrc_nico/domain_access.rb:22`.

`conversation_id` significa **display_id** no contrato NICO; o adaptador resolve a conversa visível e só então passa sua chave interna para serviços R2. `assignee_account_user_id` é **AccountUser.id**, não User.id. A chave nativa é derivada do comando persistido (`nico_<command.id>_<request_id>`), compatível com os validadores nativos R2 e Projetos; o comando deve pertencer à conta e ao operador atuais.

## Duas pontes autenticadas para tarefas

| Ferramenta | Argumentos | Destino |
|---|---|---|
| `create_project_task` | `project_id* title* description priority board_column_id assignee_id parent_id estimated_minutes starts_on due_on labels` | POST `/api/v1/accounts/:account_id/projects/projects/:project_id/tasks`, envelope `task` |
| `update_project_task` | `project_id* task_id* lock_version* title description priority assignee_id parent_id estimated_minutes starts_on due_on labels clear_assignee clear_parent` | PATCH `/api/v1/accounts/:account_id/projects/projects/:project_id/tasks/:task_id`, envelope `task` |

`ModuleActions` verifica o projeto, `projects.task.view` para acompanhar o resultado e a capacidade nativa de escrita; edição também verifica a tarefa da conta/projeto e sua capacidade específica. O histórico preserva a referência ao projeto e à leitura de tarefas (mais a tarefa exata na edição). A validação se repete no claim, e o endpoint autenticado reaplica suas próprias regras. O adaptador não cria/atualiza `Task` diretamente. `estimated_minutes` aceita inteiro não negativo; versão zero é válida; os indicadores `clear_assignee`/`clear_parent` geram `null` na API e não podem ser combinados com um ID substituto. O estado não é parâmetro de edição: conclusão e troca de estado usam `move_project_task`, conforme a coluna real.

O POST nativo de tarefa **não implementa Idempotency-Key**. Esta integração preserva o protocolo existente: confirmação → `browser_pending` → claim atômico único → `executing`. Uma segunda tentativa de claim é recusada. O helper faz uma chamada, sem retry; timeout/erro 5xx é `unknown` e bloqueia continuação automática. Outro comando explícito exige conferir o projeto antes de repetir; não se promete criação idempotente entre comandos distintos. A resposta da aba é identificada pelo fluxo como resultado informado pela aba.

Referências: `app/services/jrc_nico/module_actions.rb:2–16` e `:45`; `app/services/jrc_nico/operator_session.rb:102–135`; `app/javascript/dashboard/components-next/jrcCopilot/nicoModuleActions.js:18`; `JrcCopilotPanel.vue:335–391`; `app/controllers/jrc_projects/api/v1/tasks_controller.rb:29–67`.

## Dados retornados e histórico

Cada registro retornado possui tipo e ID. As listagens de projetos/chamados agregam também referências dos campos relacionados no `resources` do envelope. O histórico e as notificações revalidam esses recursos usando a mesma conta/operador e os verificadores nativos.

Chamados, catálogos e histórico R2 preservam `page/per_page`, mas o conector NICO omite `meta.total`. Vínculos omitem `tickets_total/projects_total`. Esses totais incluíam registros fora da amostra e não tinham referências suficientes para revalidar o histórico após uma revogação. A resposta representa somente a página consultada, nunca o total da conta; uma página cheia não prova que a consulta terminou. As ferramentas paginadas aceitam páginas 1–20; refine os filtros quando esse limite for insuficiente. Vínculos retornam a amostra nativa de até 30 chamados, 30 projetos e 100 relações, sem prometer inventário completo. A API e a interface nativas mantêm seus próprios totais.

- R2: solicitante requer sua política de contato e `view_customer?`; SLA é acompanhado de `view_sla?`; conteúdo protegido do histórico de transições requer `view_notes?`. Equipes e operadores retornados também recebem referências. Consultas de solicitantes preservam a exigência de `customers_view` e `ContactPolicy.index?`.
- Vínculos R2: o solicitante e seu ID são removidos quando `view_customer?` negar acesso. Na origem chamado, conversas diretas e relações com conversa exigem também `view_conversations?`; o histórico conserva os marcadores dessas permissões junto aos recursos. Acesso nativo à conversa não substitui o grant R2 para consultar sua associação ao chamado.
- Alteração, atribuição e transferência R2 retornam recibo mínimo de aplicação, como a API nativa. Transferir um chamado pode remover legitimamente o acesso de leitura do operador; o recibo não tenta reler seus detalhes, e o histórico continua revalidando o recurso.
- Projetos: usa o serializer básico; remove o contato se sua própria política negar acesso; contagens de tarefas e colunas só são expostas com `projects.task.view`, cuja referência é revalidada no histórico. Orçamento, membros, horas e atividade recente não são incluídos por acidente no comando de leitura básico.
- Vínculos: guarda a origem mesmo quando a consulta é vazia; vínculos retornados são revalidados por `Linker.read`; contatos embutidos passam por `OperationalAccess.contact`. Detalhes de empresa/organização não fazem parte desta projeção.
- Agenda: mantém data simples nas tarefas e data/hora nos itens CRM; remove contagens de outras visualizações e diretório de usuários da resposta. Cada compromisso exibido tem referência de origem. `service_desk` informa `native_tasks_not_available`.

Referências: `domain_actions.rb:73–116`, `domain_actions.rb:141–153`, `domain_actions.rb:184–207`, `domain_actions.rb:250–289`; `app/models/jrc_nico/notice.rb:50–130`; `app/services/jrc_nico/operator_session.rb:169–204` e `:465–489`.

## Operações fora do novo conector: classificação exata

“Não integrado” significa que há implementação nativa, mas nenhum comando NICO desta expansão. Não significa que a operação seja tecnicamente impossível. “Controller” significa que a sequência completa de autorização, normalização, lock, validação, efeitos e auditoria ainda está no controller: chamar diretamente o model ou um calculador parcial duplicaria/ignoraria essa regra. A alternativa é extrair um serviço nativo ou desenvolver uma ponte de navegador finita para o endpoint existente, com confirmação e tratamento de resultado desconhecido. Um catálogo genérico de URLs não foi criado.

| Módulo | Fora do conector / classificação | Evidência e motivo |
|---|---|---|
| Pedidos | Criação manual, atualização, anexos, PDF e preview: **não integrado; controller/UI de arquivo** | `app/controllers/api/v1/accounts/crm/sales_orders_controller.rb:24`, `:49`, `:83`, `:102`, `:119`, `:152`. A criação manual e a sincronização comercial ficam no controller; não há contrato reutilizado de idempotência para essa sequência. A conversão de proposta aceita é a exceção já integrada. |
| Contratos | Criar/editar, preparar/registrar assinatura, renovar, aditivo: **não integrado; controller**. Documentos/PDF: **UI de arquivo** | `app/controllers/api/v1/accounts/crm/contracts_controller.rb:16`, `:31`, `:85`, `:102`, `:119`, `:131`, `:156`, `:178`. Renovação e aditivo criam novos registros sem a idempotência de comando reutilizada pelo adaptador. `send_for_signature` registra referência/estado: não comprova envio real a um provedor externo. |
| Metas | Criar/editar/distribuir, dashboard e visão de agente: **não integrado; controller** | `app/controllers/api/v1/accounts/crm/goals_controller.rb:9`, `:18`, `:30`, `:66`, `:81`. O escopo por alocações e os cálculos do dashboard estão em métodos privados; a nova leitura usa o escopo administrativo inequívoco e o serviço de progresso já existente. |
| Comissões | Criar/editar, liberar, pagar, estornar, resumo/histórico, programas completos e simulação: **não integrado; controller** | `app/controllers/api/v1/accounts/crm/commissions_controller.rb:38`, `:48`, `:113`, `:128`; `commission_programs_controller.rb:15`, `:20`, `:25`, `:65`. Transições, justificativa de estorno, cálculo e auditoria não formam um serviço de mutação reutilizável. `RulesEngine` é cálculo, não autorização/pagamento. |
| Backoffice | Criar/editar, avançar, documentos, pendências, provisionar e reabrir: **não integrado; controller/UI de arquivo** | `app/controllers/api/v1/accounts/crm/backoffice_requests_controller.rb:36`, `:53`, `:79`, `:88`, `:104`, `:133`, `:147`, `:162`, `:188`, `:202`. Fluxos coordenam estado, documentos, locks e auditoria; faturamento e pagamentos usam controllers financeiros próprios. |
| Equipe comercial | Indicadores de gestão: **navegação; consulta ainda não integrada** | `app/controllers/api/v1/accounts/crm/management_controller.rb:6`. `list_team` preexistente lista diretório nativo de usuários/equipes; não administra a Equipe Comercial nem equivale a seus indicadores. |
| R2 operação | Painel, histórico de eventos, lista/leitura de notas, contexto do cliente, conversas vinculadas, SLA detalhado/snapshots: **APIs nativas existentes, não integradas individualmente** | `app/controllers/api/v1/accounts/jrc_service_desk/tickets_controller.rb`, `dashboard_controller.rb`, `native_context_controller.rb`. O resumo do chamado e ciclo de vida expõem apenas os campos descritos acima. Mudança de estado de trabalho já é representável por regra explícita de ciclo de vida, sem novo setter livre de status. |
| R2 administração | Estrutura, empresas operadoras, unidades, concessões, catálogos/configuração, serviços, políticas e publicação: **serviços/APIs nativos, não integrados** | `app/controllers/api/v1/accounts/jrc_service_desk/structure_controller.rb`, `configuration_controller.rb`, `service_definitions_controller.rb`, `lifecycle_policies_controller.rb`. Exigem comandos administrativos próprios, schemas e testes negativos específicos; a expansão operacional não concede nem administra escopo de unidade. |
| R2 governança futura | Páginas SLA, catálogo, knowledge, aprovações, problemas, mudanças, ativos, contratos, automações, pesquisas e relatórios: **navegação planejada** | `app/javascript/dashboard/routes/dashboard/serviceDesk/routeDefinitions.js:11–21` usa `page: 'planned'`. Isto não apaga os serviços operacionais SLA/catálogos que já existem. `UiContextService` informa relatório operacional indisponível. |
| Projetos tarefas | Criar/editar: **ponte autenticada integrada**. Excluir, comentários/checklist: **não integrado; controller** | `app/controllers/jrc_projects/api/v1/tasks_controller.rb:29`, `:50`, `:79`, `:95`; controllers de comentários/checklist. A ponte finita preserva validadores, edição de projeto, WIP, parentesco, responsável e auditoria. Mover/concluir já usa serviço completo. Os demais endpoints são candidatos a pontes dedicadas, não operações inerentemente impossíveis. |
| Projetos planejamento | Dependências escrever/remover: **não integrado; controller envolvendo algoritmo**. Caminho crítico e dependências ler: **consulta nativa não integrada** | `app/controllers/jrc_projects/api/v1/planning_controller.rb:5`, `:9`, `:14`, `:29`. `DependencyGraph` sozinho não executa autorização, lock e auditoria do controller. |
| Projetos gestão | Membros, marcos, sprints, riscos, issues, decisões, modelos, quadros/colunas: **não integrado; controllers** | `app/controllers/jrc_projects/api/v1/resource_controller.rb:17`, `:30`, `:48`, `:80`, `:97`; subclasses e controllers de colunas. Contratos de contexto e capacidades diferem por recurso. |
| Projetos financeiro/relatórios | Orçamento, apontamentos, aprovação de horas, relatórios/CSV, portfólio: **não integrado; políticas específicas/controller** | `app/controllers/jrc_projects/api/v1/budgets_controller.rb:5`, `:11`; `time_entries_controller.rb:10`, `:23`; `reports_controller.rb:6`, `:11`; `portfolio_controller.rb`. A existência de FinancialProjection não autoriza expor orçamento sob apenas project.view. |
| Projetos arquivos | Upload/download/exclusão: **não integrado; UI de arquivo** | `app/controllers/jrc_projects/api/v1/files_controller.rb`. Não há origem de arquivo implicitamente autorizada pelo texto do modelo. |
| Agenda | Criar/editar/apagar “compromisso unificado”: **não existe no domínio de projeção** | `app/services/jrc_operations/agenda.rb:3`. Alteração deve usar o recurso original: atividade CRM ou tarefa de Projeto. R2 não fornece tarefas nativas para essa projeção. |
| Broker e Flows | Administração, gráficos, publicação e controle de execução: **não integrados no NICO** | Nenhum nome em `DomainToolCatalog` ou `ModuleActions` despacha essas ações. `app/services/jrc_flows/actions.rb` contém a ação de entrada Flows→NICO; isso não concede a direção NICO→administração de Flows. Regras `AutomationActions` são outro módulo. |
| Contatos/Conversas/Campanhas/Calls | **Conectores preexistentes preservados**, com limites específicos | `app/services/jrc_nico/tool_executor.rb`, `module_actions.rb`, `automation_actions.rb`; a expansão de domínio não cria novos canais, não remove permissões e não administra telefonia. `call_contact`, `call_control`, `open_video`, `whatsapp_call` dependem da aba/canal/dispositivo; não são chamadas de servidor em segundo plano. |
| Leads/Negócios/Produtos/Propostas | **Conectores preexistentes preservados** | `tool_catalog.rb`, `module_actions.rb`, `commercial_actions.rb`. Há dispatch real para leitura/mutação; alguns comandos são ponte autenticada de navegador. A presença em `TaskCatalog` isoladamente continua sendo orientação/navegação, sem executor implícito. |

Filtros adicionais pedidos na revisão: `ContractsController#index:5` não define filtro por período; `ProjectsController#index:6–16` oferece status, prioridade e busca textual, sem filtro de projetos atrasados. Esta entrega não inventa uma semântica temporal de contratos (início, fim, assinatura ou criação) nem equipara prazo de projeto a prazo de tarefa. A agenda permite `source=projects, view=overdue` para **tarefas** atrasadas. `list_contracts` mantém `status/page` e `list_projects` mantém `query/status/page`.

## Verificação e inventário sem executar operações reais

O catálogo novo é estático e pode ser lido sem Rails, conexão ao banco ou chamada de modelo. Uma matriz automática deve cruzar **nomes do catálogo → branches do dispatch → serviços/controllers → policies/scopes → arquivos de testes**, e marcar ausência de qualquer etapa. O schema não deve ser inferido apenas de texto de botão: deve usar campos finitos do catálogo e parâmetros permitidos do endpoint nativo. A resolução de rotas/handlers frontend precisa permanecer uma camada separada de evidência, pois navegação não prova mutação.

O arquivo histórico `docs/qa/lab-homologacao-20260929-menu.csv` contém 105 entradas de menu e evidência estática, não execução de operações. Não foi encontrado um gerador versionado original dessa planilha na inspeção de scripts. Os scripts E2E de revalidação operacional não são extratores passivos: podem escrever dados e chamar o runtime.

Testes de contrato acrescentados: `spec/services/jrc_nico/domain_actions_spec.rb` contém 26 exemplos cobrindo idempotência, conflito de chave, versão zero/stale, unidade/conta estrangeira, revogação R2/Projetos, schemas, fora de autonomia, contatos vinculados, grants adicionais do histórico, remoção idempotente de vínculos e claim único/revogação da ponte de tarefas. Inclui atribuição/transferência com perda legítima de leitura, redação/revogação histórica de solicitantes e conversas de chamados e ausência de totais agregados fora da amostra. O executor principal da tarefa é responsável pelo resultado registrado da suíte Rails, sem concorrência no banco.

Validação local do helper de navegador: `nicoModuleActions.spec.js` passou **9/9**, incluindo os três exemplos novos de tarefa; ESLint dos dois arquivos JavaScript alterados passou. As chamadas HTTP da suíte são simuladas, sem operações reais.

Infraestrutura já existente: `scripts/nico-specs.rb`; suites Rails R2 em `spec/requests/api/v1/accounts/jrc_service_desk/`; Projetos/Agenda em `spec/requests/api/v1/accounts/jrc_operations/`; CRM comercial em `spec/requests/api/v1/accounts/crm/`; `vitest.nico.config.ts`, `vitest.crm-phase1.config.mjs`; testes puros em `test/jrc_operations/` e `test/jrc_consolidation/`. RSpec cria fixtures no banco de teste; testes puros/projeções e inspeção estática não substituem a prova de autorização negativa do backend.
