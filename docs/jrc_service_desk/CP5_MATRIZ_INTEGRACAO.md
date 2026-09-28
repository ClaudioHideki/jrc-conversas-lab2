# CP5 - matriz de integracao

**CP5 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE**

PENDENTE — validação nativa em ambiente Docker/local

Nenhuma cadeia funcional e OK por inspecao estatica. N/A indica item fora do escopo.

| RECURSO | FEATURE FLAG | ACCOUNT | UNIT MEMBERSHIP | PERMISSAO | POLICY | FRONTEND | API | AUDITORIA | TESTE | STATUS |
|---|---|---|---|---|---|---|---|---|---|---|
| Entrada/sidebar/deep links | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | module_view + screen | ModulePolicy + resource | Backend-confirmed entry, guard, denied page | GET ui_context | Read only | cp5Cases/cp5Views/routing + cp5_integration_spec | PENDENTE |
| Revogacao/troca de Account | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | All exact capabilities | OperationalContext | Clear on identity/flag switch; focus/visibility/60s and API denial | Every request rechecks | No fabricated action | cp5 session cases + cp5_capabilities_spec | PENDENTE |
| Listagem/detalhe/minha fila | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | tickets_view (+ view_all optional) | TicketPolicy::Scope | Real server pagination and per-record actions | GET tickets/:id | Read only | cp5_action_matrix + existing query specs | PENDENTE |
| Criar | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | tickets_create | TicketPolicy#create? | Action-specific capability + POST/PATCH -> independent GET | POST tickets | ticket_created + creation_context_recorded | cp5_command_guards + native CP4 APIs + readback cases | PENDENTE |
| Editar | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | tickets_edit | TicketPolicy#update? | Action-specific capability + POST/PATCH -> independent GET | PATCH/PUT ticket | ticket_updated | cp5_command_guards + native CP4 APIs + readback cases | PENDENTE |
| Prioridade | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | priority_change | TicketPolicy#change_priority? | Action-specific capability + POST/PATCH -> independent GET | PATCH/PUT ticket | ticket_updated with before/after | cp5_command_guards + native CP4 APIs + readback cases | PENDENTE |
| Atribuir | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | tickets_assign | TicketPolicy#assign? | Action-specific capability + POST/PATCH -> independent GET | POST assign | ticket_assigned | cp5_command_guards + native CP4 APIs + readback cases | PENDENTE |
| Transferir na mesma unidade | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | tickets_transfer | TicketPolicy#transfer? | Action-specific capability + POST/PATCH -> independent GET | POST transfer | ticket_transferred | cp5_command_guards + native CP4 APIs + readback cases | PENDENTE |
| Status trabalho | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | work_status_change | LifecycleActionPolicy#action? + pinned CP4-D01 | Options filtered by exact action; readback event/ticket/lifecycle | POST lifecycle; work_status alias also guarded | LifecycleTransition/event with actor/unit/Account/version | cp5_action_matrix/replay + prior lifecycle suites | PENDENTE |
| Pausar | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | pause | LifecycleActionPolicy#action? + pinned CP4-D01 | Options filtered by exact action; readback event/ticket/lifecycle | POST lifecycle; work_status alias also guarded | LifecycleTransition/event with actor/unit/Account/version | cp5_action_matrix/replay + prior lifecycle suites | PENDENTE |
| Retomar | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | resume | LifecycleActionPolicy#action? + pinned CP4-D01 | Options filtered by exact action; readback event/ticket/lifecycle | POST lifecycle; work_status alias also guarded | LifecycleTransition/event with actor/unit/Account/version | cp5_action_matrix/replay + prior lifecycle suites | PENDENTE |
| Resolver | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | resolve | LifecycleActionPolicy#action? + pinned CP4-D01 | Options filtered by exact action; readback event/ticket/lifecycle | POST lifecycle; work_status alias also guarded | LifecycleTransition/event with actor/unit/Account/version | cp5_action_matrix/replay + prior lifecycle suites | PENDENTE |
| Encerrar | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | close | LifecycleActionPolicy#action? + pinned CP4-D01 | Options filtered by exact action; readback event/ticket/lifecycle | POST lifecycle; work_status alias also guarded | LifecycleTransition/event with actor/unit/Account/version | cp5_action_matrix/replay + prior lifecycle suites | PENDENTE |
| Cancelar | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | cancel | LifecycleActionPolicy#action? + pinned CP4-D01 | Options filtered by exact action; readback event/ticket/lifecycle | POST lifecycle; work_status alias also guarded | LifecycleTransition/event with actor/unit/Account/version | cp5_action_matrix/replay + prior lifecycle suites | PENDENTE |
| Reabrir | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | reopen | LifecycleActionPolicy#action? + pinned CP4-D01 | Options filtered by exact action; readback event/ticket/lifecycle | POST lifecycle; work_status alias also guarded | LifecycleTransition/event with actor/unit/Account/version | cp5_action_matrix/replay + prior lifecycle suites | PENDENTE |
| Notas | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | notes_view / notes_add | TicketNotePolicy + TicketPolicy | Separate tab/add-note; GET note confirmation | GET/POST notes | note_added/native author | cp5 action matrix + previous notes/API tests | PENDENTE |
| Historico | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | history_view | TicketEventPolicy / lifecycle projection | Only server events, no fabricated text | GET events / lifecycle transition | Existing append-only domain records | cp5 action matrix + existing history tests | PENDENTE |
| SLA operacional | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | sla_view (+ history_view for lifecycle workspace) | SlaMilestonePolicy / LifecycleActionPolicy | No fictitious deadline; raw conditions separate | GET sla / lifecycle | Existing clocks/pauses/transitions | CP4 lifecycle + cp5 matrix | PENDENTE |
| Cliente nativo | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | customers_view + native Contact/Company ACL | TicketPolicy#view_customer? + native policies | Minimal Contact/Company panel | GET customer_context | Read only, no duplicate customer | cp5_integration_spec + cp5Cases/cp5Views | PENDENTE |
| Lookups nativos | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | lookups_view + customers_view for requester | LookupPolicy + native policies | Selectors bound to permitted unit | GET lookups | Read only | Existing lookup/query tests + cp5 scope cases | PENDENTE |
| Usuarios/equipes | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | assignment/transfer + target capability/unit | Native TeamPolicy + OperationalContext | Native AccountUser/User/Team; no new agents | Existing lookups/assignment | Assignment/transfer | cp5 target capability + Team-without-membership cases | PENDENTE |
| Vinculos de conversa | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | conversations_view/link + native ACL | TicketConversationPolicy + ConversationPolicy | Existing links; no copied messages | GET/POST conversations | conversation_linked redacted if native ACL denied | cp5 request specs + prior native link specs | PENDENTE |
| Abrir conversa | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | conversations_view + native ACL | Both domains reauthorized before route | GET navigation -> native inbox_conversation/display_id | GET conversations/:record_id/navigation | Read only | cp5 native route/decoder tampering cases | PENDENTE |
| Gerenciar Filas | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | queues_manage | ConfigurationPolicy | Existing read-only catalog structure | Read API only; full CRUD remains pending | No false writes | cp5 management matrix + existing catalog specs | PENDENTE |
| Gerenciar Categorias | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | categories_manage | ConfigurationPolicy | Existing read-only catalog structure | Read API only; full CRUD remains pending | No false writes | cp5 management matrix + existing catalog specs | PENDENTE |
| Gerenciar Prioridades | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | priorities_manage | ConfigurationPolicy | Existing read-only catalog structure | Read API only; full CRUD remains pending | No false writes | cp5 management matrix + existing catalog specs | PENDENTE |
| Gerenciar Status | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | statuses_manage | ConfigurationPolicy | Existing read-only catalog structure | Read API only; full CRUD remains pending | No false writes | cp5 management matrix + existing catalog specs | PENDENTE |
| Servicos | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | services_manage | ServicePolicy | Scoped service editor | service_definitions API | Existing record/scope metadata | cp5 matrix + prior service tests | PENDENTE |
| Politicas de ciclo | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | lifecycle_policies_manage | LifecyclePolicyPolicy | Scoped versioned JSON editor | lifecycle_policies API | Version/actor/unit/Account/digest/publication | cp5 matrix + prior publication/version tests | PENDENTE |
| Configuracoes | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | settings_view + management action | ModulePolicy#settings? + resource | No generic admin bypass | ui_context + resources | Per-resource | cp5 landing/screens + native policies | PENDENTE |
| Dashboard | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | dashboard_view + tickets_view/scope | ModulePolicy#dashboard? + TicketPolicy::Scope | Same real SQL counts, no local counter | GET dashboard | Read only | cp5_dashboard_scopes_spec + prior KPI fixtures | PENDENTE |
| Papeis customizados nativos | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | Native role administration; explicit SD catalog | Native CustomRoles policy + capability interpretation | Existing modal/labels; no duplicate role UI | Existing native CustomRoles API | Native audits of SD permissions + AccountUser custom_role_id | cp5_native_role_audit_spec + isolated capabilities | PENDENTE |
| Jobs/acoes automaticas | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | No new execution grant | Existing SD domain gates | No job interface | No new job/scheduler | N/A | Whole-tree comparison | N/A |
| Comunicacao/anexos/relatorios completos/governanca | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | No implicit grants | Not exposed by analogy | Unavailable/PENDENTE | No new operational API | No simulated success | Preserved pending matrix | PENDENTE |
| CP6 / Projetos | jrc_service_desk true; default false | Native authenticated Account and scoped records | Active explicit AccountUser/Unit; no admin/Team bypass | None | None | Not implemented | Not implemented | N/A | Scope comparison | N/A |

