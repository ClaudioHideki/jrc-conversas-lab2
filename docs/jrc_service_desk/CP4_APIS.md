# CP4 - contratos HTTP

CP4 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE

PENDENTE — validação nativa em ambiente Docker/local

28 combinacoes de verbo/caminho (27 contratos, contando PATCH/PUT como a mesma atualizacao). Inventario do codigo; nao e saida de rails routes executado.

Todos herdam BaseController CP1 atraves de OperationsController: autenticacao nativa, Account/flag, contexto operacional fresco, unidade vinculada e Pundit. GET usa snapshot REPEATABLE READ quando fora de transacao; Cache-Control no-store. Nao existe endpoint de concessao/provisionamento.

| METODO | CAMINHO (apos o prefixo) | CONTROLLER | SERVICE | POLICY |
|---|---|---|---|---|
| GET | `/ui_context` | `UiContextController#show` | UiContextService | LookupPolicy#index? |
| GET | `/dashboard` | `DashboardController#show` | DashboardService / TicketQuery / KpiCounts | TicketPolicy#index? / Scope |
| GET | `/queues` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/priorities` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/categories` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/statuses` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/units` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/operator_companies` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/assignees` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/requesters` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/teams` | `LookupsController#index` | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas |
| GET | `/tickets` | `TicketsController#index` | TicketQuery / Presenter | TicketPolicy#index? / Scope |
| GET | `/tickets/:id` | `TicketsController#show` | Presenter | TicketPolicy#show? / Scope |
| POST | `/tickets` | `TicketsController#create` | CreateTicketWorkflowService -> CreateTicketService / LinkConversationService | TicketPolicy#create? + ConversationPolicy se vinculo |
| PATCH | `/tickets/:id` | `TicketsController#update` | UpdateTicketService | TicketPolicy#update? |
| PUT | `/tickets/:id` | `TicketsController#update` | UpdateTicketService | TicketPolicy#update? |
| POST | `/tickets/:id/assign` | `TicketsController#assign` | AssignTicketService | TicketPolicy#assign? |
| POST | `/tickets/:id/transfer` | `TicketsController#assign` | AssignTicketService | TicketPolicy#assign? |
| POST | `/tickets/:id/work_status` | `TicketsController#work_status` | ChangeWorkStatusService | WorkStatusPolicy#change_work_status? |
| POST | `/tickets/:id/notes` | `TicketsController#add_note` | AddNoteService | TicketPolicy#add_note? |
| POST | `/tickets/:id/conversations` | `TicketsController#link_conversation` | LinkConversationService | TicketPolicy#link_conversation? + ConversationPolicy |
| GET | `/tickets/:id/notes` | `TicketsController#related` | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro |
| GET | `/tickets/:id/events` | `TicketsController#related` | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro |
| GET | `/tickets/:id/sla` | `TicketsController#related` | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro |
| GET | `/tickets/:id/conversations` | `TicketsController#related` | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro |
| GET | `/tickets/:id/status_options` | `TicketsController#related` | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro |
| GET | `/tickets/:id/notes/:record_id` | `TicketsController#related_item` | Presenter | TicketPolicy#show? + policy do registro |
| GET | `/tickets/:id/conversations/:record_id` | `TicketsController#related_item` | Presenter | TicketPolicy#show? + policy do registro |

## Envelopes e identidades

Resposta versionada: contract_version=1 e account_id canonico em string. Contexto tambem contem user_id, unidades, operadora derivada e capacidades. Nenhum parametro concede Account ou unidade.
Listas: items + meta.total/page/per_page. Vazio somente apos consulta efetiva. Falha nao e convertida em lista vazia.
Ticket: envelope ticket com projeccao explicita, lock_version, relacoes nomeadas e permissoes. Numero e o ID real do ticket, sem prefixo/numeracao ficticia.
Escritas: applied=true, operation, ticket_id e result_id quando ha nota/vinculo. Esse retorno NAO substitui a releitura GET que a interface exige.
Responsavel: assignee_account_user_id nas escritas; assignee_id nos filtros representa o MESMO AccountUser, nao User nem UnitMembership.
Conversa: conversation_id e ID interno do banco; display_id nao e aceito como uma conversao implicita.

## Comandos de escrita

POST /tickets recebe {unit_id, ticket:{title,description,requester_id,status_id,priority_id,category_id?,queue_id?,team_id?,assignee_account_user_id?}, conversation_id?} e header Idempotency-Key.
PATCH/PUT recebe {ticket:{title?,description?,priority_id?,category_id?}, expected_lock_version}.
POST /assign e /transfer recebem {assignment:{assignee_account_user_id?,queue_id?,team_id?}, expected_lock_version}; null remove a relacao opcional. A unidade nao muda.
POST /work_status recebe {status_id,expected_lock_version}. Somente fase open -> open, status ativo configurado; nenhuma resolucao/pausa implicita.
POST /notes recebe {note:{body}} e Idempotency-Key. Nenhuma nota publica ou arquivo nesse comando.
POST /conversations recebe {conversation_id}.
Campos desconhecidos e IDs frouxos sao rejeitados, nao ignorados. Nenhum wrapper automatico de parametros no novo controller.

## Falhas e concorrencia

401: autenticacao nativa. 403: acesso/flag/escopo negado. 404: registro nao encontrado no escopo (code=not_found), sem revelar existencia fora dele.
422: entrada/validacao recusada. 409: versao/chave/constrangimento concorrente. SQL bruto/credenciais nao sao retornados.
CP2 continua fornecendo transacoes, lock por unidade, locks de identidade/grants e controle otimista. GETs nao prometem revogacao retroativa de dados ja retornados; cada novo request reconfirma autorizacao. Medir locks e snapshot de leitura nativamente.

## Limites

Sem endpoints para transicao de fase, calculador de SLA, arquivo, automacao, cadastro/provisionamento, Projetos ou integracao externa.
CatalogQuery avalia policies nativas por registro ANTES de total/paginacao em contatos/equipes e elegibilidade dos responsaveis. Essa varredura e consultas por registro precisam de ensaio de desempenho; nao afirmar escalabilidade ja comprovada.
Eventos financeiros/snapshots brutos/blobs nao acompanham acesso generico ao chamado. Varios scopes antigos permanecem restritivos e nao foram ampliados para alimentar telas.
