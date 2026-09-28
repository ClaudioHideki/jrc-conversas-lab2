# CP5 - matriz de perfis e capacidades

**CP5 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE**

PENDENTE — validação nativa em ambiente Docker/local

33 capacidades acrescentadas ao catalogo NATIVO CustomRole.permissions. Sem tabela de roles/grants do Service Desk, sem login alternativo, sem permissao em UnitMembership.

Os defaults abaixo sao explicitamente enumerados para os perfis nativos. Administrador nao e bypass: Account, flag, unidade, visibilidade do registro e regra de ciclo continuam obrigatorias. Nao ha wildcard que conceda automaticamente novas capacidades futuras. Um CustomRole substitui completamente os defaults, inclusive quando AccountUser.role e administrator. Roles antigos sem capacidade SD permanecem negados.

Prerequisitos nao sao autoatribuidos pelo editor. Resolver exige module_view, tickets_view, history_view, sla_view e resolve, alem da unidade e da regra aplicavel. Consultar alvos para selecao nos formularios exige lookups_view e, para cliente, customers_view. IDs conhecidos nao dispensam as verificacoes backend.

| Capacidade | Significado | Agente nativo | Admin nativo | Prerequisitos | Policy | Status |
|---|---|---|---|---|---|---|
| `jrc_service_desk_module_view` | Visualizar modulo | S | S | - | ModulePolicy#show? | PENDENTE |
| `jrc_service_desk_tickets_view` | Visualizar chamados | S | S | module_view | TicketPolicy#index?/show?/Scope | PENDENTE |
| `jrc_service_desk_tickets_view_all` | Visualizar todos os chamados das unidades vinculadas | N | S | tickets_view | TicketPolicy::Scope (same units only) | PENDENTE |
| `jrc_service_desk_tickets_create` | Criar chamado | S | S | tickets_view, lookups_view, customers_view | TicketPolicy#create? | PENDENTE |
| `jrc_service_desk_tickets_edit` | Editar dados do chamado | S | S | tickets_view | TicketPolicy#update? + field checks | PENDENTE |
| `jrc_service_desk_tickets_assign` | Atribuir chamado | S | S | tickets_view | TicketPolicy#assign? | PENDENTE |
| `jrc_service_desk_tickets_transfer` | Transferir na mesma unidade | S | S | tickets_view | TicketPolicy#transfer? | PENDENTE |
| `jrc_service_desk_priority_change` | Alterar prioridade | S | S | tickets_view | TicketPolicy#change_priority? + field checks | PENDENTE |
| `jrc_service_desk_work_status_change` | Alterar status de trabalho | S | S | tickets_view, history_view, sla_view | WorkStatusPolicy + published rule | PENDENTE |
| `jrc_service_desk_pause` | Pausar | S | S | tickets_view, history_view, sla_view | LifecycleActionPolicy#action? + pinned rule | PENDENTE |
| `jrc_service_desk_resume` | Retomar | S | S | tickets_view, history_view, sla_view | LifecycleActionPolicy#action? + pinned rule | PENDENTE |
| `jrc_service_desk_resolve` | Resolver | S | S | tickets_view, history_view, sla_view | LifecycleActionPolicy#action? + pinned rule | PENDENTE |
| `jrc_service_desk_close` | Encerrar | S | S | tickets_view, history_view, sla_view | LifecycleActionPolicy#action? + pinned rule | PENDENTE |
| `jrc_service_desk_cancel` | Cancelar | S | S | tickets_view, history_view, sla_view | LifecycleActionPolicy#action? + pinned rule | PENDENTE |
| `jrc_service_desk_reopen` | Reabrir | S | S | tickets_view, history_view, sla_view | LifecycleActionPolicy#action? + pinned rule | PENDENTE |
| `jrc_service_desk_notes_view` | Consultar notas internas | S | S | tickets_view | TicketNotePolicy | PENDENTE |
| `jrc_service_desk_notes_add` | Adicionar nota interna | S | S | notes_view | TicketPolicy#add_note? + TicketNotePolicy#create? | PENDENTE |
| `jrc_service_desk_history_view` | Consultar historico | S | S | tickets_view | TicketEventPolicy + LifecycleReadService | PENDENTE |
| `jrc_service_desk_conversations_view` | Consultar vinculos de conversa | S | S | tickets_view | TicketConversationPolicy + native ConversationPolicy | PENDENTE |
| `jrc_service_desk_conversations_link` | Relacionar conversa | S | S | conversations_view | TicketPolicy#link_conversation? + native ConversationPolicy | PENDENTE |
| `jrc_service_desk_sla_view` | Visualizar SLA operacional | S | S | tickets_view | SlaMilestonePolicy / LifecycleActionPolicy | PENDENTE |
| `jrc_service_desk_contract_conditions_view` | Consultar condicoes contratuais restritas | N | S | sla_view | SlaSnapshotPolicy#show?/Scope | PENDENTE |
| `jrc_service_desk_sla_snapshots_record` | Registrar snapshot de SLA | N | S | contract_conditions_view | SlaSnapshotPolicy#create? | PENDENTE |
| `jrc_service_desk_lookups_view` | Consultar seletores operacionais | S | S | module_view | LookupPolicy + resource/native policies | PENDENTE |
| `jrc_service_desk_customers_view` | Consultar contexto do cliente | S | S | tickets_view | TicketPolicy#view_customer? + native Contact/Company policies | PENDENTE |
| `jrc_service_desk_queues_manage` | Gerenciar filas | N | S | settings_view, lookups_view | ConfigurationPolicy (Queue) | PENDENTE |
| `jrc_service_desk_categories_manage` | Gerenciar categorias | N | S | settings_view, lookups_view | ConfigurationPolicy (Category) | PENDENTE |
| `jrc_service_desk_priorities_manage` | Gerenciar prioridades | N | S | settings_view, lookups_view | ConfigurationPolicy (Priority) | PENDENTE |
| `jrc_service_desk_statuses_manage` | Gerenciar status | N | S | settings_view, lookups_view | ConfigurationPolicy (TicketStatus) | PENDENTE |
| `jrc_service_desk_services_manage` | Gerenciar servicos | N | S | settings_view, lookups_view | ServicePolicy#create? | PENDENTE |
| `jrc_service_desk_lifecycle_policies_manage` | Publicar politicas de ciclo | N | S | settings_view, lookups_view | LifecyclePolicyPolicy#publish? | PENDENTE |
| `jrc_service_desk_settings_view` | Visualizar configuracoes | N | S | module_view | ModulePolicy#settings? | PENDENTE |
| `jrc_service_desk_dashboard_view` | Visualizar dashboard autorizado | S | S | tickets_view | ModulePolicy#dashboard? + TicketPolicy::Scope | PENDENTE |

