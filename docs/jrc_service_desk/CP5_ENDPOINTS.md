# CP5 - endpoints acumulados

PENDENTE — validação nativa em ambiente Docker/local

39 combinacoes verbo/caminho. Duas novas leituras; transferencia tem destino proprio.
A API nativa CustomRoles nao foi duplicada e nao pertence a esse prefixo.

| METODO | CAMINHO | CONTROLLER | SERVICE | POLICY | STATUS |
|---|---|---|---|---|---|
| GET | /api/v1/accounts/:account_id/jrc_service_desk/ui_context | UiContextController#show | UiContextService | ModulePolicy#show? + per-action capabilities | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/dashboard | DashboardController#show | DashboardService / TicketQuery / KpiCounts | ModulePolicy#dashboard? + TicketPolicy::Scope | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/queues | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/priorities | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/categories | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/statuses | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/units | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/operator_companies | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/assignees | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/requesters | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/teams | LookupsController#index | CatalogQuery / Presenter | LookupPolicy + policies do recurso e nativas | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets | TicketsController#index | TicketQuery / Presenter | TicketPolicy#index? / Scope | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id | TicketsController#show | Presenter | TicketPolicy#show? / Scope | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/tickets | TicketsController#create | CreateTicketWorkflowService -> CreateTicketService / LinkConversationService | TicketPolicy#create? + ConversationPolicy se vinculo | PENDENTE |
| PATCH | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id | TicketsController#update | UpdateTicketService | TicketPolicy#show? + update?/change_priority? per field | PENDENTE |
| PUT | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id | TicketsController#update | UpdateTicketService | TicketPolicy#show? + update?/change_priority? per field | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/assign | TicketsController#assign | AssignTicketService | TicketPolicy#assign? | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/transfer | TicketsController#transfer | TransferTicketService | TicketPolicy#transfer? | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/work_status | TicketsController#work_status | ChangeWorkStatusService | WorkStatusPolicy + LifecycleActionPolicy + regra publicada work_status | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/notes | TicketsController#add_note | AddNoteService | TicketPolicy#add_note? | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/conversations | TicketsController#link_conversation | LinkConversationService | TicketPolicy#link_conversation? + ConversationPolicy | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/notes | TicketsController#related | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/events | TicketsController#related | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/sla | TicketsController#related | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/conversations | TicketsController#related | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/status_options | TicketsController#related | RelatedRecordsQuery / Presenter | TicketPolicy#show? + policy de cada registro | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/notes/:record_id | TicketsController#related_item | Presenter | TicketPolicy#show? + policy do registro | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/conversations/:record_id | TicketsController#related_item | Presenter | TicketPolicy#show? + policy do registro | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/lifecycle_policies | LifecyclePoliciesController#index | Query autorizado por unidade | LifecyclePolicyPolicy + lifecycle_policies_manage + UnitMembership | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/lifecycle_policies/:id | LifecyclePoliciesController#show | Projection explicita | LifecyclePolicyPolicy + lifecycle_policies_manage + UnitMembership | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/lifecycle_policies | LifecyclePoliciesController#create | PublishLifecyclePolicyService | LifecyclePolicyPolicy + lifecycle_policies_manage + UnitMembership | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/service_definitions | ServiceDefinitionsController#index | Consulta paginada por unidade | ServicePolicy | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/service_definitions/:id | ServiceDefinitionsController#show | Projection explicita | ServicePolicy | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/service_definitions | ServiceDefinitionsController#create | CreateServiceDefinitionService | ServicePolicy | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/lifecycle | LifecycleController#show | LifecycleReadService | LifecycleActionPolicy#inspect? (tickets/sla/history) | PENDENTE |
| POST | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/lifecycle | LifecycleController#create | LifecycleTransitionService | LifecycleActionPolicy#action? + explicit pinned policy | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/lifecycle/transitions/:transition_id | LifecycleController#transition | LifecycleReadService#transition | TicketPolicy#view_history? + exact ticket/unit | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/customer_context | NativeContextController#customer | CustomerContextService | TicketPolicy#view_customer? + native Contact/Company | PENDENTE |
| GET | /api/v1/accounts/:account_id/jrc_service_desk/tickets/:id/conversations/:record_id/navigation | NativeContextController#conversation_navigation | ConversationNavigationService | TicketConversationPolicy + native ConversationPolicy | PENDENTE |