## Detalhes e limites

**Revogacao/troca de Account:** Remote revocation is not a push event. Frontend refresh interval does not enforce backend permission.

**Status trabalho:** Policy publication does not retarget pinned tickets; calendar/snapshot dependencies remain.

**Pausar:** Policy publication does not retarget pinned tickets; calendar/snapshot dependencies remain.

**Retomar:** Policy publication does not retarget pinned tickets; calendar/snapshot dependencies remain.

**Resolver:** Policy publication does not retarget pinned tickets; calendar/snapshot dependencies remain.

**Encerrar:** Policy publication does not retarget pinned tickets; calendar/snapshot dependencies remain.

**Cancelar:** Policy publication does not retarget pinned tickets; calendar/snapshot dependencies remain.

**Reabrir:** Policy publication does not retarget pinned tickets; calendar/snapshot dependencies remain.

**Historico:** Domain readonly does not protect against privileged SQL.

**Abrir conversa:** Native route still checks its own policy. Database ID and display_id are distinct.

**Gerenciar Filas:** Capability is implemented; complete CRUD is not claimed complete.

**Gerenciar Categorias:** Capability is implemented; complete CRUD is not claimed complete.

**Gerenciar Prioridades:** Capability is implemented; complete CRUD is not claimed complete.

**Gerenciar Status:** Capability is implemented; complete CRUD is not claimed complete.

**Dashboard:** Different scopes may legitimately yield different totals. Mathematics remains unchanged.

**Papeis customizados nativos:** Account-level role configuration does not grant units. Native role deletion fallback is retained.

**Jobs/acoes automaticas:** No implicit operation or feature activation.

**Comunicacao/anexos/relatorios completos/governanca:** Sending to channels, portal, exports and complementary domains remain pending.

**CP6 / Projetos:** Not started.