## Limites e compatibilidade

- tickets_view_all amplia SOMENTE as unidades ja vinculadas. Sem essa capacidade, permanece autoria/atribuicao/equipe dentro da unidade.
- Editar dados nao concede prioridade; atribuicao nao concede transferencia; PATCH misto nao grava parcialmente.
- Historico, notas, SLA, cliente, conversas e condicoes contratuais brutas possuem gates distintos.
- Publicar politica exige lifecycle_policies_manage; nunca deriva da permissao de resolver chamados.
- Gerenciar filas/categorias/prioridades/status possui policy/capacidade, mas o CRUD completo ainda nao foi exposto. Isso continua PENDENTE.
- Relatorios completos, exportacoes, portal, automacoes, ativos, conhecimento e operacoes NICO nao recebem permissoes por analogia.

A tela nativa CustomRoles e sua disponibilidade continuam obedecendo a extensao/feature existente. Nao a habilitamos. Sem essa extensao, continuam os perfis agent/administrator nativos, sem armazenamento paralelo para granularidade individual. A flag SD desligada oculta suas novas opcoes no editor, mas NAO apaga permissoes previamente gravadas. A API nativa de roles pode configurar capacidades sem ativar o modulo: isso nao concede unidade nem acesso operacional.

IMPORTANTE: excluir um CustomRole nativo continua usando dependent:nullify e restaura o perfil nativo base dos usuarios afetados. Excluir role NAO e revogar acesso SD. Para revogacao operacional, revogar UnitMembership ou atribuir papel sem capacidades SD; desabilitar a flag bloqueia o modulo inteiro. Essa semantica global preexistente nao foi reescrita. A auditoria registra as mudancas SD e nao inventa uma unidade para a configuracao de um papel no nivel Account.

Nenhuma Account, usuario, papel ou UnitMembership foi ativado por esta entrega. Todas as linhas funcionais ainda precisam de validacao nativa.
