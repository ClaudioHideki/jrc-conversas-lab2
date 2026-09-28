# CP6 atualizado - permissoes nativas

**CANDIDATO PARA HOMOLOGAÇÃO — VALIDAÇÃO NATIVA PENDENTE**

**PENDENTE — validação nativa em Docker/servidor**

| CAPACIDADE | FINALIDADE | AGENTE DEFAULT | ADMIN DEFAULT | PRE-REQUISITOS | ESCOPO | POLICY | STATUS |
|---|---|---|---|---|---|---|---|
| jrc_service_desk_module_view | Visualizar modulo | True | True | [] | Required active; no admin/Team bypass | ModulePolicy#show? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_tickets_view | Visualizar chamados | True | True | ["module_view"] | Required active; no admin/Team bypass | TicketPolicy#index?/show?/Scope | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_tickets_view_all | Visualizar todos os chamados das unidades vinculadas | False | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketPolicy::Scope (same units only) | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_tickets_create | Criar chamado | True | True | ["tickets_view", "lookups_view", "customers_view"] | Required active; no admin/Team bypass | TicketPolicy#create? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_tickets_edit | Editar dados do chamado | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketPolicy#update? + field checks | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_tickets_assign | Atribuir chamado | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketPolicy#assign? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_tickets_transfer | Transferir na mesma unidade | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketPolicy#transfer? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_priority_change | Alterar prioridade | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketPolicy#change_priority? + field checks | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_work_status_change | Alterar status de trabalho | True | True | ["tickets_view", "history_view", "sla_view"] | Required active; no admin/Team bypass | WorkStatusPolicy + published rule | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_pause | Pausar | True | True | ["tickets_view", "history_view", "sla_view"] | Required active; no admin/Team bypass | LifecycleActionPolicy#action? + pinned rule | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_resume | Retomar | True | True | ["tickets_view", "history_view", "sla_view"] | Required active; no admin/Team bypass | LifecycleActionPolicy#action? + pinned rule | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_resolve | Resolver | True | True | ["tickets_view", "history_view", "sla_view"] | Required active; no admin/Team bypass | LifecycleActionPolicy#action? + pinned rule | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_close | Encerrar | True | True | ["tickets_view", "history_view", "sla_view"] | Required active; no admin/Team bypass | LifecycleActionPolicy#action? + pinned rule | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_cancel | Cancelar | True | True | ["tickets_view", "history_view", "sla_view"] | Required active; no admin/Team bypass | LifecycleActionPolicy#action? + pinned rule | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_reopen | Reabrir | True | True | ["tickets_view", "history_view", "sla_view"] | Required active; no admin/Team bypass | LifecycleActionPolicy#action? + pinned rule | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_notes_view | Consultar notas internas | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketNotePolicy | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_notes_add | Adicionar nota interna | True | True | ["notes_view"] | Required active; no admin/Team bypass | TicketPolicy#add_note? + TicketNotePolicy#create? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_history_view | Consultar historico | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketEventPolicy + LifecycleReadService | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_conversations_view | Consultar vinculos de conversa | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketConversationPolicy + native ConversationPolicy | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_conversations_link | Relacionar conversa | True | True | ["conversations_view"] | Required active; no admin/Team bypass | TicketPolicy#link_conversation? + native ConversationPolicy | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_sla_view | Visualizar SLA operacional | True | True | ["tickets_view"] | Required active; no admin/Team bypass | SlaMilestonePolicy / LifecycleActionPolicy | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_contract_conditions_view | Consultar condicoes contratuais restritas | False | True | ["sla_view"] | Required active; no admin/Team bypass | SlaSnapshotPolicy#show?/Scope | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_sla_snapshots_record | Registrar snapshot de SLA | False | True | ["contract_conditions_view"] | Required active; no admin/Team bypass | SlaSnapshotPolicy#create? | PENDENTE FUNCIONAL |
| jrc_service_desk_lookups_view | Consultar seletores operacionais | True | True | ["module_view"] | Required active; no admin/Team bypass | LookupPolicy + resource/native policies | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_customers_view | Consultar contexto do cliente | True | True | ["tickets_view"] | Required active; no admin/Team bypass | TicketPolicy#view_customer? + native Contact/Company policies | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_queues_manage | Gerenciar filas | False | True | ["settings_view", "lookups_view"] | Required active; no admin/Team bypass | ConfigurationPolicy (Queue) | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_categories_manage | Gerenciar categorias | False | True | ["settings_view", "lookups_view"] | Required active; no admin/Team bypass | ConfigurationPolicy (Category) | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_priorities_manage | Gerenciar prioridades | False | True | ["settings_view", "lookups_view"] | Required active; no admin/Team bypass | ConfigurationPolicy (Priority) | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_statuses_manage | Gerenciar status | False | True | ["settings_view", "lookups_view"] | Required active; no admin/Team bypass | ConfigurationPolicy (TicketStatus) | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_services_manage | Gerenciar servicos | False | True | ["settings_view", "lookups_view"] | Required active; no admin/Team bypass | ServicePolicy#create? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_lifecycle_policies_manage | Publicar politicas de ciclo | False | True | ["settings_view", "lookups_view"] | Required active; no admin/Team bypass | LifecyclePolicyPolicy#publish? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_settings_view | Visualizar configuracoes | False | True | ["module_view"] | Required active; no admin/Team bypass | ModulePolicy#settings? | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_dashboard_view | Visualizar dashboard autorizado | True | True | ["tickets_view"] | Required active; no admin/Team bypass | ModulePolicy#dashboard? + TicketPolicy::Scope | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_structure_view | Consultar estrutura da Account sem chamados | False | False | [] | N/A para administracao estrutural explicitamente delegada; obrigatorio independentemente para operar chamados | StructurePolicy + StructureContext; nao TicketPolicy | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_operator_companies_manage | Gerenciar operadoras da Account | False | False | ["structure_view"] | N/A para administracao estrutural explicitamente delegada; obrigatorio independentemente para operar chamados | StructurePolicy + StructureContext; nao TicketPolicy | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_units_manage | Gerenciar unidades da Account | False | False | ["structure_view"] | N/A para administracao estrutural explicitamente delegada; obrigatorio independentemente para operar chamados | StructurePolicy + StructureContext; nao TicketPolicy | PENDENTE DE EXECUÇÃO NATIVA |
| jrc_service_desk_unit_memberships_manage | Conceder/revogar escopo de clientes sem autoconcessao | False | False | ["structure_view"] | N/A para administracao estrutural explicitamente delegada; obrigatorio independentemente para operar chamados | StructurePolicy + StructureContext; nao TicketPolicy | PENDENTE DE EXECUÇÃO NATIVA |

A autoridade do funcionario JRC usa sessao SuperAdmin + designacao nominativa protegida, nao uma capacidade operacional. Nenhum grant real realizado.
