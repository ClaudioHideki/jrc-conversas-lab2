## Fechamento R2 — estado corrente para revisão, sem publicação

Esta seção substitui o checkpoint provisório da R2. A R1/CP0 abaixo foi preservada integralmente e continua definindo o escopo aprovado, mas seus resultados e pendências anteriores são históricos. Conclusão do lote local não é homologação operacional nem conclusão de todos os anexos.

Repositório `ClaudioHideki/jrc-conversas-lab2`; origin exclusivo `https://github.com/ClaudioHideki/jrc-conversas-lab2.git`; branch `codex/relacionamento-servicedesk-v2-20261008`. HEAD e base continuam em `4ce8241d35ce862e9d53e9a5dce4df9a1858432c`. O ancestral `b2001cb40ebe1eb1e8f3a97e1559b901199adf71` foi preservado, incluindo os 157 arquivos e 8 migrations históricas. Nenhum arquivo versionado foi removido; nada está staged.

Estado inicial R2: 202 novos/untracked + 99 modificados = 301. Estado final acumulado: 299 novos/untracked + 105 modificados = 404, com zero removidos/staged. Em relação ao snapshot inicial, 117 caminhos passaram a participar do diff (incluem 6 arquivos existentes antes limpos), 153 caminhos anteriores mudaram e 14 specs untracked foram renomeados; esses renomes não representam 14 exclusões do Git. A auditoria externa está em `C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-auditoria-20261008/`.

A última alteração executável afetou somente três specs: corrigiu fixtures de revogação/inbox e o helper SQL com RETURNING duplicado. Todos os demais 396 hashes do selo anterior ficaram idênticos. O novo selo final contém 399 arquivos executáveis/testes/configs; o snapshot de teste tem 404/404 hashes iguais aos do checkout. Após esse ponto, apenas estes cinco documentos são atualizados.

STATUS_R2_A_QUALIDADE=CONCLUIDO_COM_IMPEDIMENTO_EXPLICITO_E_WARNINGS_DOCUMENTADOS
STATUS_R2_B_SERVICE_DESK=VALIDADO_LOCALMENTE_NO_LOTE_R2
STATUS_R2_C_FLOWS=VALIDADO_LOCALMENTE_NO_LOTE_R2
STATUS_DESTA_RODADA=ENTREGA_PARCIAL_VALIDADA_COM_RESSALVAS
STATUS_DO_ESCOPO_TOTAL=PARCIAL_COM_PENDENCIAS_CLASSIFICADAS
VALIDACAO_DO_ESTADO_FINAL=EXECUTADA_COM_SETE_FALHAS_HISTORICAS_E_UM_IMPEDIMENTO_DE_LINT
PRONTO_PARA_REVISAO_DE_COMMIT=NAO
COMMIT_EXECUTED=NAO
PUSH_EXECUTED=NAO
IMAGE_PUBLISHED=NAO
DEPLOY_EXECUTED=NAO
MIGRATIONS_EXECUTED_ON_SERVER=NAO
ATIVACAO_EM_CLIENTES_REAIS=NAO
REAL_MESSAGES_SENT=NAO
COMPOSE_CHANGED=NAO
RUNTIME_REBUILT=NAO

Não há autorização de commit, push, imagem, deploy, backfill ou ativação. O impedimento de lint é deliberadamente visível, não suprimido. Nenhuma aprovação integral decorre dos testes abaixo.

### Resultado do lote R2, requisito por requisito

| Requisito | Resultado local | Evidência/limite |
|---|---|---|
| A: ocorrências Ruby novas e origem das antigas | 372 ocorrências: 371 históricas provadas e 1 impedimento novo; 0 origens sem prova | 218 métricas com owner AST exato e medida individual não maior que a base; 152 tokens recalculados; 1 expressão AST. Sem disables, exclusões ou limites ampliados. |
| A: warnings JS | 0 erros novos; 179 warnings novos documentados por arquivo/regra | 118 conflitos Vue/Prettier (o experimento geraria 191 erros), 31 traduções com catálogo/binding explícito e 30 símbolos de pontuação. Sem alegar ESLint limpo. |
| A: migrations congeladas | Revisão humana autorizada; 4 das 6 alteradas para qualidade, 2 hashes iguais; schema das 6 equivalente | DDL real em clone novo local. Históricas intactas. Migration 160000 aditiva separada. |
| B: INTERNAL/TECHNICAL_TEAM/CUSTOMER/PUBLIC_WITHOUT_NOTIFICATION | 4 audiências reais, default interno, autorização backend atual e publicação silenciosa sem exigir canal | 4 × UI → POST 201 → GET persistido/timeline; sem stub da API. O estado queued não equivale a envio. |
| B: preview/aprovação | Texto literal, arquivos, audiência, recipient, Account, Unit, ticket revision, grants, policy e TTL de 5 min vinculados | A edição invalida a aprovação; assinatura adulterada retorna 409; stale/foreign/revoked são rejeitados. Receipts somente após releitura real. |
| B: políticas/eventos | 13 event_types nativos, políticas versionadas/configuráveis, snapshot mínimo e intenção após commit | customer_interaction, ticket_created, ticket_assigned, status_changed, waiting_customer, approval_requested, approval_decided, resolved, closed, reopened, task_created, task_updated, task_completed. Tarefa somente quando pública. A pesquisa usa o motor compartilhado. |
| B: entregas/reenvio | DTO com actor/recipient/channel/template/provider, horários e estado; nova tentativa manual auditada preserva a original | unknown não é reenviado cegamente; a conciliação exige Message/digest reais. O job reautoriza. Estado monotônico e idempotência em SQL. Provider real não homologado. |
| B: cabeçalho/SLA/timeline | Header persistente com dados/SLA reais; SQL UNION keyset nas fontes nativas | Notes/Events/Tasks/Approvals/Message/Call/Deliveries, source ACL e scanner antes de conteúdo/export/anexo. Nenhuma cópia paralela de conversa. |
| B: preservação/negativos | HMAC, Contact merge, OFF e legado preservados; source grant revogado redige o payload | Browser local com as 4 audiências + teste de adulteração (tamper) e requests atuais; portal/scanner externo e telefonia não homologados. |
| C: managed-only e ator atual | Guard específico do managed_run; legado independente | Account/Unit/customer/originalActor/pilot/phase/approval/TTL/version/digest/payload/scope/quota/kill revalidados em cada retomada/efeito, sem admin fallback. |
| C: delay/input/timer | Mesmo Runner e journal nativos, com continuação durável | input copia o texto para a variável explicitamente aprovada; não infere keyword/voz/OTP. A retomada concorrente é atômica. |
| C: efeitos | Somente note/message autorizáveis; policy/effects OFF por padrão | Message nativo + claim durável + receipt verificado. unknown exige conciliação; cancelamento/replay/revocation/current state exercitados. Outros nós continuam bloqueados com reason preciso. |
| C: concorrência | 19/19 casos PG reais aprovados no estado final, incluindo 5 Flow | A primeira execução sob gates paralelos teve 1 SQL timeout de espera em Account; a repetição 5/5 e o final isolado 19/19 passaram. Não foi provada causalidade de carga, nem alterado timeout/assertion. |

### Pendências do escopo total — continuam obrigatórias

| Classe | Requisitos aprovados / trabalho restante |
|---|---|
| IMPLEMENTACAO_LOCAL_PENDENTE | CS10/CS16: pesquisas de voz interativa e QR. CS01/CS12: denominadores completos/BI. SD P0-04: terceiro relógio de atendimento e OLA thresholds/escalonamento. Menus 04/09: campos/catalog ACL por contrato/tipo/serviço e defaults. Menu 07: approvals por Team/role/escalation/waiting. Menus 08/11/12/13: Problems/Changes/Assets/páginas planejadas/analytics. Overrides de notification por tipo/serviço/contact prefs/task channels. Pipeline task completed → próxima/status/approval e UI supervision integral. P0-11/12: portal SLA/outgoing/KB pré-abertura/survey/busca/acesso/retenção/expiry. R13: origem genérica verificável de ticket_updated. K1: prova de confirmação do cliente + autonomia/intervenção. Diário: adapters locais email/WhatsApp e recipient verificado. |
| IMPLEMENTACAO_LOCAL_PENDENTE | CS11 guards: remote_flow_simulator_and_relationship_guard_unavailable; workflow_relationship_continuation_guard_required; native_manual_trigger_required; native_message_keyword_input_required; native_dispatch_business_hours_guard_required; native_relationship_delivery_guard_required para media/webhook/nico; native_relationship_action_grants_required para contact/labels/status/assign/create_lead/move_deal/activity. São lacunas locais, não “API externa” genérica. |
| TESTE_LOCAL_PENDENTE | CS08: renovação macro E2E renewal → CRM → pedido/aditivo/contrato → retorno/carteira. Cadeias humanas/efeitos de todas as 16 regras R01–R16 e fases/grupos NICO. E2E comercial integral/portal e clientes Broker/Runtime. Carga/latência da admissão Flow por Account para explicar o timeout inicial observado: os retestes aprovados não provam a causa. Os 1282 exemplos únicos locais não provam esses macrofluxos. Testes cobertos nesta rodada não são reclassificados como pendentes. |
| DEPENDENCIA_EXTERNA | Grupos NICO A1–A4/B1–B2/C1 e CS07/18: contratos/API/credenciais Billing/PABX/OTP/Reporter/URA/reuniões/gravação. Depois do contrato, ainda há adapter local a construir e homologação distinta. Não existem endpoints/admin/recipient inventados. |
| DECISAO_DE_NEGOCIO | C01: SLA 70/90/100 vs NICO 80. C02: R07–R09, horas/dias úteis ou corridos (168 h úteis ≠ 7 dias). C03: janela R03, fonte omissa/5 ocorrências/60 dias unconfirmed. C04: população/NPS <= 6 vs CSAT/CES/meta 20%; pilots/Units/actors/roles/consent/calendar/canais/templates/limits/TTL/kill e strict/handoff approvals. Defaults permanecem OFF. |
| HOMOLOGACAO_OPERACIONAL | SMTP/Meta/WhatsApp/Broker/telefone/gravação/portal/scanner/calendários reais, receipts reais e E2E funcional/comercial autorizado. Nenhum envio real nem homologação de provider IA/Runtime live nesta rodada. |

As 18 áreas CS, 52 linhas SD e 13 menus, 12 P0, 11 grupos NICO/fases, 16 regras, 7 KPIs e Diário continuam integralmente no histórico aprovado abaixo e no inventário externo `r2-total-scope-consolidated.md`. Nada foi cancelado ou considerado concluído apenas pela presença de menu/arquivo. Lacuna de adapter local, contrato externo, decisão de negócio e homologação são estados distintos.

### Lista exata final de arquivos (inclui untracked)

| Git | Delta R2 | Arquivo |
|---|---|---|
| A/untracked | R1 preservado | `app/controllers/api/v1/accounts/jrc_nico/helpdesk_controller.rb` |
| A/untracked | alterado R2 | `app/controllers/api/v1/accounts/jrc_service_desk/cockpit_controller.rb` |
| A/untracked | entra no diff R2 | `app/controllers/api/v1/accounts/jrc_service_desk/communication_controller.rb` |
| A/untracked | R1 preservado | `app/controllers/api/v1/accounts/jrc_service_desk/knowledge_controller.rb` |
| A/untracked | alterado R2 | `app/controllers/api/v1/accounts/relationship/handoffs_controller.rb` |
| A/untracked | alterado R2 | `app/controllers/api/v1/accounts/relationship/survey_administration_controller.rb` |
| A/untracked | alterado R2 | `app/controllers/api/v1/widget/service_desk_controller.rb` |
| A/untracked | R1 preservado | `app/javascript/dashboard/api/jrcNicoHelpdesk.js` |
| A/untracked | alterado R2 | `app/javascript/dashboard/api/serviceDeskCockpit.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/api/serviceDeskOperationsV2.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/i18n/locale/en/jrcNicoHelpdesk.json` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/crm/views/leads/spec/LeadsIndex.spec.js` |
| A/untracked | alterado R2 | `app/javascript/dashboard/routes/dashboard/jrcNico/HelpdeskPage.vue` |
| A/untracked | alterado R2 | `app/javascript/dashboard/routes/dashboard/jrcNico/HelpdeskPolicyForm.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcNico/helpdesk.spec.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/jrcNico/helpdeskLabels.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcNico/routes.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/HandoffPanel.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/ManualAttendancePanel.vue` |
| A/untracked | alterado R2 | `app/javascript/dashboard/routes/dashboard/jrcRelationship/PlaybookDesignPreview.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/PlaybookExecutionPanel.vue` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/jrcRelationship/PlaybookFlowPolicyForm.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyAdministrationPanel.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyReportFilters.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyReportSummary.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyResponseBox.vue` |
| A/untracked | alterado R2 | `app/javascript/dashboard/routes/dashboard/jrcRelationship/nativeCompletions.spec.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/nativeLineage.spec.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/jrcRelationship/playbookFlowLabels.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/jrcRelationship/playbookFlowPolicy.spec.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/sharedSurveys.spec.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/CatalogueAnswers.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/ClaimNext.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/InteractionComposer.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/MembershipAvailability.vue` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/NotificationControls.vue` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/NotificationPolicyEditor.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/SupervisorPanel.vue` |
| A/untracked | alterado R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketHeader.vue` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketTimeline.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/spec/ClaimNext.spec.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/spec/ConfigurationV2Fields.spec.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/spec/InteractionComposer.spec.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/composables/useInteractionComposer.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/composables/usePublicationConfirmation.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/composables/useTicketTimeline.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/catalogueFields.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/cockpitContract.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/communicationContract.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/communicationLabels.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/cockpitContract.spec.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/communicationContract.spec.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/v2Configuration.spec.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/v2Projection.spec.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/v2Configuration.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/v2Labels.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/v2Projection.js` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/KnowledgeView.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/OperationsBoardView.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/ReportsView.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/ServiceCatalogView.vue` |
| A/untracked | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/spec/KnowledgeView.spec.js` |
| A/untracked | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/spec/TicketDetailPublication.spec.js` |
| A/untracked | R1 preservado | `app/javascript/widget/api/serviceDesk.js` |
| A/untracked | R1 preservado | `app/javascript/widget/api/specs/serviceDeskIdentity.spec.js` |
| A/untracked | R1 preservado | `app/javascript/widget/components/ServiceDeskPortal.vue` |
| A/untracked | R1 preservado | `app/javascript/widget/components/spec/ServiceDeskPortal.spec.js` |
| A/untracked | R1 preservado | `app/javascript/widget/helpers/serviceDeskIdentityProof.js` |
| A/untracked | R1 preservado | `app/javascript/widget/helpers/serviceDeskPortal.js` |
| A/untracked | R1 preservado | `app/jobs/jrc_nico/helpdesk/event_job.rb` |
| A/untracked | R1 preservado | `app/jobs/jrc_nico/helpdesk/monitor_job.rb` |
| A/untracked | R1 preservado | `app/jobs/jrc_relationship/native_csat_response_job.rb` |
| A/untracked | entra no diff R2 | `app/jobs/jrc_relationship/playbook_flow_resume_job.rb` |
| A/untracked | R1 preservado | `app/jobs/jrc_relationship/survey_closure_job.rb` |
| A/untracked | alterado R2 | `app/jobs/jrc_relationship/survey_dispatch_job.rb` |
| A/untracked | R1 preservado | `app/jobs/jrc_relationship/survey_receipt_job.rb` |
| A/untracked | R1 preservado | `app/jobs/jrc_service_desk/first_response_job.rb` |
| A/untracked | alterado R2 | `app/jobs/jrc_service_desk/notification_delivery_job.rb` |
| A/untracked | entra no diff R2 | `app/jobs/jrc_service_desk/notification_event_job.rb` |
| A/untracked | alterado R2 | `app/jobs/jrc_service_desk/notification_reconciliation_job.rb` |
| A/untracked | entra no diff R2 | `app/models/concerns/jrc_relationship/playbook_flow_scheduling.rb` |
| A/untracked | R1 preservado | `app/models/concerns/jrc_relationship/survey_message_receipts.rb` |
| A/untracked | alterado R2 | `app/models/concerns/jrc_service_desk/notification_receipts.rb` |
| A/untracked | alterado R2 | `app/models/jrc_nico/helpdesk/approval.rb` |
| A/untracked | alterado R2 | `app/models/jrc_nico/helpdesk/control_event.rb` |
| A/untracked | alterado R2 | `app/models/jrc_nico/helpdesk/daily_report.rb` |
| A/untracked | R1 preservado | `app/models/jrc_nico/helpdesk/delivery_receipt.rb` |
| A/untracked | alterado R2 | `app/models/jrc_nico/helpdesk/event.rb` |
| A/untracked | alterado R2 | `app/models/jrc_nico/helpdesk/policy_control.rb` |
| A/untracked | R1 preservado | `app/models/jrc_nico/helpdesk/policy_version.rb` |
| A/untracked | R1 preservado | `app/models/jrc_nico/helpdesk/ticket_profile.rb` |
| A/untracked | R1 preservado | `app/models/jrc_relationship/handoff_case.rb` |
| A/untracked | R1 preservado | `app/models/jrc_relationship/playbook_execution.rb` |
| A/untracked | R1 preservado | `app/models/jrc_relationship/playbook_version.rb` |
| A/untracked | alterado R2 | `app/models/jrc_relationship/survey_definition.rb` |
| A/untracked | R1 preservado | `app/models/jrc_relationship/survey_dispatch_decision.rb` |
| A/untracked | alterado R2 | `app/models/jrc_relationship/survey_rule.rb` |
| A/untracked | R1 preservado | `app/models/jrc_relationship/survey_version.rb` |
| A/untracked | R1 preservado | `app/models/jrc_service_desk/incident.rb` |
| A/untracked | alterado R2 | `app/models/jrc_service_desk/notification_delivery.rb` |
| A/untracked | alterado R2 | `app/models/jrc_service_desk/notification_policy_version.rb` |
| A/untracked | R1 preservado | `app/models/jrc_service_desk/ola_clock.rb` |
| A/untracked | alterado R2 | `app/models/jrc_service_desk/portal_request.rb` |
| A/untracked | R1 preservado | `app/models/jrc_service_desk/ticket_approval.rb` |
| A/untracked | alterado R2 | `app/models/jrc_service_desk/ticket_task.rb` |
| A/untracked | R1 preservado | `app/policies/jrc_service_desk/incident_policy.rb` |
| A/untracked | R1 preservado | `app/policies/jrc_service_desk/ticket_approval_policy.rb` |
| A/untracked | R1 preservado | `app/policies/jrc_service_desk/ticket_task_policy.rb` |
| A/untracked | entra no diff R2 | `app/serializers/jrc_service_desk/delivery_presenter.rb` |
| A/untracked | entra no diff R2 | `app/serializers/jrc_service_desk/event_data_projection.rb` |
| A/untracked | entra no diff R2 | `app/serializers/jrc_service_desk/operations_presenter.rb` |
| A/untracked | entra no diff R2 | `app/serializers/jrc_service_desk/portal_presenter.rb` |
| A/untracked | entra no diff R2 | `app/serializers/jrc_service_desk/sla_milestone_projection.rb` |
| A/untracked | entra no diff R2 | `app/serializers/jrc_service_desk/ticket_permissions.rb` |
| A/untracked | entra no diff R2 | `app/serializers/jrc_service_desk/timeline_presenter.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/action_preview.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/approvals.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/broker_health.rb` |
| A/untracked | alterado R2 | `app/services/jrc_nico/helpdesk/capture.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/catalog.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/context.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/controls.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/cycle_evidence.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/daily_reporter.rb` |
| A/untracked | alterado R2 | `app/services/jrc_nico/helpdesk/definition.rb` |
| A/untracked | alterado R2 | `app/services/jrc_nico/helpdesk/delivery.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/event_processor.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/execution_guard.rb` |
| A/untracked | alterado R2 | `app/services/jrc_nico/helpdesk/facts.rb` |
| A/untracked | alterado R2 | `app/services/jrc_nico/helpdesk/kpis.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/policies.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk/profile_writer.rb` |
| A/untracked | alterado R2 | `app/services/jrc_nico/helpdesk/rule_detector.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk_tool_actions.rb` |
| A/untracked | R1 preservado | `app/services/jrc_nico/helpdesk_tool_catalog.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_nico/operator_context.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_nico/protected_resource_reader.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_nico/tool_result_projection.rb` |
| A/untracked | R1 preservado | `app/services/jrc_relationship/commercial_eligibility.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/commercial_return.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/customer_timeline.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/expansion_attributes.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/manual_attendance.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/playbook_flow.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_admission.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_approval.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_capabilities.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_continuation.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_decision.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_journal.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_locks.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_origin.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_policy.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/playbook_flow_reference.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_result.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_run_context.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_source_denied.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_flow_visibility.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/playbook_native_result.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/playbook_preview.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/portfolio_batch.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/record_filters.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/record_presentation.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/record_visibility.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/renewal_reconciliation.rb` |
| A/untracked | R1 preservado | `app/services/jrc_relationship/risk_financial_snapshot.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/satisfaction_signals.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_administration.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_engine.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_execution_context.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_links.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_message_execution.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_metrics.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_question_schema.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_report.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_response.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_source.rb` |
| A/untracked | alterado R2 | `app/services/jrc_relationship/survey_summary.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_relationship/workflow_references.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/attachment_scan_error.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/automatic_routing_service.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/catalogue_answers.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/catalogue_fields.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/claim_next_service.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/cockpit_projection.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/composer_projection.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/create_approval_service.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/create_incident_service.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/create_task_service.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/decide_approval_service.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/delivery_access.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/dispatch_order.rb` |
| A/untracked | R1 preservado | `app/services/jrc_service_desk/interaction_attachments.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/interaction_draft.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/interaction_preview.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/interaction_publication.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/interaction_visibility.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/knowledge_query.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/native_execution_context.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/native_response_recorder.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/notification_eligibility.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/notification_engine.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/notification_event.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/notification_execution.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/notification_payload.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/notification_receipt.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/notification_resend_preview.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/notification_source.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/ola_tracker.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/operations_board_query.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/portal_configuration_options.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/portal_creation_service.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/portal_customer_message.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/portal_identity_proof.rb` |
| A/untracked | R1 preservado | `app/services/jrc_service_desk/portal_identity_required.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/portal_scope.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/publication_plan.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/publication_preview_error.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/publish_notification_policy_service.rb` |
| A/untracked | R1 preservado | `app/services/jrc_service_desk/recorded_changes.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/resend_notification_service.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/service_portal_configuration.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/skill_codes.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/supervision_projection.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/ticket_timeline.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/timeline_attachment.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/timeline_sources.rb` |
| A/untracked | entra no diff R2 | `app/services/jrc_service_desk/ui_capability_projection.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/update_incident_service.rb` |
| A/untracked | alterado R2 | `app/services/jrc_service_desk/update_task_service.rb` |
| A/untracked | R1 preservado | `app/views/relationship_surveys/show.html.erb` |
| A/untracked | alterado R2 | `db/migrate/20261008110000_complete_relationship_shared_surveys.rb` |
| A/untracked | alterado R2 | `db/migrate/20261008120000_add_jrc_service_desk_visibility_and_operations.rb` |
| A/untracked | alterado R2 | `db/migrate/20261008130000_create_jrc_nico_helpdesk.rb` |
| A/untracked | R1 preservado | `db/migrate/20261008135000_allow_revocation_of_shared_survey_executor.rb` |
| A/untracked | alterado R2 | `db/migrate/20261008140000_configure_service_desk_portal_creation.rb` |
| A/untracked | R1 preservado | `db/migrate/20261008150000_complete_relationship_native_lineage.rb` |
| A/untracked | entra no diff R2 | `db/migrate/20261008160000_extend_service_desk_event_delivery.rb` |
| A/untracked | entra no diff R2 | `db/migrate/support/jrc_service_desk_v2_catalog_schema.rb` |
| A/untracked | entra no diff R2 | `db/migrate/support/jrc_service_desk_v2_delivery_schema.rb` |
| A/untracked | entra no diff R2 | `db/migrate/support/jrc_service_desk_v2_incident_schema.rb` |
| A/untracked | entra no diff R2 | `db/migrate/support/jrc_service_desk_v2_visibility_schema.rb` |
| A/untracked | entra no diff R2 | `db/migrate/support/jrc_service_desk_v2_work_schema.rb` |
| A/untracked | alterado R2 | `docs/relacionamento-servicedesk-v2-20261008/CHECKPOINTS_E_CONTINUIDADE.md` |
| A/untracked | alterado R2 | `docs/relacionamento-servicedesk-v2-20261008/CONFLITOS_E_DECISOES.md` |
| A/untracked | alterado R2 | `docs/relacionamento-servicedesk-v2-20261008/DEPENDENCIAS_E_ATIVACAO.md` |
| A/untracked | alterado R2 | `docs/relacionamento-servicedesk-v2-20261008/INVENTARIO_E_COBERTURA.md` |
| A/untracked | alterado R2 | `docs/relacionamento-servicedesk-v2-20261008/TESTES_E_EVIDENCIAS.md` |
| A/untracked | R1 preservado | `spec/enterprise/models/call_shared_survey_spec.rb` |
| A/untracked | entra no diff R2 | `spec/listeners/csat_survey_listener_shared_survey_spec.rb` |
| A/untracked | entra no diff R2 | `spec/migrations/jrc_service_desk_r2_delivery_spec.rb` |
| A/untracked | entra no diff R2 | `spec/requests/api/v1/accounts/jrc_service_desk/r2_communication_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/jrc_service_desk/v2_claim_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/jrc_service_desk/v2_cockpit_spec.rb` |
| A/untracked | R1 preservado | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_configuration_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_creation_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_identity_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/relationship/native_completions_spec.rb` |
| A/untracked | entra no diff R2 | `spec/requests/api/v1/accounts/relationship/portfolio_controller_flow_approvals_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/relationship/shared_surveys_spec.rb` |
| A/untracked | alterado R2 | `spec/requests/api/v1/accounts/relationship/survey_reports_spec.rb` |
| A/untracked | entra no diff R2 | `spec/requests/api/v1/widget/service_desk_controller_quality_spec.rb` |
| A/untracked | R1 preservado | `spec/requests/jrc_nico_helpdesk_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_nico/helpdesk/approvals_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_nico/helpdesk/capture_boundaries_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_nico/helpdesk/capture_concurrency_spec.rb` |
| A/untracked | R1 preservado | `spec/services/jrc_nico/helpdesk/controls_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_nico/helpdesk/cycle_evidence_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_nico/helpdesk/delivery_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_nico/helpdesk/kpis_spec.rb` |
| A/untracked | R1 preservado | `spec/services/jrc_nico/helpdesk/policies_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_nico/helpdesk/rule_detector_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_nico/helpdesk_tool_actions_native_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_relationship/configuration_guards_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/customer_timeline_navigation_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/manual_attendance_native_completions_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/playbook_flow_concurrency_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/playbook_flow_continuation_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/playbook_flow_delivery_spec.rb` |
| A/untracked | alterado R2 | `spec/services/jrc_relationship/playbook_flow_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/playbook_native_result_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/playbooks_integration_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/survey_engine_concurrency_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/survey_engine_shared_surveys_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/survey_message_execution_provider_boundary_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_relationship/workflow_native_lineage_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_service_desk/jrc_service_desk_r2_communication_concurrency_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_service_desk/jrc_service_desk_v2_concurrency_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_service_desk/jrc_service_desk_v2_notifications_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_service_desk/jrc_service_desk_v2_operations_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_service_desk/jrc_service_desk_v2_supervision_spec.rb` |
| A/untracked | R1 preservado | `spec/services/jrc_service_desk/knowledge_query_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_service_desk/notification_engine_r2_communication_spec.rb` |
| A/untracked | entra no diff R2 | `spec/services/jrc_service_desk/portal_customer_message_spec.rb` |
| A/untracked | entra no diff R2 | `spec/support/jrc_service_desk_concurrency.rb` |
| A/untracked | entra no diff R2 | `spec/support/playbook_flow_context.rb` |
| M | R1 preservado | `app/controllers/api/v1/accounts/jrc_service_desk/configuration_controller.rb` |
| M | R1 preservado | `app/controllers/api/v1/accounts/jrc_service_desk/dashboard_controller.rb` |
| M | alterado R2 | `app/controllers/api/v1/accounts/jrc_service_desk/service_definitions_controller.rb` |
| M | alterado R2 | `app/controllers/api/v1/accounts/relationship/configuration_controller.rb` |
| M | alterado R2 | `app/controllers/api/v1/accounts/relationship/dashboard_controller.rb` |
| M | alterado R2 | `app/controllers/api/v1/accounts/relationship/portfolio_controller.rb` |
| M | alterado R2 | `app/controllers/api/v1/accounts/relationship/records_controller.rb` |
| M | alterado R2 | `app/controllers/relationship_surveys_controller.rb` |
| M | R1 preservado | `app/javascript/dashboard/api/jrcRelationship.js` |
| M | R1 preservado | `app/javascript/dashboard/api/serviceDeskConfigurationClient.js` |
| M | alterado R2 | `app/javascript/dashboard/api/serviceDeskOperationsClient.js` |
| M | R1 preservado | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` |
| M | R1 preservado | `app/javascript/dashboard/constants/serviceDeskPermissions.js` |
| M | R1 preservado | `app/javascript/dashboard/i18n/locale/en/customRole.json` |
| M | R1 preservado | `app/javascript/dashboard/i18n/locale/en/index.js` |
| M | alterado R2 | `app/javascript/dashboard/i18n/locale/en/jrcServiceDesk.json` |
| M | alterado R2 | `app/javascript/dashboard/i18n/locale/en/relationship.json` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/crm/views/leads/LeadsIndex.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` |
| M | alterado R2 | `app/javascript/dashboard/routes/dashboard/jrcRelationship/ConfigurationPanel.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/CustomerPanel.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/ModulePage.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/RecordEditor.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/RenewalPipeline.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/jrcRelationship/definitions.js` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/unitAccess.spec.js` |
| M | alterado R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationManager.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/configuration.js` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/drafts.js` |
| M | alterado R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/lifecycle.js` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/operationalContracts.js` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/structure.js` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/routeDefinitions.js` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/routes.js` |
| M | entra no diff R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/SettingsView.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/StructureView.vue` |
| M | alterado R2 | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketDetailView.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketFormView.vue` |
| M | R1 preservado | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketListView.vue` |
| M | R1 preservado | `app/javascript/widget/api/contacts.js` |
| M | R1 preservado | `app/javascript/widget/i18n/locale/en.json` |
| M | R1 preservado | `app/javascript/widget/views/Home.vue` |
| M | alterado R2 | `app/jobs/jrc_relationship/signal_job.rb` |
| M | R1 preservado | `app/jobs/send_reply_job.rb` |
| M | R1 preservado | `app/listeners/csat_survey_listener.rb` |
| M | R1 preservado | `app/models/csat_survey_response.rb` |
| M | entra no diff R2 | `app/models/jrc_flow_run.rb` |
| M | alterado R2 | `app/models/jrc_relationship/configuration.rb` |
| M | R1 preservado | `app/models/jrc_relationship/expansion_signal.rb` |
| M | R1 preservado | `app/models/jrc_relationship/health_snapshot.rb` |
| M | alterado R2 | `app/models/jrc_relationship/playbook.rb` |
| M | alterado R2 | `app/models/jrc_relationship/qbr.rb` |
| M | alterado R2 | `app/models/jrc_relationship/record.rb` |
| M | alterado R2 | `app/models/jrc_relationship/risk_case.rb` |
| M | R1 preservado | `app/models/jrc_relationship/success_plan.rb` |
| M | alterado R2 | `app/models/jrc_relationship/survey.rb` |
| M | alterado R2 | `app/models/jrc_service_desk/queue.rb` |
| M | alterado R2 | `app/models/jrc_service_desk/service.rb` |
| M | alterado R2 | `app/models/jrc_service_desk/ticket.rb` |
| M | alterado R2 | `app/models/jrc_service_desk/ticket_event.rb` |
| M | R1 preservado | `app/models/jrc_service_desk/ticket_note.rb` |
| M | alterado R2 | `app/models/jrc_service_desk/unit_membership.rb` |
| M | R1 preservado | `app/models/message.rb` |
| M | R1 preservado | `app/policies/jrc_service_desk/ticket_event_policy.rb` |
| M | R1 preservado | `app/policies/jrc_service_desk/ticket_note_policy.rb` |
| M | alterado R2 | `app/policies/jrc_service_desk/ticket_policy.rb` |
| M | R1 preservado | `app/policies/jrc_service_desk/ticket_record_policy.rb` |
| M | alterado R2 | `app/serializers/jrc_service_desk/presenter.rb` |
| M | alterado R2 | `app/services/jrc_customers/customer360.rb` |
| M | alterado R2 | `app/services/jrc_customers/timeline.rb` |
| M | entra no diff R2 | `app/services/jrc_flows/actions.rb` |
| M | entra no diff R2 | `app/services/jrc_flows/delivery.rb` |
| M | entra no diff R2 | `app/services/jrc_flows/runner.rb` |
| M | alterado R2 | `app/services/jrc_nico/domain_access.rb` |
| M | alterado R2 | `app/services/jrc_nico/operator_session.rb` |
| M | alterado R2 | `app/services/jrc_nico/tool_catalog.rb` |
| M | alterado R2 | `app/services/jrc_nico/tool_executor.rb` |
| M | alterado R2 | `app/services/jrc_relationship/context.rb` |
| M | alterado R2 | `app/services/jrc_relationship/customer_signals.rb` |
| M | alterado R2 | `app/services/jrc_relationship/eligibility.rb` |
| M | alterado R2 | `app/services/jrc_relationship/handoff.rb` |
| M | alterado R2 | `app/services/jrc_relationship/health_score.rb` |
| M | alterado R2 | `app/services/jrc_relationship/playbook_steps.rb` |
| M | alterado R2 | `app/services/jrc_relationship/playbooks.rb` |
| M | alterado R2 | `app/services/jrc_relationship/presenter.rb` |
| M | alterado R2 | `app/services/jrc_relationship/processor.rb` |
| M | alterado R2 | `app/services/jrc_relationship/renewal_window.rb` |
| M | alterado R2 | `app/services/jrc_relationship/survey_delivery.rb` |
| M | alterado R2 | `app/services/jrc_relationship/work_context.rb` |
| M | alterado R2 | `app/services/jrc_relationship/workflow.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/add_note_service.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/assign_ticket_service.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/capabilities.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/configuration_contract.rb` |
| M | entra no diff R2 | `app/services/jrc_service_desk/create_service_definition_service.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/create_ticket_service.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/create_ticket_workflow_service.rb` |
| M | R1 preservado | `app/services/jrc_service_desk/dashboard_service.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/lifecycle_transition_service.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/structure_contract.rb` |
| M | alterado R2 | `app/services/jrc_service_desk/ui_context_service.rb` |
| M | alterado R2 | `config/initializers/filter_parameter_logging.rb` |
| M | alterado R2 | `config/routes.rb` |
| M | R1 preservado | `config/schedule.yml` |
| M | R1 preservado | `enterprise/app/models/call.rb` |

Os 14 nomes untracked renomeados (sem remoção versionada):

- `spec/listeners/jrc_shared_survey_listener_spec.rb`
- `spec/services/jrc_nico/helpdesk/concurrency_spec.rb`
- `spec/services/jrc_nico/helpdesk/native_tools_spec.rb`
- `spec/services/jrc_relationship/lineage_navigation_spec.rb`
- `spec/services/jrc_relationship/native_completions_spec.rb`
- `spec/services/jrc_relationship/native_lineage_spec.rb`
- `spec/services/jrc_relationship/playbook_integration_spec.rb`
- `spec/services/jrc_relationship/shared_surveys_spec.rb`
- `spec/services/jrc_relationship/survey_concurrency_spec.rb`
- `spec/services/jrc_relationship/survey_provider_boundary_spec.rb`
- `spec/services/jrc_service_desk/v2_concurrency_spec.rb`
- `spec/services/jrc_service_desk/v2_notifications_spec.rb`
- `spec/services/jrc_service_desk/v2_operations_spec.rb`
- `spec/services/jrc_service_desk/v2_supervision_spec.rb`


---

# Entrega local integrada — matriz final e inventário

Base, HEAD inicial e HEAD final: `4ce8241d35ce862e9d53e9a5dce4df9a1858432c`. Branch: `codex/relacionamento-servicedesk-v2-20261008`. Repositório: `ClaudioHideki/jrc-conversas-lab2`.

Os dois prompts anexados são idênticos e foram tratados como uma solicitação. Os quatro anexos foram lidos integralmente; as cinco abas, 63 fórmulas/cache e referências históricas estão registradas no CP0 abaixo. Dados pessoais, os 1.439 chamados e metas da planilha não foram importados para runtime nem para fixtures.

**Entrega parcial para revisão, sem publicação.** Esta matriz distingue comportamento nativo implementado/testado, lacuna funcional local e dependência externa. OFF é proteção operacional; não significa implementação completa. Presença de arquivos, rotas ou mocks não é homologação.

Gates finais: 833 exemplos Ruby (820 PASS, uma falha histórica comprovada, 12 concorrentes executados separadamente e aprovados); 557 testes JS PASS; build produção PASS; boot/autoload PASS; Ruby-c 214 PASS; diff-check limpo. RuboCop NÃO aprovado: 1.225 infrações, incluindo 582 em arquivos novos. ESLint tem zero erros novos, mas 547 erros históricos no escopo comparado. Detalhes/comandos em TESTES_E_EVIDENCIAS.md.

Arquivos: **202 adicionados, 99 modificados, zero removidos**. Nada staged. `git diff --stat` mostra apenas os 99 modificados porque os 202 novos permanecem untracked; a lista abaixo inclui ambos.

## Relacionamento / Customer Success — todas as 18 áreas

### Matriz de entrega do Relacionamento — 18 áreas

| Área | Estado da entrega | Arquivos e comportamento concreto | Evidência/limite preciso |
|---|---|---|---|
| CS01 Visão Geral | IMPLEMENTADO; satisfação avançada PARCIAL_LOCAL | `Presenter`, `CustomerSignals`, `SurveyMetrics`, `ReportMetrics`, `MetricsPanel`: carteira, MRR/ARR de contratos, saúde, riscos, renovação, expansão e Agenda autorizados; CSAT compartilhado/nativo com um denominador | Reconciliação existente e testes de CSAT. `SurveySummary` acrescenta métricas/tendência no escopo filtrado; ainda não há cobertura integral de eligible→sent→responded por todos os canais nos cards executivos. |
| CS02 Carteira | IMPLEMENTADO com política opt-in | `Assignment`, `AssignmentPolicy`, `Eligibility`, `CommercialEligibility`, `PortfolioController`, `ConfigurationPanel`, `PortfolioTable`: Cadastro Mestre único e contrato/produto nativos; `active_contract_product` exige contrato ativo/expiring assinado e item ativo de produto ativo; exceção exige gestor, motivo, ator/data e audit | `native_lineage_spec` prova legado/strict/produto inativo; request prova rejeição sem evidência e exceção só por gestor. `legacy_order` é o default de compatibilidade; nova regra estrita é recomendada na UI. Um responsável principal por Assignment e acesso por equipe; não foram criadas cópias de empresa CS. |
| CS03 Central de Ações | IMPLEMENTADO | `Action`, `OperationalRouting`, `Workflow#project_risk!`, `SurveyResponse`, `SurveyLinks`, `ActionSources`, `SlaSummary`: status/SLA/pausa existentes, ação e Agenda reais e efeito por resposta | shared_surveys/provider boundaries e lineage_navigation exercitam recuperação real e dedupe. Testes de regras NICO são propriedade de outra família, não atribuídos ao contador genérico de tickets CS. |
| CS04 Saúde | IMPLEMENTADO; telemetria sem fonte BLOQUEADA_DEPENDENCIA | `Configuration`, `HealthScore`, `HealthSnapshot`, `Context`, `CustomerSignals`, `HealthScorePanel`: pesos finitos não negativos somam100; renormalize/neutral/block; imputação explícita; snapshots readonly; configuração autorizada de conta/segmento/produto/empresa/unidade | configuration_guards cobre soma, políticas e escopo. Produtos observados incluem OrderItem e ContractItem autorizados. Metas evidenciadas do plano são fonte real; fatores compartilhados da empresa não são apresentados como telemetria individual de produto. |
| CS05 Riscos e Retenção | IMPLEMENTADO | `RiskFinancialSnapshot`, `RiskCase`, `Workflow`, `Processor`, `SignalJob`, `SurveyResponse`, `Presenter`: MRR/contratos/ator/data congelados na abertura, histórico imutável e redação financeira após revogação; resposta tem efeito único | native_lineage prova contrato ended alterar carteira sem alterar MRR do risco, legacy sem backfill e finance indisponível diferente de zero. lineage_navigation prova resposta imutável com recovery_status=blocked_access após revogação da origem. |
| CS06 Planos de Sucesso | IMPLEMENTADO | `SuccessPlan`, `Workflow#validate_links!`, `WorkContext`, `RecordEditor`: contrato/produto explícitos e autorizados, metas/marcos finitos, responsáveis, tarefas/Agenda/ticket/QBR/projeto nativos e evidências existentes | Suítes nativas de operações/planos preservadas. Validação usa contrato do Customer360 e produto pertencente ao contrato/pedido; não usa produto fictício. Progresso permanece pelos objetivos/marcos e recursos existentes. |
| CS07 QBR/Reuniões | IMPLEMENTADO local; APIs BLOQUEADAS_DEPENDENCIA | `Qbr`, `Workflow#sync_qbr!`, `WorkContext`, `SurveyClosureJob`, `RecordEditor`: contexto, pauta/ata/decisões→Agenda, contact/contract/product explícitos; URLs HTTPS de reunião/gravação; closure após commit | native_lineage prova QBR comercial e escolha de policy; shared_surveys prova ausência de destinatário explícito. Provisionamento/convite/gravação/sincronização externa dependem de API/credenciais não disponíveis. |
| CS08 Renovações | IMPLEMENTADO; macrofluxo completo exige aceite E2E | `RenewalWindow.ranges`, `Configuration`, `Processor`, `RecordsController`, `RenewalPipeline`: cinco limites crescentes configuráveis, buckets contíguos/exclusivos, mesmos filtros/contadores, defaults15/30/60/90/120; casos e oportunidade CRM nativos | native_lineage prova limites/defaults/histórico e JS prova rótulos/payload. Reconciliador só confirma won por contrato active/expiring assinado com source_contract_id, não por deal won sozinho. Existe fluxo CRM de pedido/aditivo/novo contrato; a cadeia completa de renovação ainda requer prova operacional de todas as etapas. |
| CS09 Expansão | IMPLEMENTADO no sinal e retorno comercial nativo | `ExpansionSignal`, `Processor#expansion!`, `Workflow#opportunity!`, `CommercialReturn`, `RecordEditor`: origem real, Deal nativo e crescimento evidenciado; alvo depende de qualificação, sem primeiro produto arbitrário. Retorno registra contract/order/deal/product IDs reais, MRR/ator/data append-only e link ao contrato | native_lineage prova uso/evidência/dedupe. native_completions cria oportunidade→pedido expansion→OrderContractService→documento assinado/contrato ativo, verifica retorno no sinal e MRR da mesma carteira uma vez; deal won/contrato draft/produto inativo não declaram retorno. Revogação de contrato filtra o sinal por SQL; histórico de retorno permanece quando contrato termina. |
| CS10 Pesquisas/Satisfação | IMPLEMENTADO no motor compartilhado; voz/QR avançados PARCIAL_LOCAL | `Survey`, Definition/Rule/Version/Decision, `SurveyEngine`, `SurveySource`, `SurveyQuestionSchema`, `SurveyExecutionContext` e jobs: NPS/CSAT/CES/custom, versões/snapshot, uma fonte+ciclo+regra-versão, consent/frequência/atraso/expiração/tentativas, nativeCSAT, queued/dispatching/sent/delivered/failed/unknown. Activity presencial é uma origem real com contato/negócio explícitos e ciclo único por attendance | shared_surveys/provider/admin/root hooks/concorrência e native_completions. ManualAttendance usa Activity CRM real, versão/contato comercial validado e não reaproveita QBR/Call/Conversation como novo atendimento. Pesquisa interativa dentro de fluxo de voz e QR dedicado não estão completos; são lacunas locais, não APIs externas. |
| CS11 Playbooks | IMPLEMENTADO na prévia e integração limitada; continuations/efeitos avançados PARCIAL_LOCAL | `PlaybookVersion/Execution`, `PlaybookPreview`, `PlaybookFlow/Reference`, `Playbooks`, ConfigurationController e PlaybookDesignPreview: prévia integral sem escrita, definição/version/digest e IDs explícitos; JrcFlows::Simulator/Runner nativos; effects OFF; execução real só start/variable/condition/switch/note/end síncronos internos. Snapshot distingue blocked/planned de FlowRun real | playbook_flow18 + playbook_integration2 e JS3: pin/tamper/revogação/unit/grants/OFF/uma execução/replay/histórico. Bloqueado não ativa retroativamente após flagON. Configuração cria/atualiza scopes sob Account FOR UPDATE, coordenado com FOR SHARE da execução. Editor de grafo continua nativo em JrcFlows; delays/input/pesquisa/mensagens/transferência/ações externas exigem wrappers de revalidação próprios ainda ausentes. Estas continuations e guardas são lacunas locais. |
| CS12 Relatórios | IMPLEMENTADO nos relatórios nativos e respostas; BI integral PARCIAL_LOCAL | `SurveyReport`, `SurveySummary`, `RecordsController`, `SurveyReportFilters/Summary`: filtros por fonte/versão/modelo/regra/contrato/produto/carteira/agente/equipe/nota/classificação/tratamento/período/canal/unidade; lista=CSV autorizado, fórmula escapada, <=10000, tendência diária e NPS/CSAT/CES no mesmo scope | survey_reports inclui grant/account/inbox/unit, privado/formula e modelo+carteira+summary. Export/histórico de carteira e métricas nativas existentes preservados. Denominadores completos de entrega e BI de todas as etapas/canais/playbooks não foram implementados integralmente. |
| CS13 Configurações | IMPLEMENTADO | `Configuration`, `ConfigurationVersion`, `Context#authorize_configuration_scope!`, SurveyAdministration/Controller/UI: escopos/grants/versões/history/duplicate draft/simulation sem write; novas regras/playbooks OFF e modelos draft; engine e Flow effects OFF; janelas/strict/gate explícitos. Configuração revalida ator/scope dentro do lock de conta incluindo novo scope | config_guards e requests native_completions comprovam criação/history1–2 e revogação403 sem alteração. Activation não ocorreu. Políticas default preservam legado; strict e aceite podem ser ligados posteriormente por decisão auditada. APIs de reunião continuam ausentes. |
| CS14 Handoff | IMPLEMENTADO com gate opt-in | `Handoff`, `HandoffCase`, `HandoffsController`, `HandoffPanel`: caso canônico por SalesOrder; quando gateON, carteira onboarding sem ação/playbook; aceite revalida fonte/elegibilidade, checklist/motivo/ator/data imutáveis; início idempotente após accepted | native_lineage prova pendência/replay e bloqueio de playbook manual; request prova aceite→uma ação de boas-vindas. Legado continua quando gateOFF. Promessas/anexos são consultados nas fontes nativas existentes; não há cópia paralela de pacote comercial. |
| CS15 Cliente360 | IMPLEMENTADO para as novas entidades | `CustomerTimeline`, integração root em `Customer360`/`Timeline`, `WorkContext`, CustomerPanel: publicação/resposta/tratamento/decisão de pesquisa, handoff e execução de playbook com grants atuais; paginação SQL sem materializar todas execuções | lineage_navigation6 testa eventos reais/títulos sem respostas/privado, outro cliente, inbox revogado, CSrevogado sem quebrar core360 e resultado de playbook revogado. Audits reautorizam novas origens. |
| CS16 Pós-Atendimento | IMPLEMENTADO nas origens normalizadas; voz interativa PARCIAL_LOCAL | SurveyAdministration reúne source/channel/inbox/team/contract/product/company/unit/account; executor explícito, delay/frequency/expiry/maxattempts/resend/consent; regra mais específica inclusive override OFF; versions e preview; fronteira compartilhada. ManualAttendancePanel usa Contact/Deal/Contract/Product explícitos no cliente existente | Testes de OFF/actor/consent/frequency/version/grants/revocation/tamper/unknown/recipient/comercial. Ticket resolve+close compartilha ciclo, Call sócompleted e Activity manual um ciclo por ID; replay de request com payload alterado é rejeitado. Request prova POST→persisted Activity→GET nativo, sem supor completion por ACK. Voz interativa ainda não possui implementação completa; nenhuma escolha implícita de contato/inbox/admin. |
| CS17 Caixa de Respostas | IMPLEMENTADO | `SurveyResponse`, `SurveyLinks`, `SurveyResponseBox`, `SurveyReport`: original imutável, classificação, origem/ciclo/versão/contrato/produto/agente/equipe; recuperação com risk/action/effectkey; tratamento separado; links autorizados para fonte, risco e ação; record_id abre destino exato | shared_surveys/provider/reports/navigation +JS cobrem original e tratamento. Ticket sem vínculo comercial aprovado conserva nil; SD confirmou que service_fields não pode ser reinterpretado como contrato/produto. |
| CS18 Integração de Reuniões | URL externa IMPLEMENTADA; APIs BLOQUEADAS_DEPENDENCIA | QBR registra URL HTTPS real fornecida pelo operador, sem alegar conexão/provisionamento Teams/Meet/Zoom | Faltam API/credenciais/contrato técnico dos providers; nenhuma reunião, convite, gravação ou envio externo foi criado. |

## Service Desk V2 — seções, visibilidade, 13 menus e P0

A matriz a seguir conserva lacunas específicas do Word V2_VISIBILIDADE. Os resultados de lotes intermediários que aparecem nas tabelas de evidência não substituem os gates finais acima.

### Matriz por seção/subseção

| Fonte | Requisito | Estado | Arquivos reais | Prova local | Gap/dependência |
|---|---|---|---|---|---|
| §1 | Relacionamento independente; operadora/Unit/empresa cliente distintos; laterais nativas | LOCAL/PARCIAL | [MENU](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/routeDefinitions.js:1), [CONTEXT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/operational_context.rb:3), [POLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_policy.rb:3) | Escopo nativo preservado; Company mestre e Ticket/Conversation referenciados | QA visual das laterais/ações rápidas não realizada. Contrato/produto exigem origem explícita. |
| §1,§3 | Número somente após persistir; API+GET em operações críticas | LOCAL TESTADO | [CREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_ticket_workflow_service.rb:3), [FORM](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketFormView.vue:1), [CLAIMUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ClaimNext.vue:1) | Idempotência+readback; claim HTTP3 e Vue4 PASS | ID backend é número oficial; SD-000249 é exemplo de apresentação, sem sequência paralela. |
| §3–4 | Informações gerais/classificação/revisão/persistência/filas/estrutura/configurações/telas01–09 | LOCAL/PARCIAL | [FORM](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketFormView.vue:1), [CREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_ticket_workflow_service.rb:3), [SETTINGS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue:1) | Wizard e APIs reais preservados; typed catálogo e classificação scoped | Uploads na abertura interna e todos campos tipo/subcategoria não integralmente ampliados. |
| §3–4 | Notificar criação/confirmação, atendimento, resolução→comunicação→pesquisa→fechamento; tela10 | PARCIAL | [NOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_engine.rb:3), [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3), [SURVEY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_relationship/survey_engine.rb:3) | Atendimento/lifecycle reais, hook compartilhado por ciclo, notificação customer_interaction | Comunicação genérica de cada evento e tela final de preview/destinatários ainda faltam. |
| §5 | Cabeçalho permanente número/título/prioridade/status/fila/equipe/responsável/SLA | LOCAL/PARCIAL | [DETAIL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketDetailView.vue:1), [PRESENTER](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/serializers/jrc_service_desk/presenter.rb:3) | Dados reais no cabeçalho/resumo/painel SLA | Todo o conjunto não está unido no cabeçalho permanente especificado. |
| §5 | Timeline360 notas/mensagens/anexos/ligações/status/tarefas/transferências/aprovações/audit | LOCAL/PARCIAL | [COCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue:1), [API](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/accounts/jrc_service_desk/cockpit_controller.rb:3) | Notas+eventos autorizados; tarefas/approvals/delivery state; referências a conversas | Mensagens nativas e telefonia ainda não compõem timeline única integral. |
| §5 | Composer omnichannel/contexto comercial/actions/NICO | LOCAL/PARCIAL | [COCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue:1), [DETAIL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketDetailView.vue:1), [NICOACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_nico/domain_access.rb:3) | Audiências, canais Conversation reais, task/approval, lifecycle, cliente e KB contextual | Preview completo, contrato/tags/custom completos e ações semânticas NICO dependem outros contratos. |
| §6 | Eventos criado/assumido/status/aguardando/aprovação/resolvido/fechado/reaberto/pesquisa | PARCIAL | [NOTIFPOLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/publish_notification_policy_service.rb:3), [NOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_engine.rb:3), [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3) | SD política atual é event_type=customer_interaction; hooks shared created/closed/reopened/survey | Não implementa toda a tabela por evento/tipo/preferência. OFF não significa engine completo. |
| §6 | Nova resposta pública por e-mail/WhatsApp e nenhum envio de interno/técnico/silent | LOCAL CONTROLADO/PARCIAL | [VIS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/interaction_visibility.rb:3), [NOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_engine.rb:3), [EXEC](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_execution.rb:3) | Canais explicitamente selecionados, recipient real, policy/Inbox/window/SMTP atuais; Email native adapter mockado | WhatsApp real e preferência geral por tipo/evento não homologados; ZERO mensagem real. |
| §6 | Registro canal/template/destinatário/horários/provider/envio/entrega/leitura/erro e resend auditado | LOCAL/PARCIAL | [DELIVERY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/notification_delivery.rb:3), [EXEC](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_execution.rb:3), [RECEIPT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/jobs/jrc_service_desk/notification_reconciliation_job.rb:3), [PRESENTER](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/serializers/jrc_service_desk/presenter.rb:3) | Delivery persistida, source_id/receipt reais, unknown sem retry; note UI tem channel/state/reason | Detalhe integral recipient/template/provider/horários na UI e manual resend dedicado pendentes. |
| §6.1 | Default interno obrigatório persistido; quatro audiences centrais | LOCAL TESTADO | [VIS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/interaction_visibility.rb:3), [NOTE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/ticket_note.rb:3), [MIG12](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/db/migrate/20261008120000_add_jrc_service_desk_visibility_and_operations.rb:3) | Legacy replay/fingerprint preservados; não usa boolean public como outra autoridade | Nenhuma audiência pública por omissão. |
| §6.1 | INTERNAL: operadores autorizados Account/Unit/ticket; TECHNICAL_TEAM: equipe vinculada/cap | LOCAL TESTADO | [VIS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/interaction_visibility.rb:3), [POLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_policy.rb:3), [TASKACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_task_policy.rb:3) | Revogação TeamMember remove nota/evento/tarefa antes de payload, inclusive export/portal | Equipe não amplia Unit. Fornecedor não ganha compartilhamento implícito. |
| §6.1 | CUSTOMER: publish explícito+portal/canais; PUBLIC_WITHOUT_NOTIFICATION: portal sem envio | LOCAL TESTADO/CONFIG OFF | [VIS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/interaction_visibility.rb:3), [CAPS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/capabilities.rb:3), [PORTALSCOPE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_scope.rb:3), [NOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_engine.rb:3) | Ordinaryagent sem customer_publish; silent/internal com channel pedido são rejeitados | Canais externos requerem política/canal/destinatário reais. |
| §6.2 | Seletor de visibilidade antes de enviar; técnico/interno sem mensagem externa | LOCAL TESTADO | [COCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue:1), [VIS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/interaction_visibility.rb:3) | Seleção explícita + autorização backend; técnica vinculada a Team real | UI não concede poder apenas por exibir opção. |
| §6.2 | Botão/appearance conforme audiência, checkboxes canais disponíveis/motivo, destinatário e preview | PARCIAL | [COCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue:1), [API](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/accounts/jrc_service_desk/cockpit_controller.rb:3), [NOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_engine.rb:3) | Seleção de Conversation real por canal, backend impede canal/recipient indevido | Botão publish genérico; faltam quatro rótulos/aparências, preview literal e canal indisponível com motivo. |
| §6.3 | Tarefa com política interna/técnica/portal e publicação de atualizações | LOCAL/PARCIAL | [TASK](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_task_service.rb:3), [TASKUPDATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/update_task_service.rb:3), [TASKACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_task_policy.rb:3) | Audience estável; eventos task_create/update auditados e scoped no portal | Tarefa customer não cria intent/dispatch de notificação por canal ao concluir/criar. |
| §6.3 | Não enviar alterações administrativas; padrões configuráveis de eventos operacionais | PARCIAL/OFF | [ROUTING](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/automatic_routing_service.rb:3), [NOTIFPOLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/publish_notification_policy_service.rb:3), [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3) | Fila/manual/lifecycle produzem audit interno; engine só public interaction | Padrões/tipos de todos eventos da fonte ainda não configuráveis no motor SD. |
| §6.4 | Imutabilidade, correção como nova interação, internal→public com autor/hora/motivo | LOCAL TESTADO | [NOTE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/ticket_note.rb:3), [ADDNOTE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/add_note_service.rb:3), [TOPS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_operations_spec.rb:3) | previous_note_id/reason nova publicação; readonly anterior; motivo ausente negado | Nenhuma mudança silenciosa de audience. |
| §6.4 | Scanner atualiza Blob sem modificar conteúdo/histórico da nota | LOCAL TESTADO | [NOTE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/ticket_note.rb:3), [TCOCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_cockpit_spec.rb:3) | Test compara atributos integrais; body/visibility update segue ReadOnlyRecord | Só timestamp touch de ActiveStorage neutralizado; scanner ausente não vira clean. |
| §6.4 | Audit destinatários/canais/template/provider/receipts/falha e reenvio | LOCAL/PARCIAL | [DELIVERY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/notification_delivery.rb:3), [RECEIPT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/jobs/jrc_service_desk/notification_reconciliation_job.rb:3), [EXEC](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_execution.rb:3) | Delivery armazena vínculo Message/recipient/policy/version/digest/provider; append-only events | UI detalhada e nova tentativa manual por canal ainda incompletas. |
| §6.5 | N1/N2/N3/backoffice/supervisor por capacidades e Company/Unit/Team | LOCAL TESTADO | [CAPS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/capabilities.rb:3), [CONTEXT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/operational_context.rb:3), [POLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_policy.rb:3) | Roles/CustomRole nativos, action/view separados; admin não decide approval de outro ator | Perfis operacionais específicos dependem CustomRole real; sem segundo RBAC. |
| §6.5 | Fornecedor só compartilhado; cliente só público e próprias respostas | LOCAL/PARCIAL | [PORTALSCOPE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_scope.rb:3), [PROOF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_identity_proof.rb:3), [PORTAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/widget/service_desk_controller.rb:3) | Cliente Contact real+HMAC atual+ticket próprio; responses incoming nativas | Não há perfil/grant de fornecedor por interação dedicado. |
| §6.6 | visibility obrigatório; portal_visible/notify_* derivados, author/team/time | LOCAL TESTADO | [VIS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/interaction_visibility.rb:3), [NOTE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/ticket_note.rb:3), [TASK](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_task_service.rb:3), [MIG12](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/db/migrate/20261008120000_add_jrc_service_desk_visibility_and_operations.rb:3) | Quatro valores físicos; boolean lógico derivado de audiência/canais; actor Membership native | Não criar colunas redundantes como outra fonte de verdade. |
| §6.6 | Status por canal/provider e recipient válido | LOCAL/PARCIAL | [DELIVERY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/notification_delivery.rb:3), [EXEC](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_execution.rb:3), [NOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/notification_engine.rb:3) | blocked/queued/dispatching/sent/delivered/read/failed/unknown reais | Note.notification_state legado não prova envio; Delivery.state é autoridade por canal. |
| §6.7 | Cliente não recebe/vê interno/técnico; CUSTOMER público e silent sem envio | LOCAL TESTADO/CONTROLADO | [TOPS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_operations_spec.rb:3), [TPORTAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_spec.rb:3), [TNOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_notifications_spec.rb:3) | Portal HTTP, publicação/negativechannels e nativeEmailboundary; ZERO mensagem real | Homologação provider real ainda não feita. |
| §6.7 | Sem poder não publica/muda audiência; API/portal/export/IA ACL backend e revoke | LOCAL TESTADO/PARCIAL IA | [TCOCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_cockpit_spec.rb:3), [TASKACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_task_policy.rb:3), [NICOACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_nico/domain_access.rb:3) | Same projection de export e scopes; revoke revalida recursos de IA | Resultado salvo NICO deve ser conferido no gate da matriz NICO, não inferido só dos modelos. |
| §6.7 | Timeline mostra audiência/resultado e audit reconstrói publicação | LOCAL/PARCIAL | [COCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue:1), [PRESENTER](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/serializers/jrc_service_desk/presenter.rb:3), [DELIVERY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/notification_delivery.rb:3) | Audience labels e estado por canal; autoria e timestamps persistidos | Detalhe completo destinatário/provider/template/horário e resend não integral na UI. |
| §7 | SLA primeira resposta/solução backend e recibo nativo real | LOCAL TESTADO/PARCIAL | [FIRSTRESPONSE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/native_response_recorder.rb:3), [CLOCKS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_clocks.rb:3), [TNOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_notifications_spec.rb:3) | Defaultsent/caller source_id ignorados; delayedjob usa observed_at, posterior edição não muda achieved_at | Terceiro clock de atendimento não existe. |
| §7 | Calendário/fuso/feriado/pausas e seleção por cliente/contrato/serviço/categoria/prio/canal | LOCAL/PARCIAL/CONFIG | [CALENDAR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/snapshot_calendar.rb:3), [CLOCKS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_clocks.rb:3), [SELECTOR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_selector.rb:3) | Snapshot explícito, calendários existentes e policy Unit/service versionada | Seleção SD completa de todas dimensões não implementada; sem calendário default inventado. |
| §7 | OLA independente por fila/equipe, pausa, limiares70/90/100 e escalonamento | LOCAL/PARCIAL | [OLA](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/ola_tracker.rb:3), [SETTINGS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue:1), [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3) | Intervalos/pause/businesscalendar auditados sem reescrever SLA; transfer preserva histórico | OLA não tem motor completo de thresholds; regra NICO80% não equivale aos três limiares SD. |
| §8 | RoundRobin, menor carga, skill, prioridade/SLA | LOCAL TESTADO/PARCIAL | [ROUTING](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/automatic_routing_service.rb:3), [ORDER](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/dispatch_order.rb:3), [TSUP](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_supervision_spec.rb:3) | RR por eventos persistidos; load open/waiting; required_skills; priority/deadline/opened/id reais | Carga ponderada e skill por categoria/serviço são parciais; skills atualmente por fila. |
| §8 | Manual legado, claim-next atômico, elegibilidade e capacidade | LOCAL TESTADO | [CLAIM](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/claim_next_service.rb:3), [CLAIMUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ClaimNext.vue:1), [TCONCUR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_concurrency_spec.rb:3) | Unit lock+SKIPLOCKED, nativegrants/team/skills/available/positivecapacity;2 claims concorrentes PASS | nilcapacity/unavailable bloqueiam novo claim/auto; não impor esse comportamento à atribuição manual legada. |
| §9 | Task title/description/assignee/due/priority/status/checklist e audit | LOCAL API/PARCIAL UI | [TASK](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_task_service.rb:3), [TASKUPDATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/update_task_service.rb:3), [COCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue:1) | Checklist required complete, stale version negada; backend tem todos campos | UI criação expõe título/checklist/prazo, não todos campos; overdue destaque amplo ainda parcial. |
| §9 | Tarefa vencida no NICO e conclusão encadeia status/notif/próxima/aprovação | PARCIAL/PENDENTE | [SUPERVISOR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/supervision_projection.rb:3), [NICOACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_nico/domain_access.rb:3), [TASKUPDATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/update_task_service.rb:3) | Due_at e overdue aggregates reais; native tools podem ler task autorizada | Não há pipeline automático completo de taskcompletion; validar NICO em sua matriz. |
| §10 | Aprovação real, prazo, approved/rejected/returned/comment/audit | LOCAL TESTADO/PARCIAL | [APPROVAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_approval_service.rb:3), [DECISION](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/decide_approval_service.rb:3), [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3) | Só membro designado; outroadmin negado; rejeição/devolução comentadas; pending fecha conforme regra | Aprovador Team/role, clock SLA próprio/escalonamento e mudança automática de waiting status pendentes. |
| §11 | Incidente principal/filhos, progresso, impacto/causa/workaround/resolução | LOCAL TESTADO/PARCIAL | [INCIDENT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_incident_service.rb:3), [INCIDENTUPDATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/update_incident_service.rb:3), [BOARD](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/OperationsBoardView.vue:1) | Allchildren Unit scoped, primaryticket autorizado, updates geram eventos | Página enriquecida de clientes afetados incompleta; problemas separado continua PlannedView. |
| §11 | Recorrência por categoria/título/serviço/erro/volume e sugestão NICO | DEPENDÊNCIA NICO | [NICOACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_nico/domain_access.rb:3), [INCIDENT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_incident_service.rb:3) | Native incidente e APIs/tools autorizadas disponíveis | Não homologar detector somente por presença da classe; matriz NICO contém regras/evidências. |
| §12 | Catálogo código/nome/descrição/Unit/status/formulário required | LOCAL TESTADO/PARCIAL | [SERVICE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/service.rb:3), [SETTINGS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue:1) | Typed text/integer/boolean/select; rejectunknown/prototype/duplicate; respostas persistidas | Responsável/categoria/equipe padrão integrais ausentes. |
| §12 | SLA/default prioridade/fila/aprovação, ACL cliente/contrato e abertura portal | LOCAL/PARCIAL/OFF | [SERVICE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/service.rb:3), [CREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_ticket_workflow_service.rb:3), [PORTALCREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_creation_service.rb:3) | Defaults reais, versioned service/lifecycle, approval_required e portal Widget+executor revalidados | ACL catálogo por contrato/cliente não existe; approval_required não inventa decisor/fluxo. |
| §13 | KB contextual + NICO resumo/resposta/classificação/risco/sentimento/resolução→artigo | LOCAL/PARCIAL/DEPENDÊNCIA NICO | [KB](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/knowledge_query.rb:3), [KBUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/KnowledgeView.vue:1), [COCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue:1), [NICOACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_nico/domain_access.rb:3) | Reusa Article/Portal/policy publicados; query contexto título e mudança de ticket | Ranking semântico categoria/descrição, sentimento e criação artigo dependem capacidades NICO verificadas. |
| §14 | Meus chamados/número, abrir catálogo, responder/anexar, identidade separada | LOCAL TESTADO/OFF | [PORTAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/widget/service_desk_controller.rb:3), [PORTALCREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_creation_service.rb:3), [PORTALMESSAGE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_customer_message.rb:3), [PORTALUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/widget/components/ServiceDeskPortal.vue:1), [PROOF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_identity_proof.rb:3) | Portal20 PASS:identity5+read6+create6+claim3; requester/conversa/proof; nenhum operador falso | UI não tem busca textual por número dedicada; endpoints resolvem id oficial scoped. |
| §14 | Status/SLA amigável/histórico/KB deflexão/pesquisa | PARCIAL | [PORTAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/widget/service_desk_controller.rb:3), [PORTALUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/widget/components/ServiceDeskPortal.vue:1), [KB](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/knowledge_query.rb:3), [SURVEY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_relationship/survey_engine.rb:3) | Status real, notas/tarefas públicas e próprias replies/anexos | SLA no portal, histórico outgoing/notificações integral, KB pré-abertura e survey incorporada pendentes. |
| §14,§20 | TokenA após merge e prova antiga não lê B; SDK prova só memória por request | LOCAL TESTADO | [PROOF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_identity_proof.rb:3), [PORTALSCOPE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/portal_scope.rb:3), [PROOFJS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/widget/helpers/serviceDeskIdentityProof.js:1), [CONTACTSJS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/widget/api/contacts.js:1), [TPROOF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_identity_spec.rb:3) | MasterOFF merge real403; MasterON clearidentifier nativo+merge403; MasterON guard preservado403/404; hash não retorna/loga | Hmac_verified armazenado nunca é suficiente. Hash não vai a Vuex/cookie/local/sessionstorage/globalheaders. |
| §15 | Pesquisa shared após resolve/close por política/canal/tipo e cliente/ticket/health | INTEGRADO/DEPENDÊNCIA GATE RELATIONSHIP | [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3), [SURVEY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_relationship/survey_engine.rb:3) | Stable cycle_key por último reopen; mesmo ciclo resolved/closed dedupe; AccountUser real; automação OFF | Motor completo/health/entrega homologados pela matriz Relationship, sem survey paralelo SD. |
| §16 | Backlog/SLA/tempos/agentes/volume/qualidade/satisfação/incidentes | LOCAL/PARCIAL | [SUPERVISOR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/supervision_projection.rb:3), [REPORTUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/ReportsView.vue:1), [BOARD](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/OperationsBoardView.vue:1) | Byagent/capacities/latestcycleSLA averages/time-series90dUTC/topcategory, filters+caps; ordinaryagent não supervisor | FCR/reopen/clock atendimento e todas dimensões volume/CSAT/incidentesrank ainda não projetadas. |
| §17 | Status/transições/priority/categorias/filas/skills/capacidade/catálogo/SLA/OLA | LOCAL/PARCIAL | [SETTINGS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue:1), [MEMBER](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/MembershipAvailability.vue:1), [CLOCKS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_clocks.rb:3), [CAPS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/capabilities.rb:3) | Nativeconfiguration finite+auditreadback; typed novos campos e defaults seguros | Impact×urgency/subcategorias/tipos/retention/custom governança completos pendentes. |
| §17 | Templates por evento/automações/escalonamentos/permissões | PARCIAL/OFF | [NOTIFPOLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/publish_notification_policy_service.rb:3), [CAPS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/capabilities.rb:3), [MENU](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/routeDefinitions.js:1) | Evento suportado versionado e CustomRole native action/view | Página automations SD planned; não configurador integral da fonte. |
| §18 | Modelo mínimo entities ticket/event/message/task/SLA/queues/approval/incident/notif/audit | LOCAL/PARCIAL | [MIG12](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/db/migrate/20261008120000_add_jrc_service_desk_visibility_and_operations.rb:3), [MIG14](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/db/migrate/20261008140000_configure_service_desk_portal_creation.rb:3), [DELIVERY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/notification_delivery.rb:3) | Novas/aditivas com compositeFK Account/Unit e nativas; Message/Conversation reutilizadas | Não duplicar ticket_messages/cadastrocliente. Modelo lógico não exige tabelas paralelas. |
| §19 | Tickets/tasks/assign/claim/lifecycle/notif/queues/assignees/automations/incidents APIs | LOCAL/PARCIAL | [ROTAS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/config/routes.rb:3), [API](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/accounts/jrc_service_desk/cockpit_controller.rb:3), [PORTAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/widget/service_desk_controller.rb:3) | Endpoints concretos abaixo; command+ACK+GET e scopes reais | /service-desk do Word recomendado; prefixo legado A preservado. automations/notify generic pendentes. |
| §20 | Account+Unit+ações/view, Team sem ampliarUnit, audit, anexos/scanner/expiry/access | LOCAL TESTADO/PARCIAL | [CONTEXT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/operational_context.rb:3), [POLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_policy.rb:3), [API](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/accounts/jrc_service_desk/cockpit_controller.rb:3), [PORTAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/controllers/api/v1/widget/service_desk_controller.rb:3) | ForeignUnit/Account/revoke negativos; proxy authorizeddownload clean gate sem URL pública direta | Scanner real/retention/expiry/access audit dedicado não implementados; ausência bloqueia download. |
| §21 | CreatedTelefoniaAlta/SLA70/90/100/waitingreminder/resolvedsurvey/detractorhealth | PARCIAL/SHARED | [CREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_ticket_workflow_service.rb:3), [ROUTING](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/automatic_routing_service.rb:3), [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3), [SURVEY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_relationship/survey_engine.rb:3), [NICOACL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_nico/domain_access.rb:3) | Routing real e shared capture/survey hooks; não há automação ativa em cliente real | Não há rule editor SD integral, thresholds/lembretes genéricos; detractorhealth e NICO só via suas matrizes. |
| §23–24 | API real/readback/tests negativos/E2E/visual/log/API/migrations docs/homologação | LOCAL TESTADO/PARCIAL | [TCOCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_cockpit_spec.rb:3), [TCLAIM](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_claim_spec.rb:3), [TCREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_creation_spec.rb:3), [TNOTIF](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_notifications_spec.rb:3), [TCONCUR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_concurrency_spec.rb:3) | Portal20/notification25/concurrency12 ZERO falhas; JS final23 PASS; novasmigrations/docs versionáveis | E2E browser/provider real, QA responsiva e aprovação funcional final do usuário não realizadas. |

### As 13 entradas do menu

| Fonte §2 | Estado real | Arquivos |
|---|---|---|
| 1 Visão geral | KPIs/capacidade/evolução/SLA reais; analytics completo parcial | [SUPERVISOR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/supervision_projection.rb:3), [REPORTUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/ReportsView.vue:1) |
| 2 Chamados | Lista/cockpit/ações scoped, persistidos | [DETAIL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketDetailView.vue:1), [POLICY](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/policies/jrc_service_desk/ticket_policy.rb:3) |
| 3 Minha fila | Atribuídos e claim-next atômico com Unit real/GET | [CLAIM](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/claim_next_service.rb:3), [CLAIMUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ClaimNext.vue:1) |
| 4 Novo chamado | Wizard legado+catálogo/typed fields; uploads internos na abertura parciais | [FORM](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketFormView.vue:1), [CREATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_ticket_workflow_service.rb:3) |
| 5 Filas e equipes | UI modos/skills/OLA e routing real; defaultmanual | [SETTINGS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue:1), [ROUTING](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/automatic_routing_service.rb:3) |
| 6 Responsáveis | Grant nativo, availability/capacity/skills reais | [MEMBER](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/MembershipAvailability.vue:1), [CONTEXT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/operational_context.rb:3) |
| 7 Aprovações | Board real e decisão do ator designado | [BOARD](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/OperationsBoardView.vue:1), [APPROVAL](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_approval_service.rb:3), [DECISION](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/decide_approval_service.rb:3) |
| 8 Problemas / Incidentes | Incidentes pai/filhos operáveis; problemas ainda PlannedView | [INCIDENT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/create_incident_service.rb:3), [INCIDENTUPDATE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/update_incident_service.rb:3), [MENU](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/routeDefinitions.js:1) |
| 9 Catálogo de serviços | Editor tipado/defaults/portal authority; ACL contrato/cliente parcial | [SETTINGS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue:1), [SERVICE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/models/jrc_service_desk/service.rb:3) |
| 10 Base de conhecimento | Published Articles nativos com policy e busca contextual | [KB](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/knowledge_query.rb:3), [KBUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/KnowledgeView.vue:1) |
| 11 Automações | Página SD PlannedView; lifecycle/hooks shared operáveis | [MENU](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/routeDefinitions.js:1), [LIFECYCLE](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/lifecycle_transition_service.rb:3) |
| 12 Relatórios | Agregados reais autorizados; FCR/CSAT/todas dimensões parciais | [SUPERVISOR](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/services/jrc_service_desk/supervision_projection.rb:3), [REPORTUI](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/views/ReportsView.vue:1) |
| 13 Configurações | Recursos finitos com audit/readback; editor V2 e estrutura native | [SETTINGS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue:1), [MEMBER](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/app/javascript/dashboard/routes/dashboard/serviceDesk/components/MembershipAvailability.vue:1) |

### Endpoints concretos e configuração

| Endpoint real | Comportamento |
|---|---|
| GET/POST A/tickets; GET/PATCH A/tickets/:id | Lista/criação/detalhe/update scoped; criação idempotente e número após transação. |
| POST A/tickets/:id/assign, /transfer, /lifecycle | Nativecommands+versão e historicalreadback; resolução/reabertura preservam sourceclock/snapshot. |
| GET A/tickets/:id/cockpit; GET .../export | Mesma projection autorizada para notas/tasks/approvals/events/incident/OLA; exportJSON, não CSV completo. |
| POST A/tickets/:id/interactions | Audience+channels+uploads; republicação previous_note_id+motivo; key/fingerprint. |
| POST A/tickets/:id/tasks; PATCH .../tasks/:record_id | Checklist, optimisticversion e audiência estável; sem dispatch externo da tarefa. |
| POST A/tickets/:id/approvals; POST .../approvals/:record_id/decision | Solicitar e decidir como AccountUser real designado; audit/comment/version. |
| GET A/board?kind=tasks/approvals/incidents | Board real paginado e policy scoped. |
| POST A/incidents; PATCH A/incidents/:incident_id | Pai/filhos autorizados Unit única; update auditado e primaryticket inacessível omitido. |
| POST A/claim_next | Unit explícita; available/capacity/skill/team/caps atuais, Unitlock+SKIPLOCKED; idempotência; ACK+GET antes navegar;422 sanitizado. |
| POST A/notification_policies | Unit/channel/versionedconfirmedpolicy de customer_interaction, Inbox nativo; defaultOFF. |
| GET/POST/PATCH A/configuration/:resource | queues/categories/priorities/statuses/services, contrato finito e auditreceipt/readback. |
| GET A/configuration/portal_options?unit_id=&inbox_id= | Widgets e executores nativos atualmente autorizados; não retorna hmac_token/website_token. |
| GET/POST/PATCH A/structure/:resource | Native grants/membros: availability/capacity/skills separados de active/role. |
| GET A/dashboard; GET A/reports; GET A/knowledge | Agregados scoped e KB Article/Portal; supervisor requer dashboard_view+tickets_view_all. |
| GET W/services; GET W/tickets; GET W/tickets/:id | Catálogo explícito e tickets próprios; identidade nativa+HMAC atual, notes/tasks public apenas. |
| POST W/tickets | Serviço publishedrevision e executor real revalidado; CreateWorkflow+incomingContact; immutablePortalRequest key/fingerprint. |
| POST W/tickets/:id/replies | Contact real/conversation vinculada/sourcekey idempotente/uploads; incomingWebWidget nativo. |
| GET W/tickets/:id/notes/:note_id/attachments/:attachment_id | Nota pública+ticket próprio+currentproof+scan clean; proxy download. |
| GET W/tickets/:id/messages/:message_id/attachments/:attachment_id | Própria reply+ticket próprio+currentproof+scan clean; proxy download. |

### Schema novo e defaults

| Migration nova | Schema e constraints | Defaults |
|---|---|---|
| [MIG12](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/db/migrate/20261008120000_add_jrc_service_desk_visibility_and_operations.rb:3) | Notes/events:audiences/team/notificationchannels/conversations/state e explicitrepublication; queues:routing/skills/OLA; memberships:availability/capacity/skills; tasks/approvals/incidents; notification_policy_versions/deliveries; ola_clocks; Service forms/defaults/approval, Ticketincident/service_fields; compositeFK Account/Unit e nativas Inbox/Message/Conversation. | internal; channels[]; not_requested; queue manual; member unavailable/capacitynil/skills[]; approval_requiredfalse; policy.enabledfalse; delivery blocked; ola_budgetnil/pausefalse. |
| [MIG14](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/db/migrate/20261008140000_configure_service_desk_portal_creation.rb:3) | Service.portal_enabled/inbox/executionMembership reais + configcheck; immutablePortalRequest com Contact/ContactInbox/Inbox/Account/Unit/service/ticket/member/conversation/message/revision/snapshot/key/fingerprint e nativeFKs; key Account+Contact unique. | portal_enabledfalse; Inbox/executor não inferidos; sem login/pessoa/operador fictício. |

### Testes e resultados recebidos

| Suite | Resultado/evidência |
|---|---|
| Portal HTTP final |20 exemplos ZERO falhas:identity5 + portal6 + creation6 + claim3, informados pelo root na rodada security-flow2. Flowfixture isolada não pertence ao SD. |
| Notifications final |25 exemplos ZERO falhas. Inclui3 regressões determinísticas de duplicate/version, receipt read antes de concluir e timeout após duplicate; adapter Email nativo mockado, nenhuma mensagem real. |
| Concorrência PostgreSQL real integrada |12 exemplos ZERO falhas:configuração/lifecycle/2claims/Notificationbuilder+provideronce/Nico2/Survey2. Email/forward_to fixtures UUID corrigidos sem limparDB nem relaxarunique/lock_version. |
| V2 operations/cockpit/supervisor |Suites [TOPS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_operations_spec.rb:3), [TCOCKPIT](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_cockpit_spec.rb:3), [TSUP](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/services/jrc_service_desk/v2_supervision_spec.rb:3) executadas nas rodadas do root; gate agregado final centralizado por ele. Não extrapolar presença de spec para aprovação da homologação inteira. |
| Portal configoptions |4 specs atuais em [TOPTIONS](C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008/spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_configuration_spec.rb:3):grant/cap/scopedWidget/realexecutor/revocation/foreignscope/nosecrets. Confirmar agregado final no relatório do root. |
| JS final proof/widget/claim |4 arquivos23 PASS:ServiceDeskIdentity5, ServiceDeskPortal7, widgetendPoints legado7, ClaimNext4. Inclui storage/header isolation, token returned por setUser, ausência HMAC preserva chat, failedattempt, merge revoga, responseantiga ignorada e revogação imediata do conteúdo. |
| JS configuração/estrutura V2 rodada anterior |7 arquivos103 PASS:configurationContracts48+structureContracts36+configurationViews5+structureView1+v2Configuration4+ConfigurationV2Fields4+portal5 naquela revisão. Portal final evoluiu para7 no grupo acima. |
| JS cockpitcontract/v2projection |8/8 PASS informados pelo root. |
| JS UnitAccess focal após gate ampliado |5/5 PASS. Fixture de membership passou a incluir availability=unavailable, capacity=null e skills=[] conforme StructureContract/StructureRecords backend; igualdade/audit/readback/assertions preservados. |
| ESLint arquivos novos |ZERO erros na revisão identity/API/widget/claim. contacts.js histórico acusa apenas CRLF; stdin normalizado LF sem alterar arquivo:ZERO erros lógicos/format além de lineending. |
| Baseline preexistente |CP5 foreignCompany update_columns corretamente viola FK composta, comprovado pelo root. Nenhuma assertion removida/FK enfraquecida para mascarar. |
| Diffcheck |Limpo na leitura desta área; warnings CRLF conhecidos. Gate final inteiro do root pendente. |

### P0 do Word §22

| ID | Estado preciso |
|---|---|
| P0-01 Criação persistida |LOCAL testado+readback; E2Ebrowser pendente. |
| P0-02 Número único |Idempotência native e concorrência local confirmadas; ID backend oficial. |
| P0-03 Classificação |Escopo/grants/routing/claims reais; matcher comercial amplo ainda parcial. |
| P0-04 SLA |Backend calendar/pause/receipt real; atendimento clock/seleção integral pendentes. |
| P0-05 Minha fila |Claims2 concorrentes e HTTP3+Vue4 PASS, elegibilidade/capacity explícitas. |
| P0-06 Timeline |Audit novas ações real; timeline360/messages/telefonia integral ainda parcial. |
| P0-07 Notificação |NativeEmailboundary/state/receipt/unknown25 PASS; eventos/tipos integrais e provider real ainda sem homologação. |
| P0-08 Multiunidade |API/policies/foreignUnit/revoke negativos locais; sem adminbypass introduzido. |
| P0-09 Resolução |Requirements/versionedlifecycle reais; política concreta deve ser configurada. |
| P0-10 Reabertura |History/cycles preservados, surveycycle estável; reação negativa automática depende matriz NICO/Relationship. |
| P0-11 Portal |Identity5/read6/create6 ZERO falhas, token stale após merge negado, scope próprio. |
| P0-12 Auditoria |Antes/depois/ator/horário nas novas mutações; downloadaccess e manualresend dedicado pendentes. |

## NICO HelpDesk — 11 grupos, R01–R16 e sete KPIs

### CP15A — catálogo e integrações

| Grupo | Fase da fonte | Estado concreto | Capacidade/gap |
|---|---:|---|---|
| A1 Financeiro | 1 | BLOQUEADO_DEPENDENCIA | Faltam contratos Billing de contrato, fatura e entrega segura. Nenhum endpoint inventado. |
| A2 Senhas/acessos | 1 | BLOQUEADO_DEPENDENCIA | Faltam verificação OTP e reset seguro PABX. Não há alteração de senha por inferência de texto. |
| A3 Relatórios/gravações | 1 | BLOQUEADO_DEPENDENCIA | Faltam Reporter query e links protegidos autorizados. |
| A4 Voz/URA | 2 | BLOQUEADO_DEPENDENCIA | Faltam API URA, catálogo de vozes aprovadas e rollback verificável. |
| B1 Usuários/ramais | 2 | BLOQUEADO_DEPENDENCIA | Faltam admin identity, planos/limites e provisionamento PABX. |
| B2 Softphone/IP Phone | 2 | BLOQUEADO_DEPENDENCIA | Faltam registros/tentativas reais de dispositivos PABX. |
| C1 Defeitos de voz | 3, alertas fase 1 | BLOQUEADO_DEPENDENCIA | Detecção interna de ocorrência/SLA é concreta; saúde/recovery de trunks PABX indisponíveis. |
| C2 WhatsApp/chat | 2 | CAPACIDADE_NATIVA_COM_GRANTS | `BrokerHealth` chama `JrcBroker::Control.status` para binding da mesma Account. Pair/QR existentes continuam no catálogo/executor autorizado; nenhum Broker live foi acionado nesta tarefa. |
| D1 Classificação | 1 | NATIVO_COM_REVISAO | Perfil canônico de defeito/tipo, R16 durável e ferramentas SD autorizadas; classificação incerta requer humano. Não autoriza ação a partir de texto do cliente. |
| D2 Humano | 1 | NATIVO_COM_REVISAO | Projetos, notas internas, tarefas e encaminhamento pelos serviços existentes. Cancelamento/comercial/jurídico sensíveis mantêm revisão humana. |
| E Conhecimento | 3 | CAPACIDADE_NATIVA_COM_GRANTS | Busca aprovada existente, com autorização de domínio; não acrescenta documentos externos ou respostas sem fonte. |

### CP15B — R01–R16

| Regra | Implementação concreta | Condição/limite preservado |
|---|---|---|
| R01 | Mesmo defeito canônico/Company, caso anterior aberto ou encerrado há até 14 dias; IDs anteriores, proposta de prioridade uma posição explícita acima, alerta interno para destinatários configurados. | Uma aprovação do mesmo evento não altera prioridade duas vezes. Nova ocorrência é distinta de retry/reabertura/mensagem. |
| R02 | >=3 ocorrências distintas/30 dias; evidência de IDs; proposta de projeto real/nota. | Destinatários N2/CS/Thiago são IDs explícitos, não nomes inferidos. |
| R03 | >=5 ocorrências distintas na janela configurada. | Default 60 dias com `confirmed=false`; a omissão da janela no Word permanece pendente de confirmação versionada. |
| R04 | >=4 Companies distintas/mesmo defeito/60 minutos na Unit autorizada; proposta de incidente nativo com os tickets exatos da evidência. | Revalida todos os filhos. Campanha/mensagem em massa não é enviada. A inclusão posterior de outros filhos é revisão nativa explícita, sem editar a evidência imutável do episódio capturado. |
| R05 | Pré-alerta no percentual configurado do relógio de resolução corrente, antes de consumir todo o budget. | Default 80% com conflito 70/90/100 pendente; `confirmed=false`. Não substitui silenciosamente a política SD. |
| R06 | Deadline registrado ultrapassado (>0). | Relógio native, snapshot de calendário; alerta/diário internos, sem sucesso externo presumido. |
| R07 | >24 horas, configurável. | Confirmação explícita e basis calendar/business obrigatórias antes de habilitar. |
| R08 | >72 horas, configurável. | Mesma distinção temporal; não conta pausa como relógio running. |
| R09 | >7 dias, configurável. | 168 horas úteis não são sete dias corridos; basis/configuração permanecem explícitas e inicialmente pendentes. |
| R10 | Palavras/frases configuradas em notas atestadas e autorizadas; NPS elegível 0–10 <=6; referência à recovery compartilhada existente. | A escala vem da pergunta principal snapshot, mesmo com key `rating`. Não aplica <=6 a CSAT 1–5, não recria RiskCase/Action e não envia reconhecimento ao cliente. |
| R11 | Termos jurídicos configurados; evidência interna protegida; prioridade máxima segundo ordem explícita. | Só ator/admin/destinatários jurídicos configurados podem ler a evidência; não transmite conteúdo jurídico ao cliente. |
| R12 | Company crítica explicitamente aprovada + defeito; alvo alto escolhido por ID nativo ativo para cada Unit do piloto. | Não infere alvo por nome, próximo nível ou máximo. Create/publish e preview bloqueiam alvo ausente, inativo ou de outra Account/Unit. O seletor mostra somente prioridades autorizadas daquela Unit; OFF por default. |
| R13 | 2/5/15 dias configuráveis; anchor por atividade positiva autorizada: notas, tarefas/transições nativas e atestado do operador. | Exclui NICO por comando persistido da mesma Account/ticket/tool/UUID/usuário, comparado a key e actor nativos. Prefixo cliente sozinho não decide origem. `ticket_updated` sem vínculo de origem continua lacuna; não inferido por horário/nome. |
| R14 | Retorno negativo atestado pelo operador com ciclo nativo, ator da Account e timestamp após o close ou a aprovação pendente real do MESMO ticket; proposta de reopen via lifecycle versionado/pinned. | Waiting genérico e boolean legado sem ciclo/tempo não bastam. Eventos correlacionam ciclo e atestado; replay conserva o stamp. Novo ciclo invalida atestado/aprovação antiga e requer novo atestado/revisão. Withdrawal, stamp alterado e tempos passados/futuros bloqueiam execução; não cria outro ticket. |
| R15 | Leitura da SurveyDispatchDecision do motor compartilhado para o mesmo source/cycle. | Não chama outro motor/segunda pesquisa. scheduled/available não são sent. |
| R16 | Ticket novo com serviço/tipo/prioridade incompletos; evidência durável de missing fields e revisão de fila/responsável. | Não executa classificação/atribuição por palpite de LLM. |

### CP15E — sete KPIs

| KPI | Numerador / denominador observado | Estado sem evidência |
|---|---|---|
| K1 | Fechamentos autônomos confirmados / fechamentos native observados. | `sem_dados`: falta prova de confirmação do cliente e de intervenção humana/autonomia; sugestão/toolcall não vira resolução. |
| K2 | Reopens <=14 dias de ticket de defeito / ciclos de fechamento de defeito com janela completa de 14 dias. | Janela ainda aberta/sem cohort -> `sem_dados`; request e nova ocorrência em outro ticket ficam fora. |
| K3 | Completions resolution clock >72h overdue / fechamentos observados. | Basis não confirmado, clock ausente ou falta permission -> `sem_dados`, não zero fictício. |
| K4 | Pré-alertas confirmados entregues antes do deadline / clocks resolution efetivamente vencidos. | Não inclui running ainda dentro do prazo, nem queued como delivered. |
| K5 | Reincidência entregue ao N2 designado <=5min desde a ocorrência / eventos visíveis de reincidência. | Fila entra no atraso; papel ausente/cohort vazio -> `sem_dados`. |
| K6 | Reclamação entregue ao responsável designado <=5min / eventos visíveis de reclamação. | Sem inferir Thiago pelo nome; mesma evidência temporal/recibo. |
| K7 | Pesquisas confirmadas sent para o EXATO ciclo fechado / ciclos de fechamento observados. | scheduled/available não são sent; pesquisa de ciclo anterior não infla cobertura; grants/history/survey ausentes -> `sem_dados`. |

### Matriz final R01–R16: evidência local e dependência precisa

| Regra | Fronteira/negativa efetivamente coberta | Capacidade local / limite que permanece |
|---|---|---|
| R01 | 14 dias inclusive; 14 dias +1s excluído; mesmo defeito/Company; ticket distinto de retry/mensagem. | Captura/correlação e prioridade nativa aprovada uma vez; diagnóstico/recovery de trunk depende de PABX real. |
| R02 | Três ocorrências distintas em 30 dias inclusive; duas e 30 dias +1s excluídos. | Contagem/captura e proposta de `create_project` nativo; os novos casos não provam toda a cadeia aprovação→projeto para esta regra. |
| R03 | Cinco ocorrências/60 dias configurados; quatro e janela +1s excluídos. | Detector/captura locais; janela da fonte precisa confirmação versionada antes de ON. Não é API externa ausente. |
| R04 | Quatro Companies distintas em 60min inclusive; três, Company repetida e 60min +1s excluídos. | Incidente/filhos têm serviços e policies nativos reais; falta homologação de toda a cadeia regra→aprovação→incidente no lote adicional. Comunicação em massa requer caminho de entrega autorizado, não incluído. |
| R05 | 80% aceito; 79,999%, 100% e clock pausado excluídos. | Clock/snapshot e aviso internos concretos; conflito 70/90/100 vs 80 permanece configurável, pendente/OFF. |
| R06 | Deadline +1s aceito; deadline exato excluído. | Vencimento do relógio nativo e captura; nenhuma confirmação externa é presumida. |
| R07 | >24h aceito, 24h exato excluído; relógio nativo nas capturas. | Task/projeto/notas nativos disponíveis com aprovação; basis e destinatários precisam confirmação. O lote adicional não prova todos esses efeitos. |
| R08 | >72h aceito, 72h exato excluído. | Escalação/aviso interno local; basis/destinatários explícitos e inicialmente pendentes. |
| R09 | >7 dias aceito, 7 dias exato excluído; calendar não substitui business. | Calendar snapshot local; divergência 168h úteis vs 7 dias corridos requer decisão de configuração, não integração externa. |
| R10 | NPS 6/7 e escala 0–10; CSAT 1–5 não usa corte NPS; seleção estrangeira/adulterada e grant técnico revogado não produzem texto/evidência. | Busca lexical local e referência à recovery compartilhada; não há inferência semântica/validação humana de conteúdo nem segundo motor de recovery. Reconhecimento ao cliente requer entrega autorizada ausente desta família. |
| R11 | Palavra inteira/termos configurados; nota de outro ticket/Account e nota técnica revogada excluídas. | Evidência jurídica privada e revisão/prioridade internas; não há classificação jurídica semântica nem envio externo ao cliente. |
| R12 | Company crítica e defeito; prioridade explicitamente escolhida para a Unit; ausência/inatividade/Unit ou alvo diferente bloqueados. | Alvo nativo aprovado uma vez; nenhum alvo alto é inferido por nome/ordem/máximo. |
| R13 | 2/5/15 dias; 2 dias −1s excluído; 5 dias −1s conserva nível 1 e 15 dias −1s conserva nível 2. Notas/tarefas nativas humanas vs comando NICO não resetam indevidamente anchor. | Captura por anchor/nível local; `ticket_updated` sem origem nativa verificável permanece excluído. Não se declara evidência de atividade cliente/portal ou de toda transição humana ainda não exercitada especificamente como anchor. |
| R14 | Closed ou aprovação pendente real no mesmo ticket; waiting genérico/boolean legado/tempo anterior ou futuro/ciclo anterior/retirada de atestado bloqueados. | Reopen lifecycle nativo pinned, ticket único e efeito uma vez; novo ciclo exige novo atestado e nova revisão. Não depende de novo endpoint externo. |
| R15 | Closure/trigger/ciclo correntes; motor compartilhado e decision do mesmo source/cycle; reopen muda ciclo. | A captura não dispara outra pesquisa. Disponibilização/sent/response vêm do motor compartilhado e de recibo real; `scheduled`/`available` não provam entrega email/WhatsApp. |
| R16 | Created com campo obrigatório ausente; preenchidos/trigger diferente excluídos. | Pendência de classificação e proposta de atribuição nativa com revisão; não há classificação automática autorizada por palpite de LLM. |

## Relatório diário NICO

Estado: IMPLEMENTADO E TESTADO LOCALMENTE para cálculo e aviso interno; envio HelpDesk por e-mail/WhatsApp BLOQUEADO_DEPENDENCIA de adaptador/destinatário verificados. Não se declara entrega externa com base em preview ou receipt queued.


18h no timezone IANA explícito; somente os AccountUsers designados no papel Thiago e com grants atuais. Sem escolher automaticamente usuário pelo nome. Snapshot de escopo/recipient/date é único; crescimento do backlog não cria segunda entrega diária. Cutoff, hora de configuração, tickets/Company/Unit/serviço/tipo/status/responsável/budget/deadline e diferenças calendar/business são preservados; novos vencidos hoje separados do backlog anterior. Conta reclamação, jurídico protegido, reincidência, root cause, mass incident, estados/escalations somente após revalidar cada evento.

Recibo independente por canal/source/recipient evita repetir NICO confirmado quando email/WhatsApp estão bloqueados. Apenas aviso NICO interno tem caminho concreto nesta extensão; email/WhatsApp ficam `blocked_verified_recipient_and_delivery_adapter_required`. Unknown não é reenviado. Preview não persiste relatório/recibo/notificação e não envia.



## CRM Leads

VALIDADO_LOCAL: cards compactos preservam números reais; Lista/Kanban, busca/filtros, Novo Lead, qualificação, exclusão, responsáveis, origem, próximo passo e APIs permanecem. Script comparado por AST à base, exceto quatro classes de cor. Dois arquivos/10 testes passaram no lote final. Preview do componente real em 1520/640/390 px, claro/escuro, preservou seis colunas por scroll horizontal necessário: altura dos cards 114→58 px; tabela aparece em y507→283 desktop, y637→349 tablet e y941→489 mobile. Nenhum redesenho geral do CRM.

## Lacunas locais restantes — não atribuir artificialmente a APIs externas

- CS: continuações assíncronas/inputs/delay e efeitos externos de playbook exigem guard de continuação/entrega; pesquisa interativa de voz e QR dedicado; BI e denominadores completos eligible→sent→responded; aceite E2E da cadeia integral de renovação.
- SD: matriz completa de notificações por todos os eventos; preview literal/destinatário/motivos e aparência por audiência no composer; notificação de tarefas; timeline360 integral com mensagens/telefonia; SLA/histórico/KB pré-abertura no portal; dimensões/FCR de supervisão; Problems/Changes/Assets ainda sem engine completo.
- NICO: origem genérica verificável de ticket_updated (R13), confirmação do cliente/autonomia para K1 e adapters verificáveis de delivery externo do diário. Catálogos de Billing/PABX/OTP/Reporter/URA dependem de APIs e contratos reais ausentes.
- Qualidade: RuboCop novo de estilo/complexidade ainda pendente; não alterar código histórico ou desabilitar cops para obter verde.

## Preservação verificada

`b2001cb40ebe1eb1e8f3a97e1559b901199adf71` é ancestral da base/HEAD. Os 157 arquivos antes ausentes na branch incompleta estão presentes, incluindo as oito migrations históricas abaixo. Zero exclusões nesta entrega, zero mudanças em migrations históricas/schema, provider IA, SafeLogger, Runtime, Compose, lockfiles ou workflows. Novo filtro mínimo `identifier_hash` evita que a prova de identidade do portal apareça em logs; não muda a seleção de provedor. Chaves continuam no backend por Account, sem cópia para .env/frontend.

Customer360/Timeline e hooks do envio/CSAT foram integrados com grants atuais. Regressão ampla anterior: base/candidato 401 exemplos e as mesmas cinco falhas históricas. Repetição final dos módulos afetados: base/candidato 119 exemplos e as mesmas três falhas históricas. NICO legado, Broker/Flows/canais/CRM/Projetos/Agenda não foram substituídos por outro motor.

- `db/migrate/20261004170000_complete_jrc_customer_master_company_profile.rb`
- `db/migrate/20261004183000_strengthen_sales_order_origin_and_audit.rb`
- `db/migrate/20261004234000_create_jrc_operations_routing_and_sla.rb`
- `db/migrate/20261005180000_create_jrc_relationship.rb`
- `db/migrate/20261005190000_allow_direct_customer_proposals.rb`
- `db/migrate/20261005200000_extend_relationship_operations.rb`
- `db/migrate/20261005210000_add_relationship_playbook_conditions.rb`
- `db/migrate/20261005220000_extend_commercial_operational_configuration.rb`

## Seis migrations aditivas — apenas bancos locais de teste

| Arquivo | SHA256 congelado |
|---|---|
| `20261008110000_complete_relationship_shared_surveys.rb` | `33548d5df8926ed52864c351bbabf12f88dd5f305eae7b8d2067eac0f6de1712` |
| `20261008120000_add_jrc_service_desk_visibility_and_operations.rb` | `b505a46e0589f947d267481b7d185b298abd4ae03518fbd5489b342bbef49c46` |
| `20261008130000_create_jrc_nico_helpdesk.rb` | `92cf34b3c629d4c0c6254ad83d859fcd8fae9146f56a402e72ea3e64f6f806a1` |
| `20261008135000_allow_revocation_of_shared_survey_executor.rb` | `b7bb3adb8479f9ab445574e91c54f0ef3ca861b2c32a8457de63045fe94d3d48` |
| `20261008140000_configure_service_desk_portal_creation.rb` | `8044ad00908f151ca0bb423789637c85215ecf88d223f540599d4bf1ad87b241` |
| `20261008150000_complete_relationship_native_lineage.rb` | `884d4183c23ec341ae5f914777e20855df75367b662132c921ed40397ea78f05` |

Rollout/recuperação e políticas ainda não aprovadas: DEPENDENCIAS_E_ATIVACAO.md e CONFLITOS_E_DECISOES.md. Não há backfill monetário presumido nem execução em servidor.

## Lista exata de arquivos desta entrega

| Estado | Arquivo |
|---|---|
| A | `app/controllers/api/v1/accounts/jrc_nico/helpdesk_controller.rb` |
| A | `app/controllers/api/v1/accounts/jrc_service_desk/cockpit_controller.rb` |
| A | `app/controllers/api/v1/accounts/jrc_service_desk/knowledge_controller.rb` |
| A | `app/controllers/api/v1/accounts/relationship/handoffs_controller.rb` |
| A | `app/controllers/api/v1/accounts/relationship/survey_administration_controller.rb` |
| A | `app/controllers/api/v1/widget/service_desk_controller.rb` |
| A | `app/javascript/dashboard/api/jrcNicoHelpdesk.js` |
| A | `app/javascript/dashboard/api/serviceDeskCockpit.js` |
| A | `app/javascript/dashboard/api/serviceDeskOperationsV2.js` |
| A | `app/javascript/dashboard/i18n/locale/en/jrcNicoHelpdesk.json` |
| A | `app/javascript/dashboard/routes/dashboard/crm/views/leads/spec/LeadsIndex.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/jrcNico/HelpdeskPage.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcNico/HelpdeskPolicyForm.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcNico/helpdesk.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/jrcNico/routes.js` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/HandoffPanel.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/ManualAttendancePanel.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/PlaybookDesignPreview.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/PlaybookExecutionPanel.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyAdministrationPanel.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyReportFilters.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyReportSummary.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/SurveyResponseBox.vue` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/nativeCompletions.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/nativeLineage.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/jrcRelationship/sharedSurveys.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/CatalogueAnswers.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/ClaimNext.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationV2Fields.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/MembershipAvailability.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/SupervisorPanel.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/TicketCockpit.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/spec/ClaimNext.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/spec/ConfigurationV2Fields.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/catalogueFields.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/cockpitContract.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/cockpitContract.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/v2Configuration.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/v2Projection.spec.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/v2Configuration.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/v2Labels.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/v2Projection.js` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/KnowledgeView.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/OperationsBoardView.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/ReportsView.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/ServiceCatalogView.vue` |
| A | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/spec/KnowledgeView.spec.js` |
| A | `app/javascript/widget/api/serviceDesk.js` |
| A | `app/javascript/widget/api/specs/serviceDeskIdentity.spec.js` |
| A | `app/javascript/widget/components/ServiceDeskPortal.vue` |
| A | `app/javascript/widget/components/spec/ServiceDeskPortal.spec.js` |
| A | `app/javascript/widget/helpers/serviceDeskIdentityProof.js` |
| A | `app/javascript/widget/helpers/serviceDeskPortal.js` |
| A | `app/jobs/jrc_nico/helpdesk/event_job.rb` |
| A | `app/jobs/jrc_nico/helpdesk/monitor_job.rb` |
| A | `app/jobs/jrc_relationship/native_csat_response_job.rb` |
| A | `app/jobs/jrc_relationship/survey_closure_job.rb` |
| A | `app/jobs/jrc_relationship/survey_dispatch_job.rb` |
| A | `app/jobs/jrc_relationship/survey_receipt_job.rb` |
| A | `app/jobs/jrc_service_desk/first_response_job.rb` |
| A | `app/jobs/jrc_service_desk/notification_delivery_job.rb` |
| A | `app/jobs/jrc_service_desk/notification_reconciliation_job.rb` |
| A | `app/models/concerns/jrc_relationship/survey_message_receipts.rb` |
| A | `app/models/concerns/jrc_service_desk/notification_receipts.rb` |
| A | `app/models/jrc_nico/helpdesk/approval.rb` |
| A | `app/models/jrc_nico/helpdesk/control_event.rb` |
| A | `app/models/jrc_nico/helpdesk/daily_report.rb` |
| A | `app/models/jrc_nico/helpdesk/delivery_receipt.rb` |
| A | `app/models/jrc_nico/helpdesk/event.rb` |
| A | `app/models/jrc_nico/helpdesk/policy_control.rb` |
| A | `app/models/jrc_nico/helpdesk/policy_version.rb` |
| A | `app/models/jrc_nico/helpdesk/ticket_profile.rb` |
| A | `app/models/jrc_relationship/handoff_case.rb` |
| A | `app/models/jrc_relationship/playbook_execution.rb` |
| A | `app/models/jrc_relationship/playbook_version.rb` |
| A | `app/models/jrc_relationship/survey_definition.rb` |
| A | `app/models/jrc_relationship/survey_dispatch_decision.rb` |
| A | `app/models/jrc_relationship/survey_rule.rb` |
| A | `app/models/jrc_relationship/survey_version.rb` |
| A | `app/models/jrc_service_desk/incident.rb` |
| A | `app/models/jrc_service_desk/notification_delivery.rb` |
| A | `app/models/jrc_service_desk/notification_policy_version.rb` |
| A | `app/models/jrc_service_desk/ola_clock.rb` |
| A | `app/models/jrc_service_desk/portal_request.rb` |
| A | `app/models/jrc_service_desk/ticket_approval.rb` |
| A | `app/models/jrc_service_desk/ticket_task.rb` |
| A | `app/policies/jrc_service_desk/incident_policy.rb` |
| A | `app/policies/jrc_service_desk/ticket_approval_policy.rb` |
| A | `app/policies/jrc_service_desk/ticket_task_policy.rb` |
| A | `app/services/jrc_nico/helpdesk/action_preview.rb` |
| A | `app/services/jrc_nico/helpdesk/approvals.rb` |
| A | `app/services/jrc_nico/helpdesk/broker_health.rb` |
| A | `app/services/jrc_nico/helpdesk/capture.rb` |
| A | `app/services/jrc_nico/helpdesk/catalog.rb` |
| A | `app/services/jrc_nico/helpdesk/context.rb` |
| A | `app/services/jrc_nico/helpdesk/controls.rb` |
| A | `app/services/jrc_nico/helpdesk/cycle_evidence.rb` |
| A | `app/services/jrc_nico/helpdesk/daily_reporter.rb` |
| A | `app/services/jrc_nico/helpdesk/definition.rb` |
| A | `app/services/jrc_nico/helpdesk/delivery.rb` |
| A | `app/services/jrc_nico/helpdesk/event_processor.rb` |
| A | `app/services/jrc_nico/helpdesk/execution_guard.rb` |
| A | `app/services/jrc_nico/helpdesk/facts.rb` |
| A | `app/services/jrc_nico/helpdesk/kpis.rb` |
| A | `app/services/jrc_nico/helpdesk/policies.rb` |
| A | `app/services/jrc_nico/helpdesk/profile_writer.rb` |
| A | `app/services/jrc_nico/helpdesk/rule_detector.rb` |
| A | `app/services/jrc_nico/helpdesk_tool_actions.rb` |
| A | `app/services/jrc_nico/helpdesk_tool_catalog.rb` |
| A | `app/services/jrc_relationship/commercial_eligibility.rb` |
| A | `app/services/jrc_relationship/commercial_return.rb` |
| A | `app/services/jrc_relationship/customer_timeline.rb` |
| A | `app/services/jrc_relationship/manual_attendance.rb` |
| A | `app/services/jrc_relationship/playbook_flow.rb` |
| A | `app/services/jrc_relationship/playbook_flow_reference.rb` |
| A | `app/services/jrc_relationship/playbook_preview.rb` |
| A | `app/services/jrc_relationship/risk_financial_snapshot.rb` |
| A | `app/services/jrc_relationship/survey_administration.rb` |
| A | `app/services/jrc_relationship/survey_engine.rb` |
| A | `app/services/jrc_relationship/survey_execution_context.rb` |
| A | `app/services/jrc_relationship/survey_links.rb` |
| A | `app/services/jrc_relationship/survey_message_execution.rb` |
| A | `app/services/jrc_relationship/survey_metrics.rb` |
| A | `app/services/jrc_relationship/survey_question_schema.rb` |
| A | `app/services/jrc_relationship/survey_report.rb` |
| A | `app/services/jrc_relationship/survey_response.rb` |
| A | `app/services/jrc_relationship/survey_source.rb` |
| A | `app/services/jrc_relationship/survey_summary.rb` |
| A | `app/services/jrc_service_desk/automatic_routing_service.rb` |
| A | `app/services/jrc_service_desk/claim_next_service.rb` |
| A | `app/services/jrc_service_desk/create_approval_service.rb` |
| A | `app/services/jrc_service_desk/create_incident_service.rb` |
| A | `app/services/jrc_service_desk/create_task_service.rb` |
| A | `app/services/jrc_service_desk/decide_approval_service.rb` |
| A | `app/services/jrc_service_desk/dispatch_order.rb` |
| A | `app/services/jrc_service_desk/interaction_attachments.rb` |
| A | `app/services/jrc_service_desk/interaction_visibility.rb` |
| A | `app/services/jrc_service_desk/knowledge_query.rb` |
| A | `app/services/jrc_service_desk/native_execution_context.rb` |
| A | `app/services/jrc_service_desk/native_response_recorder.rb` |
| A | `app/services/jrc_service_desk/notification_engine.rb` |
| A | `app/services/jrc_service_desk/notification_execution.rb` |
| A | `app/services/jrc_service_desk/ola_tracker.rb` |
| A | `app/services/jrc_service_desk/portal_configuration_options.rb` |
| A | `app/services/jrc_service_desk/portal_creation_service.rb` |
| A | `app/services/jrc_service_desk/portal_customer_message.rb` |
| A | `app/services/jrc_service_desk/portal_identity_proof.rb` |
| A | `app/services/jrc_service_desk/portal_identity_required.rb` |
| A | `app/services/jrc_service_desk/portal_scope.rb` |
| A | `app/services/jrc_service_desk/publish_notification_policy_service.rb` |
| A | `app/services/jrc_service_desk/recorded_changes.rb` |
| A | `app/services/jrc_service_desk/supervision_projection.rb` |
| A | `app/services/jrc_service_desk/update_incident_service.rb` |
| A | `app/services/jrc_service_desk/update_task_service.rb` |
| A | `app/views/relationship_surveys/show.html.erb` |
| A | `db/migrate/20261008110000_complete_relationship_shared_surveys.rb` |
| A | `db/migrate/20261008120000_add_jrc_service_desk_visibility_and_operations.rb` |
| A | `db/migrate/20261008130000_create_jrc_nico_helpdesk.rb` |
| A | `db/migrate/20261008135000_allow_revocation_of_shared_survey_executor.rb` |
| A | `db/migrate/20261008140000_configure_service_desk_portal_creation.rb` |
| A | `db/migrate/20261008150000_complete_relationship_native_lineage.rb` |
| A | `docs/relacionamento-servicedesk-v2-20261008/CHECKPOINTS_E_CONTINUIDADE.md` |
| A | `docs/relacionamento-servicedesk-v2-20261008/CONFLITOS_E_DECISOES.md` |
| A | `docs/relacionamento-servicedesk-v2-20261008/DEPENDENCIAS_E_ATIVACAO.md` |
| A | `docs/relacionamento-servicedesk-v2-20261008/INVENTARIO_E_COBERTURA.md` |
| A | `docs/relacionamento-servicedesk-v2-20261008/TESTES_E_EVIDENCIAS.md` |
| A | `spec/enterprise/models/call_shared_survey_spec.rb` |
| A | `spec/listeners/jrc_shared_survey_listener_spec.rb` |
| A | `spec/requests/api/v1/accounts/jrc_service_desk/v2_claim_spec.rb` |
| A | `spec/requests/api/v1/accounts/jrc_service_desk/v2_cockpit_spec.rb` |
| A | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_configuration_spec.rb` |
| A | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_creation_spec.rb` |
| A | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_identity_spec.rb` |
| A | `spec/requests/api/v1/accounts/jrc_service_desk/v2_portal_spec.rb` |
| A | `spec/requests/api/v1/accounts/relationship/native_completions_spec.rb` |
| A | `spec/requests/api/v1/accounts/relationship/shared_surveys_spec.rb` |
| A | `spec/requests/api/v1/accounts/relationship/survey_reports_spec.rb` |
| A | `spec/requests/jrc_nico_helpdesk_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/approvals_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/capture_boundaries_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/concurrency_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/controls_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/cycle_evidence_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/delivery_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/kpis_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/native_tools_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/policies_spec.rb` |
| A | `spec/services/jrc_nico/helpdesk/rule_detector_spec.rb` |
| A | `spec/services/jrc_relationship/configuration_guards_spec.rb` |
| A | `spec/services/jrc_relationship/lineage_navigation_spec.rb` |
| A | `spec/services/jrc_relationship/native_completions_spec.rb` |
| A | `spec/services/jrc_relationship/native_lineage_spec.rb` |
| A | `spec/services/jrc_relationship/playbook_flow_spec.rb` |
| A | `spec/services/jrc_relationship/playbook_integration_spec.rb` |
| A | `spec/services/jrc_relationship/shared_surveys_spec.rb` |
| A | `spec/services/jrc_relationship/survey_concurrency_spec.rb` |
| A | `spec/services/jrc_relationship/survey_provider_boundary_spec.rb` |
| A | `spec/services/jrc_service_desk/knowledge_query_spec.rb` |
| A | `spec/services/jrc_service_desk/v2_concurrency_spec.rb` |
| A | `spec/services/jrc_service_desk/v2_notifications_spec.rb` |
| A | `spec/services/jrc_service_desk/v2_operations_spec.rb` |
| A | `spec/services/jrc_service_desk/v2_supervision_spec.rb` |
| M | `app/controllers/api/v1/accounts/jrc_service_desk/configuration_controller.rb` |
| M | `app/controllers/api/v1/accounts/jrc_service_desk/dashboard_controller.rb` |
| M | `app/controllers/api/v1/accounts/jrc_service_desk/service_definitions_controller.rb` |
| M | `app/controllers/api/v1/accounts/relationship/configuration_controller.rb` |
| M | `app/controllers/api/v1/accounts/relationship/dashboard_controller.rb` |
| M | `app/controllers/api/v1/accounts/relationship/portfolio_controller.rb` |
| M | `app/controllers/api/v1/accounts/relationship/records_controller.rb` |
| M | `app/controllers/relationship_surveys_controller.rb` |
| M | `app/javascript/dashboard/api/jrcRelationship.js` |
| M | `app/javascript/dashboard/api/serviceDeskConfigurationClient.js` |
| M | `app/javascript/dashboard/api/serviceDeskOperationsClient.js` |
| M | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` |
| M | `app/javascript/dashboard/constants/serviceDeskPermissions.js` |
| M | `app/javascript/dashboard/i18n/locale/en/customRole.json` |
| M | `app/javascript/dashboard/i18n/locale/en/index.js` |
| M | `app/javascript/dashboard/i18n/locale/en/jrcServiceDesk.json` |
| M | `app/javascript/dashboard/i18n/locale/en/relationship.json` |
| M | `app/javascript/dashboard/routes/dashboard/crm/views/leads/LeadsIndex.vue` |
| M | `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` |
| M | `app/javascript/dashboard/routes/dashboard/jrcRelationship/ConfigurationPanel.vue` |
| M | `app/javascript/dashboard/routes/dashboard/jrcRelationship/CustomerPanel.vue` |
| M | `app/javascript/dashboard/routes/dashboard/jrcRelationship/ModulePage.vue` |
| M | `app/javascript/dashboard/routes/dashboard/jrcRelationship/RecordEditor.vue` |
| M | `app/javascript/dashboard/routes/dashboard/jrcRelationship/RenewalPipeline.vue` |
| M | `app/javascript/dashboard/routes/dashboard/jrcRelationship/definitions.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/unitAccess.spec.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/components/ConfigurationManager.vue` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/configuration.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/drafts.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/lifecycle.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/operationalContracts.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/structure.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/routeDefinitions.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/routes.js` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/StructureView.vue` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketDetailView.vue` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketFormView.vue` |
| M | `app/javascript/dashboard/routes/dashboard/serviceDesk/views/TicketListView.vue` |
| M | `app/javascript/widget/api/contacts.js` |
| M | `app/javascript/widget/i18n/locale/en.json` |
| M | `app/javascript/widget/views/Home.vue` |
| M | `app/jobs/jrc_relationship/signal_job.rb` |
| M | `app/jobs/send_reply_job.rb` |
| M | `app/listeners/csat_survey_listener.rb` |
| M | `app/models/csat_survey_response.rb` |
| M | `app/models/jrc_relationship/configuration.rb` |
| M | `app/models/jrc_relationship/expansion_signal.rb` |
| M | `app/models/jrc_relationship/health_snapshot.rb` |
| M | `app/models/jrc_relationship/playbook.rb` |
| M | `app/models/jrc_relationship/qbr.rb` |
| M | `app/models/jrc_relationship/record.rb` |
| M | `app/models/jrc_relationship/risk_case.rb` |
| M | `app/models/jrc_relationship/success_plan.rb` |
| M | `app/models/jrc_relationship/survey.rb` |
| M | `app/models/jrc_service_desk/queue.rb` |
| M | `app/models/jrc_service_desk/service.rb` |
| M | `app/models/jrc_service_desk/ticket.rb` |
| M | `app/models/jrc_service_desk/ticket_event.rb` |
| M | `app/models/jrc_service_desk/ticket_note.rb` |
| M | `app/models/jrc_service_desk/unit_membership.rb` |
| M | `app/models/message.rb` |
| M | `app/policies/jrc_service_desk/ticket_event_policy.rb` |
| M | `app/policies/jrc_service_desk/ticket_note_policy.rb` |
| M | `app/policies/jrc_service_desk/ticket_policy.rb` |
| M | `app/policies/jrc_service_desk/ticket_record_policy.rb` |
| M | `app/serializers/jrc_service_desk/presenter.rb` |
| M | `app/services/jrc_customers/customer360.rb` |
| M | `app/services/jrc_customers/timeline.rb` |
| M | `app/services/jrc_nico/domain_access.rb` |
| M | `app/services/jrc_nico/operator_session.rb` |
| M | `app/services/jrc_nico/tool_catalog.rb` |
| M | `app/services/jrc_nico/tool_executor.rb` |
| M | `app/services/jrc_relationship/context.rb` |
| M | `app/services/jrc_relationship/customer_signals.rb` |
| M | `app/services/jrc_relationship/eligibility.rb` |
| M | `app/services/jrc_relationship/handoff.rb` |
| M | `app/services/jrc_relationship/health_score.rb` |
| M | `app/services/jrc_relationship/playbook_steps.rb` |
| M | `app/services/jrc_relationship/playbooks.rb` |
| M | `app/services/jrc_relationship/presenter.rb` |
| M | `app/services/jrc_relationship/processor.rb` |
| M | `app/services/jrc_relationship/renewal_window.rb` |
| M | `app/services/jrc_relationship/survey_delivery.rb` |
| M | `app/services/jrc_relationship/work_context.rb` |
| M | `app/services/jrc_relationship/workflow.rb` |
| M | `app/services/jrc_service_desk/add_note_service.rb` |
| M | `app/services/jrc_service_desk/assign_ticket_service.rb` |
| M | `app/services/jrc_service_desk/capabilities.rb` |
| M | `app/services/jrc_service_desk/configuration_contract.rb` |
| M | `app/services/jrc_service_desk/create_ticket_service.rb` |
| M | `app/services/jrc_service_desk/create_ticket_workflow_service.rb` |
| M | `app/services/jrc_service_desk/dashboard_service.rb` |
| M | `app/services/jrc_service_desk/lifecycle_transition_service.rb` |
| M | `app/services/jrc_service_desk/structure_contract.rb` |
| M | `app/services/jrc_service_desk/ui_context_service.rb` |
| M | `config/initializers/filter_parameter_logging.rb` |
| M | `config/routes.rb` |
| M | `config/schedule.yml` |
| M | `enterprise/app/models/call.rb` |

## Inventário CP0 preservado como registro histórico

As conclusões estruturais iniciais abaixo são o inventário de partida; o estado corrente é a matriz final acima.

<!-- CP0_HISTORICAL -->
# Inventário e cobertura integrada

## Base e autorização

Repositório: ClaudioHideki/jrc-conversas-lab2. Branch: codex/relacionamento-servicedesk-v2-20261008.
HEAD inicial e base aprovada: 4ce8241d35ce862e9d53e9a5dce4df9a1858432c. Ancestralidade confirmada (exit 0), origin exclusivo do repositório esperado, working tree inicial limpo.
Os dois prompts anexados são idênticos (SHA256 D84CFA53AA84BF1567EDC2F4063630B288A27406EA42707BB63141D18A02F7E9); foi usado um só.
CP0 concluído antes de editar código funcional. As matrizes abaixo descrevem a base aprovada; evolução e testes serão registrados separadamente.
IMPLEMENTADO_PARCIAL e ESTRUTURA_EXISTENTE não significam validação funcional. Somente execução pertinente com evidência autoriza promoção do status.
Linhas de código nas auditorias referem-se ao HEAD inicial. Nenhum dado pessoal ou ticket do Excel foi importado.
O ZIP antigo não foi usado para substituir Git. Fontes originais e extrações completas permanecem fora do projeto.

## CRM Leads / CP14

Fonte: Captura de tela 2026-10-08 085111.png e §13 do prompt.
Status inicial: IMPLEMENTADO_PARCIAL. LeadsIndex.vue já tem números reais, lista/Kanban, busca, filtros, criação, detalhe, qualificação, conversão e exclusão. Lacuna: margens e cards altos, filtros empilhados; compactar somente layout mantendo handlers/APIs e operações. Aceite: mesma viewport e tela menor, claro/escuro, sem corte de ações; testes lista/Kanban e filtros/qualificação.

# Auditoria CP0 do Relacionamento e motor de pesquisas

Data: 2026-10-08. Auditoria somente leitura do Git aprovado. Existem fluxos substanciais de Customer Success; o novo Word acrescenta governança, telas e motor de pesquisas que ainda não estão completos. Nenhum item foi classificado como IMPLEMENTADO_FUNCIONAL nesta auditoria porque as suítes não foram executadas. A presença de testes é evidência de intenção e cobertura disponível, não resultado de execução.

## Base e fontes

- Checkout: `C:/Users/DEV03/Documents/Jrc/ia-provedor-unico-20261007`.
- Origin confirmado por `git remote get-url origin`: `https://github.com/ClaudioHideki/jrc-conversas-lab2.git`.
- Branch de leitura: `codex/ia-provedor-unico-20261007`.
- HEAD e base: `4ce8241d35ce862e9d53e9a5dce4df9a1858432c`.
- `git merge-base --is-ancestor 4ce8241d35ce862e9d53e9a5dce4df9a1858432c HEAD`: exit 0.
- `git status --porcelain=v1`: vazio antes e durante a auditoria.
- `AGENTS.md` lido integralmente. Nenhum código, branch, índice Git, configuração, migration ou dado alterado por este agente.
- Prompt lido integralmente: `C:/Users/DEV03/.codex/attachments/a1653d0b-2d80-4a95-a934-6c23d0960ebc/Texto colado.txt`.
- Word utilizado: `C:/Users/DEV03/Downloads/JRC_Conversas_Modulo_Relacionamento_Especificacao_DEV_V2_NPS.docx`.
- SHA256 da fonte: `0D341913EB8D2C43F3BEF9B35A3F319DD3AE95350C93F1308DD09C67A8C4DF78`.
- O título interno declara **Versão 1.1, Outubro/2026, Atualização Motor de Pesquisas e NPS por canal**; o nome de download contém V2_NPS. Essa diferença é de identificação da fonte, sem alegar equivalência com versões antigas.
- Leitura integral de `word/document.xml`, footer e 31 tabelas. A extração em `relationship-source.txt` preserva todos os 684 textos do corpo e apresenta as tabelas também em linhas/células. Não houve renderização nem alegação sobre layout ou páginas.
- Skill usada: `C:/Users/DEV03/.codex/plugins/cache/openai-primary-runtime/documents/26.915.20218/skills/documents/SKILL.md`. Extração com Python bundled `C:/Users/DEV03/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.

Os caminhos de evidência abaixo são relativos ao checkout, com linhas verificadas nesta base. Seções da fonte são as seções internas do Word; os requisitos de segurança adicionais vêm do prompt, e não são apresentados como existentes no Word.

## Fundação a preservar

- `app/models/jrc_customers/company.rb:3` usa `companies`; Assignment referencia a mesma Company (`app/models/jrc_relationship/assignment.rb:4`) e valida um único company/contact e tenant (`:23`). A migration `db/migrate/20261005180000_create_jrc_relationship.rb` possui `rel_one_identity`, `rel_unique_company`, `rel_unique_contact` e FKs. Não há tabela de cópias de empresas CS.
- `app/services/jrc_customers/customer360.rb:4` agrega origens nativas e valida tenant; `:109` separa Service Desk/Projetos; `:126` agrega contratos/pedidos; `:142` integra Assignment e `:149` filtra auditorias pelas permissões atuais.
- `app/policies/jrc_relationship/module_policy.rb:4` exige conta ativa, feature `jrc_relationship`, Cadastro Mestre e permissão. AssignmentPolicy distingue carteira própria/equipe e usa OrganizationalVisibility com `include_company: false`, preservando cliente versus operadora (`app/policies/jrc_relationship/assignment_policy.rb:15`).
- `app/services/jrc_relationship/context.rb:33` restringe records por tenant/carteira e capacidades das origens, inclusive IDs em planos; `:78` assina permissões e membros; `SnapshotAccess` revalida origens de snapshots e ações derivadas.
- Menu independente confirmado em `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:1298`; 13 telas atuais em `app/javascript/dashboard/routes/dashboard/jrcRelationship/definitions.js:1`, com rotas próprias em `routes.js:9`. Não está subordinado ao Service Desk.
- Rotas API em `config/routes.rb:409`: metadata/dashboard/drilldown/team, portfolio, records, opportunity, batch, entrega/link de pesquisa, export/export_history, configuration e playbooks. Feature flag em `config/features.yml:306`.
- Eventos existentes: `SignalDispatch` after_commit → SignalJob; allowlist do job inclui pedidos, backoffice, contratos, faturas, Agenda, tickets, projetos, CSAT nativo e Survey. Scheduler a cada 15 minutos e monitor SLA a cada 5 minutos (`config/schedule.yml:91`, `:101`). Não há permissão concedida por texto do cliente.
- Camada NICO para CS existente em `app/services/jrc_nico/domain_actions.rb:84` e `domain_access.rb:67`; o contexto vem de objetos autorizados. `NicoSummaryPanel.vue` usa o NICO existente. Esta auditoria não altera provider nem configuração global de IA.

## Matriz das 18 áreas

Todos os status parciais abaixo significam implementação verificável por leitura e suítes existentes ainda não executadas. Os critérios de aceite são o que precisa ser comprovado no checkpoint, sem ativação real.

| ID e fonte | Comportamento esperado | Implementação e evidência | Status | Lacuna e dependência | CP e aceite |
|---|---|---|---|---|---|
| CS01 Visão Geral — §15.1 | Carteira, MRR/ARR, saúde, riscos, satisfação, renovação, expansão, agenda, insights reais | DashboardController `:2`, Presenter `:64`, ReportMetrics `:5`, HealthInsights; `ModulePage.vue`/MetricsPanel/NicoSummaryPanel | IMPLEMENTADO_PARCIAL | Há dados derivados de contratos e origens autorizadas; motor compartilhado, taxa de resposta completa e pesquisas multicanal não prontos | CP1/8: reconciliar cards, drilldowns e dados sem fontes, sob mesmo escopo |
| CS02 Carteira — §4/6/15.2 | Empresa mestre, múltiplos contratos/produtos, CS, receita, saúde, próximo contato; elegibilidade por contrato+produto ativo com exceções autorizadas | Assignment; PortfolioController `:2/:23/:40`; CustomerSignals `:10`; Presenter `:6`; PortfolioTable; Eligibility `:8` | IMPLEMENTADO_PARCIAL | Handoff depende de pedido qualificável, assinatura quando obrigatória e go-live. Não é a elegibilidade padrão contrato ativo+produto ativo do Word. Criação manual não exige exceção formal registrada; um owner por Assignment | CP1/2: demonstrar padrão e exceções sem criar outra empresa nem ampliar escopo |
| CS03 Central de Ações — §8/15.3 | Hoje, vencidas, futuras, aguardando cliente/financeiro, responsável, origem, prioridade, SLA, pausa e Agenda | Action `:2`, Workflow `:22/:122`, OperationalRouting/SlaClock, RecordsController `:2/:71`, ActionSources, SlaSummary | IMPLEMENTADO_PARCIAL | Fluxo amplo já existe; completar correlação de pesquisas por resposta/efeito e eventos novos. Job atual não prova metas de reação do catálogo NICO | CP4: preservar pausa/retomada, conclusão e Agenda; efeito único em retries |
| CS04 Saúde — §7/20/15.4 | Fatores explicáveis, pesos ativos=100, ausência configurável, snapshots imutáveis, faixas e histórico | Configuration `:16/:43`; HealthScore `:11`; Processor `:8`; HealthSnapshot; HealthScorePanel/CustomerPanel; PortfolioController `:9` | CONFLITO_DOCUMENTO_CODIGO | Pesos aceitam qualquer soma positiva, não exatamente 100. HealthScore renormaliza ausência sempre, sem política neutro/bloquear. Config só conta/segmento/produto. Snapshot não possui readonly guard como ConfigurationVersion; sem API de update, mas imutabilidade não está garantida no modelo | CP3: validar soma e política explícita; histórico não mutável; separar alteração de configuração de variação real |
| CS05 Riscos e Retenção — §8/15.5 | Evidência, severidade, MRR em risco, dono, plano, prazo, resultado e efeitos idempotentes | RiskCase `:3`; Workflow `:256` projeta ação/Agenda; Processor `:131`; Presenter `:26`; SignalJob cria risco de cancelamento; plano/concessão tem aprovação de gestor | IMPLEMENTADO_PARCIAL | MRR exibido vem de snapshot, não um valor/fatia congelado no caso. Detrator é agregado nos últimos 90 dias e dedupe por kind/data, não por resposta/efeito. Correlação R10/R15 ainda ausente | CP4/5/13: manter evidência e origem; exatamente um risco/ação por efeito lógico |
| CS06 Planos de Sucesso — §9/15.6 | Empresa+contrato+produto, metas/marcos, responsáveis, prazos, progresso, tarefas/evidências | SuccessPlan `:2`, Workflow `:171` valida tasks/activities/tickets/QBR/products no escopo; RecordEditor, WorkContext `:8` | IMPLEMENTADO_PARCIAL | Entidade tem Assignment+Project, não contract_id/product_id de origem; produto só opcional nas metas. Precisa vínculo contratual e de produto autorizado. Tarefas nativas referenciadas e marcos já existem | CP6: projeto/tarefas reaproveitados; vínculos autorizados e progresso consistente |
| CS07 QBR/Reuniões — §10/15.7 | Contexto executivo, pauta, participantes, convite, agenda, URL/gravação, ata NICO, decisões/tarefas | Qbr `:2`; WorkContext `:8`; Workflow `:213/:243` sincroniza Agenda e compromissos; RecordEditor; NICO qbr task | IMPLEMENTADO_PARCIAL | Qbr/strong params não têm meeting_url/recording_url/provider. Sem convite/calendar API; ata é summary e NICO gera apoio de contexto. Existe videoconferência externa por usuário para reaproveitar | CP6: link externo real e autorizado, decisões→Agenda idempotentes; API de provider só após dependências |
| CS08 Renovações — §11/15.8 | Casos dos contratos; janelas configuráveis 120/90/60/30/15; retorno por pedido/aditivo/contrato | Renewal `:3`, Processor `:69/:121`, Workflow `:138`, RenewalWindow `:2`, RenewalPipeline e Presenter `:47` | IMPLEMENTADO_PARCIAL | Janelas exclusivas estão hardcoded no `WINDOWS`; horizonte renewal_days é configurável. Reconciliador reconhece contrato assinado com source_contract_id, mas restante do macrofluxo exige regressão | CP7: não confirmar ganho só pelo deal; provar pedido/aditivo/contrato e carteira atualizada |
| CS09 Expansão — §12/15.9 | Sinal origem contrato/produto, produto sugerido, potencial, razão/CS; CRM vende, ganho retorna | ExpansionSignal `:2`, Workflow `:138` cria deal nativo+metadata+produto com lock, Processor `:152`, ExpansionPipeline `:2`, Presenter `:32` | IMPLEMENTADO_PARCIAL | product_id é sugerido; modelo não tem contrato/produto de origem explícitos. Metadata do deal usa try(contract_id) e fica sem contrato para ExpansionSignal. Win financeiro aparece, mas retorno completo ao contrato precisa teste. Sugestão automática é primeiro produto ativo não usado, sem evidência comercial específica | CP7: sinal preserva origem e produto; ganho só por fluxo nativo de pedido/contrato |
| CS10 Pesquisas/Satisfação — §13/15.10/19/25–32 | NPS/CSAT/CES/custom, resposta, origem/canal/agente/equipe, taxa e recuperação | Survey `:4` nps/ces; CSAT nativo; Presenter `:42`, ReportMetrics `:13`; ModulePage surveys, SurveyDeliveryPanel, public controller | IMPLEMENTADO_PARCIAL | Instância relacional não guarda contact/source ticket/conversation/call/QBR, agente/equipe/contrato/produto; sent_conversation_id só quando manualmente entregue. Custom/admin e motor compartilhado ausentes | CP5: matriz detalhada abaixo; origem+ciclo+regra+versão e resposta vinculados |
| CS11 Playbooks — §14/15.11 | Onboarding/risco/renovação/detrator/pós-atendimento, escopo, versão, prévia, métricas e integração Flows | Playbook `:4`, PlaybookConditions, PlaybookSteps `:3`, Playbooks `:6`; ConfigurationController `:33/:37`; UI real em ModulePage | IMPLEMENTADO_PARCIAL | CRUD/auditoria e etapas finitas existentes; não há versão imutável/execution separado, prévia/simulação completa, etapas de canal/pesquisa ou integração Flows. Idempotência usa book id/step key/source e não versão | CP8: ampliar os pontos existentes sem executor paralelo; preservar execuções históricas |
| CS12 Relatórios — §15.12/21 | Filtros, tendências/histórico, export sob autorização da tela | DashboardController `:41/:63`, BaseController `:38/:94`, ReportMetrics, RevenueMetrics, TeamMetrics, MetricDrilldown; filtros UI | IMPLEMENTADO_PARCIAL | Export carteira/histórico já aplica escopo e CSV evita fórmula; falta motor para métricas completas de pesquisa e segmentação de resposta. Não atestar uso atual sem executar suites | CP8: igualdade de filtros cards/rows/export, ausente≠zero, autorização negativa |
| CS13 Configurações — §15.13/20/21 | Pesos, limites, pesquisa/handoff, prioridades, integrações/permissões, overrides/versionamento | Configuration `:13`; ConfigurationVersion `:12` readonly; ConfigurationController `:14` lock, optimistic version, auditoria; ConfigurationPanel/OperationsSettingsPanel | IMPLEMENTADO_PARCIAL | Escopos só conta/segmento/produto; faltam empresa/unidade, regras pesquisa, integrações e política de ausência. Renovação/expiração de pesquisa ainda rígidas | CP1/3/5/8: RBAC backend, herança explícita, versão preservada, sem ativação automática |
| CS14 Handoff — §5/15.14/16.1 | Checklist herdado, pendências/promessas/anexos, responsável/CS, validar, aceitar/rejeitar, auditar e iniciar plano/playbook | Handoff `:2`, Eligibility `:8`, Backfill `:8`, SignalJob; Assignment + onboarding action; aceita go-live existente | IMPLEMENTADO_PARCIAL | Não há entidade handoff, estados aceite/rejeição, checklist ou tela dedicada. Dados não são pacote de transição com aceite; atribuição automatizada ao owner do pedido | CP2: reaproveitar fontes e registrar transição/decisão, sem sobrescrever identidade/owner |
| CS15 Cliente 360 — §15.15/16.2 | Agregação única, origem financeira/CS, pesquisas/riscos/planos/reuniões/timeline e ações rápidas | Customer360 `:4/:142/:149`; Customer360Relationship; CustomerPanel `:1` e `:473`; Presenter assignment customer_360; Company detail integra componente | IMPLEMENTADO_PARCIAL | Contexto nativo amplo. Adicionar vínculos detalhados novos e handoff/pesquisa normalizados. CS usa abas/atalhos existentes; não precisa outro cadastro/portal | CP2: mesmas permissões nas origens, busca, timeline, NICO e ações rápidas |
| CS16 Configuração Pós-Atendimento — §15.16/16.3/25 | Canal ON/OFF, modelo, atraso/frequência/expiração/reenvio, fallback autorizado, exceções/SLA, testar/versionar | CSAT inbox config, Configuration regras pergunta/frequência; CsatSurveyService `:38/:46`; ConfigurationPanel | ESTRUTURA_EXISTENTE | Não há tela ou política compartilhada com essas dimensões; frequência positiva global exclui sempre; sem atraso/expiração/reenvio configuráveis | CP5/13: cada encerramento é avaliado, não força envio, OFF deixa decisão auditada |
| CS17 Caixa de Respostas — §15.17/16.4 | Nota/comentário, origem/agente/equipe/contrato/produto, risco/ação, responsável e marcar tratado | ModulePage `:1369` mostra nota/comentário/canal/data/expiração; ReportMetrics CSAT e NPS; surveys list filtro responded | ESTRUTURA_EXISTENTE | Área surveys não é caixa de tratamento completa; faltam classificação persistida, causa/status tratado, origem e ações vinculadas por resposta; API permite PATCH do kind mesmo após resposta | CP5: histórico imutável do enviado, abrir origem/risco/ação, registrar tratamento |
| CS18 Integrações de Reunião — §15.18/16.5 | Teams/Graph, Meet/Calendar, Zoom, externo; status real, conta, scopes, autorização, teste/desconectar | VideoConferenceSetting `:24` URLs HTTPS externas/password encrypted por account+user; API video_conference_settings existente `:12`; QBR sem vinculação | BLOQUEADO_DEPENDENCIA | URLs externas existem fora do fluxo QBR. Não foram encontrados adaptadores Graph/Meet/Zoom de reunião/Calendar ligados ao CS. APIs/docs/credenciais/provas externas necessárias; UI deve expor indisponibilidade e não alegar connected | CP6/8: fluxo URL externo e autorizado independente; provider apenas depois de teste concreto |

## Matriz do motor compartilhado de pesquisas

Não criar outro motor paralelo. Expandir as instâncias existentes e absorver a avaliação do CSAT nativo preservando os canais/provider/templates e as respostas atuais.

| ID / fonte | Evidência atual | Status / lacuna | Dependência e aceite CP5/13 |
|---|---|---|---|
| S01 Evento encerramento normalizado — §18/28/32 | CsatSurveyListener `:2` em conversa resolved; SignalJob tickets/projetos/Agenda/Survey | IMPLEMENTADO_PARCIAL: não há interaction.closed compartilhado para conversa, ligação, ticket, reunião e manual; ticket fechado crítico cria follow-up, não pesquisa | Normalizar origem/ciclo/contexto sem copiar entidades; cada encerramento elegível avaliado |
| S02 Modelos — §26.1/26.2/27 | Survey kind nps/ces, perguntas em Configuration; CSAT inbox config separado | NAO_IMPLEMENTADO: não há survey_definitions/modelos versionados custom ou CRUD/duplicar/ativar/arquivar/consultar uso | Estender motor/entidade compartilhada, quatro tipos, histórico antes/depois/RBAC |
| S03 Perguntas/opções/condições — §26.4/26.5/27 | Uma pergunta em metadata e score 0–10; CSAT escala nativa 1–5 | NAO_IMPLEMENTADO: menus, ordem, labels, required, conditional e múltiplas respostas não existentes | Versão enviada deve conter texto/escala/opções completos; lógica condicional validada backend |
| S04 Regras/hierarquia — §25.2/26.3 | Configuration escopo conta/segmento/produto; CSAT por inbox e label rules | NAO_IMPLEMENTADO para pesquisa: tipo/canal→fila/equipe→produto→empresa/unidade→conta; prioridade+versão; vigência; ON/OFF independente | Persistir regra e motivo; herança e desempate determinísticos e testados |
| S05 Avaliação/no-send audit — §25.2/27/28 | CSAT returns silenciosos; JrcRelationship audit survey_sent/responded | NAO_IMPLEMENTADO: dispatch_decisions de não envio não existem; sem pipeline estado e timestamps completos | Toda avaliação persiste elegível/não elegível e motivo, inclusive regra inexistente e canal OFF |
| S06 Frequência — §19/25.3 | Workflow `:201`, PortfolioController `:134`: frequência assignment+kind; config 90 dias e valor positivo | IMPLEMENTADO_PARCIAL: não suporta sempre/0, escopo contact/company/contact+type, horário/fuso diário e janelas por regra/version; lock existe na Assignment para criação manual | Nunca duplicar origem/ciclo; frequência correta entre origens/canais e concorrência |
| S07 Atraso/expiração/reenvio — §19/25.3/28 | Workflow `:208` expiração 30 dias fixa; sem SurveyDeliveryJob | NAO_IMPLEMENTADO para política genérica: agenda/delay/retry/dead-letter/reminder/version configuráveis | Sem novo envio real nesta rodada; simulação e jobs rastreáveis com testes de relógio |
| S08 Canais/provider — §25.1/26.1/26.3 | SurveyDelivery `:6`: WhatsApp/e-mail e can_reply; CSAT templates aprovados Twilio/WA existentes | IMPLEMENTADO_PARCIAL: sem canal alternativo autorizado, voz/SMS/manual/QBR/SD compartilhados; send records só mensagem construída | Reaproveitar provider/capacidades/templates; canal inválido mostra motivo e não falso sucesso |
| S09 Consentimento/bloqueios — §19/25.3 | can_reply e native inbox rules | IMPLEMENTADO_PARCIAL: sem checagem genérica de consentimento para instância de pesquisa ou exceções fila/teste/curto/bloqueio no SurveyDelivery | Resolver política/contexto antes do envio; testes negativos para consentimento e provider indisponível |
| S10 Pipeline/entregabilidade — §19/28 | Presenter delivery_status responded/expired/awaiting; metadata sent_message_id/sent_at; CSAT Message provider source_id | NAO_IMPLEMENTADO para instância: elegibilidade/política/scheduled/sent/delivered/failed/unknown não vinculados por versão; awaiting pode representar nunca enviada | Estado da instância deve vir do provider/Message e histórico, não presumir delivered ao construir Message |
| S11 Idempotência e concorrência — §19/28/30 | SurveyDelivery locks survey e devolve sent_message_id; creation locks Assignment; token único | IMPLEMENTADO_PARCIAL: sem chave origem+ciclo+regra+versão; Survey não tem source_key e não usa request_id para dedupe. Lock/frequência de manual não equivale a idempotência de encerramento | Índice/lock e efeito por chave lógica; conflitos/retries/concurrent close sem segunda instância |
| S12 Origem e rastreabilidade — §13/16.4/19/27 | Survey tem Assignment/owner; manual delivery metadata conversation; CSAT conversa/contact/assigned_agent nativos | IMPLEMENTADO_PARCIAL: Survey schema sem source/contact/team/contract/product; resultado não abre todos os atendimentos de origem | Reusar IDs nativos autorizados e snapshot do enviado; fonte abre resposta e vice-versa |
| S13 Resposta e versão imutável — §26.5/27/30 | RelationshipSurveysController `:14` with_lock impede segunda resposta; pergunta copiada no prepare_survey | IMPLEMENTADO_PARCIAL: sem rule_version/survey_version/pergunta id; Workflow FIELDS permite mudar kind via PATCH inclusive após responder; resposta não é um conjunto imutável de answers | Campo semântico usado não muda; nova versão para mudanças; arquivo histórico, nunca delete destrutivo |
| S14 Classificação/efeitos — §13/26.6 | CustomerSignals calcula NPS 0–6/7–8/9–10 e CSAT/ces thresholds; Processor satisfaction cria risk/action | IMPLEMENTADO_PARCIAL: classificação não persistida na resposta; efeitos agregados pelo período/kind/data, não response/effect; não aplica SLA detractor_sla_hours explicitamente no fluxo; sem promotor/neutro/no-response automações configuradas | Efeitos uma vez; diferenciar NPS, CSAT e CES; regra/version/limiar e correlação R10/R15 auditados |
| S15 Administração/auditoria — §26.1/29 | Configure policy; ConfigurationVersion readonly; auditoria JrcCustomers Audit; operações existentes | ESTRUTURA_EXISTENTE: faltam 6 abas admin e RBAC do motor, entidade versions/answers/archive e reativação controlada | Conta/unidade/referências verificadas no backend e jobs; auditor read-only e CS sem mutation admin |
| S16 Métricas/E2E — §30/32 | ReportMetrics/MetricDrilldown agregam NPS, native CSAT, CES; testes existentes da frequência/nota/escopo | IMPLEMENTADO_PARCIAL: denominadores eligible/sent/responded e response rate completo ausentes; sem E2E multicanal ON/OFF/version/falha encontrado nesta família | Suítes de ON/OFF, herança, versão, concorrência, origem, detrator e provider falho; dado ausente explícito |

Busca literal por `survey_definitions`, `survey_trigger_rules`, `survey_dispatch_decisions`, `survey_answers`, `survey_questions`, `survey_options`, `survey_rule_versions`, `survey_audit_logs` em `app enterprise config db spec` não encontrou implementação. A ausência usa também os schemas/rotas/classes efetivamente lidos, não apenas esses nomes sugeridos pelo Word.

## Riscos objetivos e continuidade

1. **Soma dos pesos**: `Configuration.valid_config` só exige soma positiva. Uma alteração de configuração hoje pode violar §20 mantendo cálculo aparente válido. CP3 precisa teste negativo de soma !=100 e migração/compatibilidade de configurações reais existentes, sem modificar dados operacionais nesta rodada.
2. **Ausência de fatores**: `HealthScore.call` renormaliza automaticamente. Tornar decisão configurável e versionada; default legado precisa ser explicitamente documentado. Não fabricar telemetria. `AdoptionMetric` usa metas do plano, não telemetry provider; `unavailable` já informa ausência de telemetria.
3. **Histórico**: ConfigurationVersion já usa readonly e deve ser mantido; HealthSnapshot tem fingerprint e insert-only no Processor, porém modelo não impede alterações persistidas. Survey usada pode ter kind alterado via API, alterando interpretação retrospectiva. Priorizar guardas e testes pertinentes.
4. **Elegibilidade/handoff**: contrato+produto ativo versus pedido+go-live do legado deve virar política explícita com defaults e exceções, sem apagar o fluxo existente ou cadastrar empresa CS paralela.
5. **Reincidência CS**: `CustomerSignals.recurring_tickets` conta todos os tickets recentes do cliente. Isso pode ser sinal amplo de suporte, mas **não implementa R01–R04** do catálogo NICO (defeito/serviço/ativo, cliente canônico, anterior aberto, clientes distintos/janelas). Não atribuir cobertura de R01–R04 a esse contador.
6. **Saúde por produto**: maioria dos fatores usa o contexto compartilhado da empresa; UI possui aviso SHARED_PRODUCT_FACTORS. Não apresentar esses fatores como telemetria individual de cada produto.
7. **Satisfação e cobertura**: frequência atual 90 dias não corresponde a políticas canal do Word; KPI histórico 20% do Excel não autoriza mudar a regra para amostragem. Corte <=6 vale NPS; CSAT atual 1–5 e CES usa escala descrita pela configuração.
8. **URL externa**: VideoConferenceSetting é cadastro funcional de URLs por usuário, sem criação de reuniões no provider. Reaproveitar, mas vinculação QBR precisa ação/campo real; provider fica BLOQUEADO_DEPENDENCIA até API/credenciais/prova.
9. **Sem ativação**: Read-only CP0 não enviou mensagens, não rodou backfill, não enfileirou jobs, não alterou flags nem configurações. Os automatismos existentes ficam como estavam na base.

## Testes encontrados e validação pendente

Família existente: quatro suites de serviço, duas request e seis JS (12 arquivos). Não executados neste CP0 para preservar o pedido de auditoria somente leitura. Não há resultados de aprovação/falha novos nem comprovação de `document_rules` preexistente por este agente.

- `spec/services/jrc_relationship/lifecycle_spec.rb`: identidade única/handoff, saúde/risco, ticket, resposta NPS, renovação, expansão CRM, cancelamento, QBR, fatura, retenção, revogação de acesso, frequência e stale edits.
- `spec/services/jrc_relationship/functional_review_spec.rb`: diagnóstico/backfill, go-live/assinatura, auto_handoff OFF, histórico, queda saúde, risco, planos, QBR e referência de outra conta.
- `spec/services/jrc_relationship/complementary_review_spec.rb`: onboarding idempotente, contexto não mutável/read-only, crescimento/expansão, pergunta preservada/frequência, compromisso QBR retirado e prioridade manual.
- `spec/services/jrc_relationship/operations_spec.rb`: pause/resume com Agenda, routing/unidade, políticas SLA preservadas, alertas idempotentes e waiting_finance.
- `spec/requests/api/v1/accounts/relationship/access_spec.rb`: carteira própria, cards/rows/drilldowns, negação detalhe/write, export histórico restrito, bulk rollback e NPS sem conta estrangeira.
- `spec/requests/api/v1/accounts/relationship/operations_configuration_spec.rb`: queues/SLA audit/tenant e versões health/risk reasons.
- JS: `api.spec.js`, `interface.spec.js`, `operations.spec.js`, `functionalReview.spec.js`, `complementaryReview.spec.js`, `reconciliation.spec.js`. Cobrem contexto explícito, permissões/troca de conta/usuário, UI/Agenda/risco/config/CSAT nativo/envio manual e janelas.
- Há suites nativas `spec/services/csat_survey_service_spec.rb`, `spec/listeners/csat_survey_listener_spec.rb`, `spec/models/csat_survey_response_spec.rb` e testes do Cadastro Mestre/Customer360. Devem entrar na regressão do motor compartilhado.
- Novos testes necessários: soma 100/política ausência/imutabilidade; handoff aceite-rejeição; contrato/produto e objeto oculto; motor ON/OFF, hierarchy/version/frequência/concorrência/retry/unknown provider; detrator por efeito único; tratamento e origem; URL externa em QBR; retorno CRM por contrato/pedido.

Comandos sugeridos para fase de validação autorizada, em ambiente de teste exclusivo configurado pelo agente principal:

```text
bundle exec rspec spec/services/jrc_relationship spec/requests/api/v1/accounts/relationship spec/services/csat_survey_service_spec.rb spec/listeners/csat_survey_listener_spec.rb
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/jrcRelationship
git diff --check
```

Não foram feitas mudanças neste checkout para permitir esses comandos. Repositório tem overlay Enterprise; buscas incluíram `enterprise/` e não localizaram módulo CS alternativo ou motor genérico equivalente. Native CSAT tem overlay de policies/controllers/reports que deve ser preservado na implementação.

## Próxima ação exata

No worktree da nova tarefa, consolidar esta matriz com as outras fontes em CP0. CP1/2 preservam fundação e completam política de elegibilidade, aceite de handoff e vínculos. CP3 corrige governança objetiva de pesos/ausência/histórico; CP5 concentra o maior acréscimo (motor compartilhado, modelo/pergunta/regra/version/decisão/entrega/resposta). Não declarar CP5 concluído só com modelos/rotas ou mock de provider. CP6 pode completar URL externa e tarefas QBR independentemente das APIs de reunião. CP7/8 exigem testes de retorno e herança/versionamento dos fluxos existentes.

```text
AUDIT_STATUS=CP0_SOMENTE_LEITURA_CONCLUIDO
IMPLEMENTACAO_STATUS=NAO_EXECUTADA_POR_ESTE_AGENTE
VALIDACAO_LOCAL_STATUS=LEITURA_ESTRUTURAL; SUITES_NAO_EXECUTADAS
ATIVACAO_EM_CLIENTES_REAIS=NAO
MIGRATIONS_EXECUTED_ON_SERVER=NAO
COMMIT_EXECUTED=NAO
PUSH_EXECUTED=NAO
IMAGE_PUBLISHED=NAO
DEPLOY_EXECUTED=NAO
```


---

# Auditoria CP0 do Service Desk V2

O SHA aprovado contém uma base de Service Desk com criação idempotente, consultas autorizadas, cadastro operacional, notas internas e ciclo de vida versionado. O alvo V2 ainda tem lacunas de produto relevantes: os quatro níveis de visibilidade não existem, o cockpit não reúne as interações, há telas planejadas sem operação e faltam mensagens/notificações próprias do chamado, tarefas, aprovações, incidentes, portal de tickets, distribuição e claim-next. A presença de serviços e specs foi tratada como implementação parcial, sem afirmar homologação ou testes aprovados nesta auditoria.

## Escopo e fonte lida

- Repositório consultado: `https://github.com/ClaudioHideki/jrc-conversas-lab2.git`.
- Checkout somente leitura: `C:/Users/DEV03/Documents/Jrc/ia-provedor-unico-20261007`.
- Branch consultada: `codex/ia-provedor-unico-20261007`.
- HEAD: `4ce8241d35ce862e9d53e9a5dce4df9a1858432c`, exatamente a base aprovada.
- `git status --porcelain=v1`: vazio. `git diff --check`: saída vazia e código 0.
- Instruções lidas: `AGENTS.md` e todas as 1.261 linhas do prompt `C:/Users/DEV03/.codex/attachments/a1653d0b-2d80-4a95-a934-6c23d0960ebc/Texto colado.txt`.
- DOCX efetivo: `C:/Users/DEV03/Downloads/JRC_Conversas_Service_Desk_Projeto_Completo_DEV_2026_V2_VISIBILIDADE.docx`.
- SHA256 do DOCX: `8F09EB1EA9809ED3480950AD2C83E00E918A90CF9F2AC6F2458F80F312E8D640`.
- Extração integral OOXML, com ordem de parágrafos/tabelas, cabeçalho e rodapé, usando Python bundled. Texto: `servicedesk-source.txt`, 343 linhas, 22.958 caracteres. As tabelas foram lidas, inclusive modelo mínimo, níveis de visibilidade e P0-01–P0-12.
- A fonte tem nome V2_VISIBILIDADE, mas o corpo diz `Versão 1.0 • 07/10/2026`. Registrar esse fato editorial; o conteúdo adicional 6.1–6.7 foi efetivamente considerado. Não substituí por outra versão.
- A skill documents foi lida e aplicada somente à extração. Não houve criação/alteração de DOCX nem análise de layout; não foi necessário renderizar.

Todos os caminhos de código abaixo são relativos ao checkout de leitura informado. As linhas foram consultadas nesse HEAD. Nenhum arquivo desse checkout foi alterado; nenhuma mutação Git, dado, migration, comunicação, publicação, ativação ou deploy foi realizada.

## Matriz das 13 entradas oficiais

| ID e área | Fonte e comportamento esperado | Situação | Implementação e evidência | Lacuna e dependência | CP e aceite |
|---|---|---|---|---|---|
| SD-01 Visão geral | Word §§2,16: KPIs operacionais, SLA, capacidade, satisfação e tendências reais e autorizadas | IMPLEMENTADO_PARCIAL | `routeDefinitions.js:3`; `app/services/jrc_service_desk/dashboard_service.rb:9` usa TicketQuery autorizado e SQL agrupado | O próprio retorno declara indisponíveis `sla_breached csat time_series capacity` em `dashboard_service.rb:17`; relatórios completos não existem | CP12/16: reconciliar métricas/totais com listas autorizadas, sem dados fictícios, com janelas e denominadores |
| SD-02 Chamados | Word §§3,4,19: lista/filtros/detail e mutações reais | IMPLEMENTADO_PARCIAL | `config/routes.rb:86`; `tickets_controller.rb:4`; `ticket_query.rb:16` intersecta policy scope; TicketDetail/TicketForm reais | Detalhe ainda parcial; sem timeline 360 e campos avançados. Número apresentado é ID backend (`app/serializers/jrc_service_desk/presenter.rb:24`), sem formato SD separado | CP9/16: criar, reler, filtrar e atender sob autorização negativa e positiva |
| SD-03 Minha fila | Word §§2,4,8: trabalho do agente e elegíveis para assumir | IMPLEMENTADO_PARCIAL | `routeDefinitions.js:5`; `ticket_query.rb:51` filtra atribuição por memberships ativos | Mostra atribuídos; não implementa fila de disponíveis com elegibilidade completa nem claim-next | CP12: outro agente/unidade não consegue capturar; concorrência concede cada ticket uma vez |
| SD-04 Novo chamado | Word §§3,4,19: wizard, classificação/revisão, persistência/número/aviso | IMPLEMENTADO_PARCIAL | `TicketFormView.vue:43` steps; `TicketFormView.vue:163` escrita; `create_ticket_workflow_service.rb:10` transação; `create_ticket_service.rb:30` replay | Upload é PendingAction (`TicketFormView.vue:268`); sem notificação de criação nem SLA automático comprovado de contrato/serviço; não há subcategoria/tipo explícitos no FIELDS (`create_ticket_service.rb:4`) | CP9–12: retry/concorrência não duplicam ticket; número somente após releitura; todos os dados e vínculos persistem |
| SD-05 Filas e equipes | Word §§2,8: canais, modos, capacidade, skills e escopo | IMPLEMENTADO_PARCIAL | `routeDefinitions.js:9`; Queue vincula Team nativo (`app/models/jrc_service_desk/queue.rb:5`); configuration aceita name/code/active/team em `configuration_contract.rb:6` | Não há configuração SD de distribution_mode, capacidade, disponibilidade ou skills. Modos de Conversas/Projetos existentes não provam distribuição de tickets | CP12: manual/round-robin/menor carga/skills/prioridade-SLA em backend com mesmas ACLs |
| SD-06 Responsáveis | Word §§2,4,8,16: agentes/permissões/carga/disponibilidade | IMPLEMENTADO_PARCIAL | `routeDefinitions.js:10`; `catalog_query.rb:74` membros ativos da unidade e `catalog_query.rb:37` tickets_view; `base_service.rb:76` revalida alvo na mutação | Listagem/atribuição existem; carga ponderada, online/pausado, capacidade e produtividade SD não existem | CP12: seleção/mutação exige equipe/skill/disponibilidade/capacidade conforme política, além do grant |
| SD-07 Aprovações | Word §10: solicitante, aprovador/papel, prazo, decisão/comentário, evidência | ESTRUTURA_EXISTENTE | `routeDefinitions.js:14` aponta `page: 'planned'`; `PlannedView.vue:30` PendingAction e `:73` pending | Não há TicketApproval, endpoint ou workflow SD. A aprovação NICO genérica existente não substitui aprovação do chamado | CP11: solicitar/decidir/devolver/recusar com prazos, payload/escopo e auditoria |
| SD-08 Problemas/Incidentes | Word §11: principal/filhos, impacto, causa, workaround, massa/recorrência | ESTRUTURA_EXISTENTE | `routeDefinitions.js:15` planned e `PlannedView.vue:73` | Nenhum model/service/rota de incidente SD localizado; não há vínculo principal/filhos ou atualização em massa | CP11/15C: vínculos Account/Unit/cliente autorizados; massa com clientes distintos e comunicação controlada |
| SD-09 Catálogo de serviços | Word §12: formulário/regras/SLA/prioridade/fila/aprovação/visibilidade/portal | IMPLEMENTADO_PARCIAL | `app/models/jrc_service_desk/service.rb:4` NamedUnitRecord; configuration services (`config/routes.rb:72`); service_definitions (`:80`); Ticket.service (`ticket.rb:15`) | Identidade mínima e associação; tela oficial catálogo segue planned (`routeDefinitions.js:12`). Configuration só name/code/active (`configuration_contract.rb:8`); sem formulário/contrato/visibilidade/padrões de roteamento/aprovação | CP11/12: serviço autorizado define campos e requisitos reais, sem duplicar produto/contrato mestre |
| SD-10 Base de conhecimento | Word §§13,14: busca contextual, sugestão/artigo por resolução | ESTRUTURA_EXISTENTE | `routeDefinitions.js:13` planned; infraestrutura nativa Portal/Article existe (`app/models/portal.rb:36`, `public/api/v1/portals/articles_controller.rb:13`) | Não há integração contextual SD artigo/categoria/título/descrição nem resolução→artigo confirmada | CP9/11: reutilizar Help Center/NICO sob autorização, sem anunciar conexão fictícia |
| SD-11 Automações | Word §§6,7,9,21: regras/eventos/ações/escalonamentos administráveis | ESTRUTURA_EXISTENTE | `routeDefinitions.js:19` planned. LifecyclePolicy não é executor de automações de eventos | Não há motor SD de notificações/SLA limiares/lembretes/pesquisa/detrator. Reutilizar Flows/executor/jobs existentes | CP12/13/15: política versionada e execução observável/idempotente, permanecendo desativada para clientes reais |
| SD-12 Relatórios | Word §16: backlog, tempos, SLA, FCR/reabertura, canal/categoria/serviço/cliente/unidade, CSAT/NPS/CES, export | ESTRUTURA_EXISTENTE | `routeDefinitions.js:21` planned; export é PendingAction (`PlannedView.vue:35`) | Dashboard tem somente subconjunto. Sem export SD e cockpit supervisor completos, unidades/denominadores de qualidade e séries históricas | CP12/13/16: tela, export e IA têm mesmo escopo e nível de conteúdo; sem data atual copiada da planilha |
| SD-13 Configurações | Word §17: status, prioridades/impacto-urgência, categorias, filas/skills/capacidade, serviços, SLA/OLA/calendários, templates, automações, ACL/campos/retenção | IMPLEMENTADO_PARCIAL | `routeDefinitions.js:22`; `config/routes.rb:60` estrutura, `:72` configuration, `:79` lifecycle policies; `configuration_contract.rb:5` conjunto finito; Capabilities nativas (`capabilities.rb:7`) | Cadastros básicos e versões lifecycle existem. Faltam templates/notificações, matriz impacto-urgência, subcategoria/tipo, skills/capacidade, catálogo completo, OLA/campos/retenção/visibilidade | CP10–12: administração segregada da operação; versões históricas preservadas e sem default de unidade |

Nas evidências frontend da tabela, prefixo completo: `app/javascript/dashboard/routes/dashboard/serviceDesk/`. Nas evidências controller: `app/controllers/api/v1/accounts/jrc_service_desk/`. Nas evidências service/model sem prefixo, usar respectivamente `app/services/jrc_service_desk/` e `app/models/jrc_service_desk/`.

## Cockpit P0 e fluxo operacional

| ID | Fonte e requisito | Estado e evidência | Lacuna e critério de aceite |
|---|---|---|---|
| SD-P0-H | Word §5: cabeçalho permanente com número, título, prioridade/status, fila/equipe, responsável e relógio SLA | IMPLEMENTADO_PARCIAL. `TicketDetailView.vue:43` cabeçalho só título/número e edição; resumo lateral em `:101`. `presenter.rb:143` retorna prazos backend | Reorganizar cabeçalho persistente usando dados existentes, diferenciar SLA calculado/pausado/indisponível. Responsividade validada na mesma viewport e menor |
| SD-P0-T | Word §5: timeline única de mensagens, notas, anexos, chamadas, tarefas, atribuições/transferências/aprovações/automações/auditoria | IMPLEMENTADO_PARCIAL. Tabs segregadas em `TicketDetailView.vue:27`; `RelatedRecordsQuery::KINDS` só notes/events/sla/conversations/status_options (`related_records_query.rb:4`); tipos de eventos finitos (`ticket_event.rb:6`) | Projeção 360 com paginação e origem, preservando logs; incluir somente objetos autorizados e visibilidade conforme backend, sem copiar conteúdos de conversa |
| SD-P0-C | Word §5,6.2: composer omnichannel e seletor/preview de visibilidade | NAO_IMPLEMENTADO. Tab conversation mostra PendingAction (`TicketDetailView.vue:97`); nota com body e texto interno (`TicketActivity.vue:57`, `:95`) | Integrar envio nativo por canal elegível, identidade/destinatário, selector antes do envio e canal ausente desabilitado com motivo |
| SD-P0-X | Word §5: contexto cliente/solicitante/contrato-serviço/empresa-unidade/categoria-origem-SLA-tags-campos | IMPLEMENTADO_PARCIAL. `TicketDetailView.vue:90` CustomerContextPanel; `customer_context_service.rb:11` autorização SD+Contact+Directory; `Ticket` referencia Service/Company | Não há painel completo de contatos/contrato/tags/campos/subcategoria/tipo. Empresa cliente canônica preservada; operadora vem da Unit |
| SD-P0-A | Word §5: assumir, transferir/escalar, status/prioridade, tarefa/aprovação/incidente, resolver/reabrir/fechar | IMPLEMENTADO_PARCIAL. `TicketOperations.vue:49` assignment/transfer/priority/work_status; LifecyclePanel e `lifecycle_transition_service.rb:29` regras específicas | Assumir próprio/claim-next dedicado e escalar precisam política; tarefa/aprovação/incidente ausentes. Resolver/fechar/reabrir existentes dependem de política publicada/versão e snapshot válido |
| SD-P0-N | Word §5,13: NICO resumo/resposta/artigos/classificação/sentimento/risco SLA/escalonamento | IMPLEMENTADO_PARCIAL. NICO chama serviços SD em `app/services/jrc_nico/domain_actions.rb:134`–`:216`, com TicketPolicy/DomainAccess | É integração de comandos/leitura, não copiloto contextual completo do cockpit. Implementar sugestões permitidas sobre projeção de visibilidade, sem executar efeitos só por sugestão LLM |
| SD-FLOW | Word §3,4: entrada→dados→classificação→revisão→persistência/número→notificação→fila→atendimento/tarefas→resolução→comunicação→pesquisa→fechamento | IMPLEMENTADO_PARCIAL. Wizard/cadastro/mutações/lifecycle existem. Escrita Vue relê servidor (`helpers/operationalSession.js:83`) e valida campos (`:86`) | Upload/notificação, comunicação pública, tarefas e motor compartilhado de pesquisa no encerramento não completam o fluxo. Não exibir sucesso operacional baseado só no ack |
| SD-IDEM | Word §19 e prompt §7: mesma intenção/retry/concorrência produz um ticket | IMPLEMENTADO_PARCIAL sem execução nesta rodada. `ticket.rb:31` key scoped + fingerprint; `base_service.rb:34` lock Unit; `create_ticket_workflow_service.rb:17` replay e conversa; `create_ticket_service.rb:57` persistência/evento na transação | Preservar implementação e testes existentes; provar concorrência PostgreSQL e retry com payload/vínculo diferente. Número atual é `id.to_s` após persistência (`presenter.rb:24`); exemplo SD-000249 da fonte não deve ser imposto silenciosamente como formato obrigatório |

## Visibilidade V2 e superfícies relacionadas

A base só tem `internal`: model `ticket_note.rb:14`; serviço `add_note_service.rb:5` aceita só body e `:19` grava internal; policy `ticket_note_policy.rb:5`; serializer `presenter.rb:69`; constraint SQL histórica `db/migrate/20260925190100_create_jrc_service_desk_core.rb:211`. Esse fluxo preserva segurança interna, mas não implementa V2. As notas são append-only e utilizam ActiveStorage (`ticket_note.rb:5`, `:8`). Não se deve mudar constraint histórica, tornar legadas públicas ou apenas aceitar visibility em params sem autorização.

| ID | Fonte | Esperado | Estado / evidência / lacuna | CP / aceite |
|---|---|---|---|---|
| SD-V01 INTERNAL | Word §§6.1,6.5–6.7 | Somente internos autorizados; nunca portal/canal externo | IMPLEMENTADO_PARCIAL: modelo/policy/serviço/constraint só interno. Scoping e capability notes_view nos TicketRecordPolicy/TicketPolicy. Falta validar todas as novas superfícies no fluxo integrado | CP10: antigos permanecem internos; matriz negativa prova portal/export/IA/canais |
| SD-V02 TECHNICAL_TEAM | Word §§6.1,6.5–6.7 | Somente equipe/usuário técnico autorizado no vínculo; jamais externo | NAO_IMPLEMENTADO: nenhum enum/policy/schema/service/rota técnico SD localizado; current TicketNote rejeita esse valor | CP10: permissão explícita + vínculo equipe + Account/Unit; equipe não amplia unidade |
| SD-V03 CUSTOMER | Word §§6.1–6.7 | Portal para contatos autorizados; notify por política/canal | NAO_IMPLEMENTADO: ausência de model/evento/publicação/portal de interação e de capability publish_customer em `capabilities.rb:7` | CP10: autoria, alvo, canais/templates/providers/versões/delivery reais; canal ausente bloqueia; só sucesso confirmado |
| SD-V04 PUBLIC_WITHOUT_NOTIFICATION | Word §§6.1–6.7 | Portal autorizado sem email/WhatsApp | NAO_IMPLEMENTADO: nota só internal e nenhum endpoint de publicação portal | CP10: publicação e proibição de side effect externo testadas, inclusive retry |
| SD-V05 Sem público por default | Word §6.1 e prompt §7 | Política explícita persistida antes da interação; compatibilidade | IMPLEMENTADO_PARCIAL: default internal atual em migration `:206`; não existe nova política/enum | CP10: migração aditiva com backfill interno; campo legado boolean public não vira fonte de verdade |
| SD-V06 Composer/destinatário | Word §6.2 | Selector, botões coerentes, canais disponíveis/motivo, preview pela política | NAO_IMPLEMENTADO no cockpit; nota continua texto interno e sem selector (`TicketActivity.vue:92`) | CP9/10: preview e envio reais com readback, sem seleção implícita de canal/pessoa |
| SD-V07 Tarefas e checklist | Word §§6.3,9 | Título/descrição/responsável/prazo/prioridade/status/checklist; mesma política de visibilidade/comunicação, histórico e automações | NAO_IMPLEMENTADO em SD. Tab tasks pending (`TicketDetailView.vue:27`, `:95`); `JrcNico` specs reconhecem `native_tasks_not_available` (`spec/services/jrc_nico/domain_actions_spec.rb:137`) | CP11: reaproveitar Projetos/Tarefas quando adequado, vínculo e ACL SD, comentários/anexos com mesma regra; vencidas no cockpit/IA |
| SD-V08 Anexos | Word §§5,6.3,20 e prompt §7 | ACL por ticket/interação/visibilidade, upload/download/access trail, expiração, antivírus disponível | ESTRUTURA_EXISTENTE: `has_many_attached :files` (`ticket_note.rb:8`); zero projeção/download/upload SD encontrados; UI upload pending (`TicketDetailView.vue:98`, `TicketFormView.vue:268`) | CP10/11: não retornar URL pública direta de nota interna; authorize em acesso, anexo herda policy e histórico de scan/expiração |
| SD-V09 Portal identidade separada | Word §§6.7,14,22 P0-11 | Meus chamados/número, abrir catálogo, status/SLA, resposta/anexo/histórico/KB/pesquisa, somente próprios/autorizados | NAO_IMPLEMENTADO para tickets. Portal existente é Help Center (Portal→Articles `app/models/portal.rb:33`–`:39`; `articles_controller.rb:13`), não prova portal SD. `JrcFlows::PortalController` é superfície Flows, sem tickets | CP10/11: evoluir capacidades existentes e identidade, não duplicar portal; positivos/negativos por cliente/Account/Unit |
| SD-V10 Busca/export/APIs | Word §6.7,§20 e prompt §7 | Backend aplica mesma visibilidade/escopo a buscas, exports e related items | IMPLEMENTADO_PARCIAL para APIs internas atuais: `related_records_query.rb:10` autoriza tipo; scoped em `:40`; `tickets_controller.rb:80` prende item ao parent Account/Unit/ticket. Export segue PendingAction (`PlannedView.vue:35`) | CP10/16: filtro por audiência central usado em todas as projeções; não aplicar só Vue |
| SD-V11 IA e resultados salvos | Prompt §§4,7,11; Word §13 | Somente conteúdo permitido na entrada/saída/contexto/KB e em acesso a resultado salvo | IMPLEMENTADO_PARCIAL: `app/services/jrc_nico/domain_access.rb:118` revalida view_notes/sla/customer; `:130` autoriza nota e parent; `domain_actions.rb:197` vincula recursos de conteúdo protegido; HistoryProjection (`history_projection.rb:8`) mascara note/solution/evidence | CP10/15: acrescentar audience técnica/cliente, anexos/tarefas e exports; revalidar revogação e conteúdo autorizado também ao reler resultado |
| SD-V12 Imutabilidade/republicação | Word §6.4 | Interna→pública exige novo evento/ação explícita com motivo; correção preserva versão; reenvio novo audit | IMPLEMENTADO_PARCIAL: notas/events append-only (`ticket_note.rb:5`, `ticket_event.rb:4`); nenhum fluxo de republicação/versão pública/reenvio | CP10: novo evento com autor/tempo/motivo/referência ao original, sem overwrite |
| SD-NOTIFY | Word §6 e tabela eventos, §6.4,§18 notification_events | Política unidade/canal/tipo/evento; criado/assumido/resposta/status/espera/tarefa/aprovação/escalonamento/resolve/close/reopen/pesquisa; destinatário/template/versão/provider/tempo/status/erro/reenviar | NAO_IMPLEMENTADO como motor SD. Tipos TicketEvent não incluem notificações (`ticket_event.rb:6`); não há job SD de notificação nem tabela notification_events. Canal nativo é infraestrutura a reutilizar | CP10/12/13: interno/técnico/escalonamento interno bloqueados de comunicação externa; entrega real e falha parcial por canal, sem reenviar sucesso |

## Account, operadora, unidade e empresa cliente

- Account continua tenant. `access_context.rb:19` verifica identity AccountUser→Account/User; flag `jrc_service_desk` e Account ativo em `:21`. `OperationalContext` refresca identidade a cada operação (`operational_context.rb:84`) e grants UnitMembership ativos (`:26`).
- Empresa operadora é `OperatorCompany` e Unit pertence a ela (`app/models/jrc_service_desk/unit.rb:4`); Ticket deduz operadora da Unit (`ticket.rb:39`) e não cria empresa cliente paralela.
- Empresa cliente canônica é `JrcCustomers::Company` por `OperationalCompanyLink` (`app/models/concerns/jrc_customers/operational_company_link.rb:5`), com decisão de links e conflito (`:42`) e verificação tenant (`:48`). `create_ticket_service.rb:16` exige permissão Directory ao selecionar Company. `customer_context_service.rb:29` reutiliza esse vínculo.
- TicketPolicy::Scope usa Account+Unit grant antes de created_by/assignee/team (`ticket_policy.rb:37`–`:43`). A presença de TeamMember não autoriza outra Unit. Admin tem separação de visualização/cadastro estrutural, mas tickets usam unit_scope; testes existentes tratam admin sem grant.
- Toda mutação atual revalida identidade/AccountUser/CustomRole e serializa Unit (`base_service.rb:22`–`:38`); parent ticket é relido com lock e policy (`:46`–`:50`). Referências de catálogo são Account+Unit (`:62`); Team é Account+policy (`:68`); assignee exige grant ativo+capability (`:76`–`:84`).
- A política de visualização por empresa cliente é indireta pelo escopo operacional/ticket e cadastro mestre; não existe ACL de portal por contato/empresa no SD. Não classificar portal/visibilidade multiempresa completo com base apenas no Account scope.
- Objetos relacionados, exports/jobs/IA precisam conservar essa camada e acrescentar audiência V2. Capabilities hoje não contemplam publicar cliente, técnico, anexos, tarefas/aprovações/incidentes, automações/export.

## SLA OLA distribuição e jobs

| ID | Fonte | Estado e evidência | Lacuna / dependência / aceite |
|---|---|---|---|
| SD-SLA01 Histórico/versionamento | Word §7 e prompt §7 | IMPLEMENTADO_PARCIAL: LifecyclePolicyVersion append-only; Ticket impede trocar versão histórica (`ticket.rb:67`); selector Account/Unit/service (`lifecycle_selector.rb:15`) | Preservar versões/snapshots e histórico no rollout; não converter backlog para metas novas sem política |
| SD-SLA02 Calendário/fuso/feriado/pausas | Word §7 | IMPLEMENTADO_PARCIAL: `snapshot_calendar.rb:12` exige fuso e contrato semanal/feriados/exceções explícitos; precedence em `:89`; TZInfo/DST em `:100`; pauses e budgets em `lifecycle_clocks.rb:98` e `:140` | Specs existem; sem execução CP0. Calendário/snapshot ainda devem ser fornecidos/validados, sem fallback Inbox/unidade/default |
| SD-SLA03 Primeira resposta/atendimento/solução | Word §7 | IMPLEMENTADO_PARCIAL: CLOCKS só `first_response resolution` (`lifecycle_rules.rb:5`); lifecycle exclui inferência de resposta pública (`:123`); engine cria ciclo com snapshot e budget (`lifecycle_clocks.rb:114`) | Métrica de atendimento/OLA e evento real que completa first_response não presentes; integração mensagens é dependência. Não declarar first_response atendido por resolver/status |
| SD-SLA04 Seleção política | Word §7: cliente/contrato/serviço/categoria/prioridade/canal | IMPLEMENTADO_PARCIAL: selector diferencia service ou fallback explícito de Unit (`lifecycle_selector.rb:15`–`:17`) | Não há regras por cliente/contrato/categoria/prioridade/canal com desempate/versionamento. RecordSlaSnapshotService é comando interno, sem endpoint de captura em routes. Contrato/calendar real deve abastecer snapshot |
| SD-SLA05 Alertas/escalonamentos | Word §7,§21: 70/90/100 parametrizável; NICO R05 80% | NAO_IMPLEMENTADO como motor SD. Não há jobs SD próprios; dashboard declara sla_breached unavailable (`dashboard_service.rb:17`) | Políticas versionadas e precedência de 70/90/100 versus 80 são decisão pendente; ativação desabilitada, nunca duplicar notificações acidentais |
| SD-SLA06 OLA | Word §7 | NAO_IMPLEMENTADO: sem metric/instance por fila/equipe independente; engine tem dois clocks SD | CP12: OLA separado do SLA contratado com snapshot/ciclo/permissão e regra de escalonamento |
| SD-ROUTE01 Manual | Word §8 | IMPLEMENTADO_PARCIAL: AssignTicket/TransferTicket persistem sob expected_lock_version, scoped references e evento (`assign_ticket_service.rb:17`, `:28`) | Elegibilidade atual não verifica disponibilidade/capacidade/skills nem membership Team do responsável; futura política deve definir quando necessários |
| SD-ROUTE02 Round Robin/menor carga/skills/prioridade SLA | Word §8 | NAO_IMPLEMENTADO no domínio SD: Queue mínima (`queue.rb:4`); TicketQuery.sort só created_at/updated_at (`ticket_query.rb:7`) | Não confundir AutoAssignment de Conversations, JrcOperations::Queue ou routing CS com ticket SD. Reutilização possível exige adaptador sob ACL SD |
| SD-ROUTE03 Claim-next atômico | Word §8,§19 e prompt §7 | NAO_IMPLEMENTADO: ausência de route/action/service claim_next/claim-next na árvore SD e enterprise; API atual em `config/routes.rb:86`–`:103` | CP12: transação/lock, elegibilidade Account/Unit/equipe/skill/capacidade/permissão/disponibilidade, priority/SLA e teste com conexões concorrentes reais |
| SD-LC Resolve/close/reopen | Word §3,§22 | IMPLEMENTADO_PARCIAL: `lifecycle_transition_service.rb:18` replay, `:29` capability específica, `:35` payload, `:39` janela de reopening, `:89` evidencia parent; mesmo Ticket alterado em `:52` | Completar resolução code/summary conforme política e comunicação/pesquisa; não trocar ticket por novo em reabertura nem resetar histórico. Validar janela/budgets e efeitos reais |
| SD-JOB Integração CS | Word §15,§21 e prompt §7 | IMPLEMENTADO_PARCIAL: Ticket inclui SignalDispatch (`ticket.rb:4`), after_commit job em `app/models/concerns/jrc_relationship/signal_dispatch.rb:4`; `app/jobs/jrc_relationship/signal_job.rb:41` gera follow-up crítico autorizado/idempotente | Isso não é avaliação de motor compartilhado de pesquisa; não se encontrou gatilho SD encerramento→SurveyPolicy/Dispatch/Delivery. Health/riscos existentes precisam evidência no motor unificado |

## Critérios P0 01 a 12

| Critério fonte Word §22 | Leitura CP0 | Evidência / restante para teste |
|---|---|---|
| P0-01 Criação persistida | IMPLEMENTADO_PARCIAL | `spec/requests/api/v1/accounts/jrc_service_desk/operations_spec.rb:40` cobre criar/GET/lista/minha fila; não executado |
| P0-02 Número único | IMPLEMENTADO_PARCIAL | `spec/services/jrc_service_desk/cp4_concurrency_spec.rb:51`, `:61` e CreateTicketService replay; executar concorrência PostgreSQL real |
| P0-03 Classificação/roteamento autorizado | IMPLEMENTADO_PARCIAL | `spec/requests/api/v1/accounts/jrc_service_desk/security_spec.rb:76`, `:89`; falta automação/full eligibility |
| P0-04 SLA backend calendário/pausas | IMPLEMENTADO_PARCIAL | `spec/services/jrc_service_desk/lifecycle_clocks_spec.rb:20`, `:66`; falta first_response canal/atendimento/OLA/seleção plena |
| P0-05 Minha fila elegível | IMPLEMENTADO_PARCIAL | TicketQuery.mine só atribuídos e policy unit; falta claim-next/disponíveis |
| P0-06 Timeline crítica auditável | IMPLEMENTADO_PARCIAL | TicketEvent tipos e lifecycle; `cp4_workflow_spec.rb:38` rollback do marker; falta timeline interações completa |
| P0-07 Notificações e erro | NAO_IMPLEMENTADO SD | Ausência do motor de eventos/canais/dispatch/provider/delivery/retry |
| P0-08 Multiunidade | IMPLEMENTADO_PARCIAL sem teste desta rodada | `security_spec.rb:22`, `:135` e `unit_access_spec.rb:159` negativos específicos; não extrapolar às novas superfícies |
| P0-09 Código/resumo resolução | IMPLEMENTADO_PARCIAL | Requirements.fields pode representar código configurado; `lifecycle_transition_service_spec.rb:30` testa solution/evidence/campo. Comunicação não existe |
| P0-10 Reabertura preservada/SLA | IMPLEMENTADO_PARCIAL | `lifecycle_transition_service_spec.rb:9` e LifecycleRules.reopen; completar reação a resposta negativa/correlação |
| P0-11 Portal só próprios | NAO_IMPLEMENTADO SD | Portal nativo somente KB; nenhuma identidade/policy de portal de tickets encontrada |
| P0-12 Antes/depois/autor/hora | IMPLEMENTADO_PARCIAL | Assign saves changes; lifecycle from/to/actor/occurred/version; config native audit. Falta notification/export/task/approval/incident trails |

## Testes encontrados e validação ainda necessária

Não foram executadas suítes Ruby/JS/E2E/build/lint nesta subtarefa: autorização recebida foi CP0 somente leitura. Os únicos comandos de validação foram Git status, HEAD/branch/origin e diff --check. Specs lidas não são prova de resultado atual. Nenhum item foi promovido a IMPLEMENTADO_FUNCIONAL por presença de arquivos ou descrição de teste.

Conjuntos encontrados (usar ferramentas/versões do projeto na implementação):

- Criação/reload/idempotência: `spec/services/jrc_service_desk/create_ticket_service_spec.rb:13`, `:21`, `:28`, `:56`; `cp4_workflow_spec.rb:12`, `:23`, `:31`; `cp4_concurrency_spec.rb:51` e `:61`.
- API e isolamento: `spec/requests/api/v1/accounts/jrc_service_desk/operations_spec.rb:40`, `:62`, `:162`, `:183`; `security_spec.rb:14`, `:22`, `:120`, `:127`, `:135`; `unit_access_spec.rb:92`, `:99`, `:132`, `:159`.
- Lifecycle/nota/evidence/versões: `spec/services/jrc_service_desk/lifecycle_transition_service_spec.rb:9`, `:49`, `:59`, `:91`, `:103`; `lifecycle_concurrency_spec.rb:17`; `cp6_history_visibility_spec.rb:14`, `:26`, `:36`.
- Calendário: `spec/services/jrc_service_desk/lifecycle_clocks_spec.rb:12`, `:20`, `:66`; `spec/isolated/jrc_service_desk_clock_engine_test.rb:71` e engines/contracts isolados.
- Constraint legado interno: `spec/models/jrc_service_desk/history_and_sla_spec.rb:9`; `spec/migrations/jrc_service_desk_core_spec.rb:93` verifica rejeição pública; devem evoluir com migration aditiva e preservação legada.
- Configuração/versionamento/ACL: `spec/services/jrc_service_desk/configuration_service_spec.rb:14`, `:30`, `:39`, `:58`, `:67`, `:81`, `:87`.
- UI: `app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/views.spec.js`, `cp4Views.spec.js`, `cp4Contracts.spec.js`, `cp5Views.spec.js`, `lifecycleViews.spec.js`, `lifecycleContracts.spec.js`, `configurationViews.spec.js`, `unitAccess.spec.js`, `routing.spec.js`. A existência de fixtures/mocks não homologa API/canal real.
- IA específica: `spec/services/jrc_nico/domain_actions_spec.rb:204`–`:209` cobre revogação de SLA salvo e `:137` documenta ausência de tarefas SD. Revalidar depois de incluir audiência V2.

Não encontrados testes pertinentes de V2 técnico/cliente/portal sem notification, upload/download V2, claim-next, motor de eventos SD, approval/ticket incident/service catalog completo ou E2E do fluxo SD completo. Criar negativos/concorrência/tempo/falha externa de cada nova superfície e executar regressão integrada.

## Conflitos decisões e riscos

1. Documento chama o arquivo V2 e o conteúdo de versão 1.0; fixar referência por nome efetivo/hash e §§6.1–6.7, não pelo sufixo.
2. Fonte sugere valores físicos `visibility` com tabela ambígua por `|`, e boolean `public` no modelo mínimo §18; prompt determina quatro comportamentos e proíbe boolean legado como verdade. Adotar representação compatível com o domínio, com policy central e default interno explícito.
3. Limiares SLA 70/90/100% da fonte versus NICO 80%; manter políticas versionadas/configuráveis, pendentes de ativação/precedência aprovada. Horas úteis/corridas/7 dias também dependem de decisão registrada por outro inventário NICO, sem conversão implícita.
4. Word §19 usa caminhos recomendados `/service-desk`; reais são `/api/v1/accounts/:account_id/jrc_service_desk`. Preservar contratos existentes; implementar comportamentos faltantes sem exigir renomeação artificial.
5. Menu atual tem entradas extras (`routeDefinitions.js:11`, `:16`–`:18`, `:20`) em relação às 13 finais. A existência dessas rotas planned não deve ser contabilizada como funcionalidades nem motivar descarte de módulos existentes.
6. Serialização do número é ID backend, não coluna específica. Fonte dá SD-000249 como exemplo. Não inventar requisito de prefixo/numeração separado; garantir unicidade/retry/readback e registrar decisão de apresentação oficial se necessário.
7. OLA e atendimento não são clocks existentes; primeira resposta corretamente não é inferida do lifecycle, mas integração real do evento público falta. Fabricar SLA atendido por mudança de status seria erro.
8. Anexos têm só associação ActiveStorage. Quando abertos em UI/portal/IA, autorização precisa ocorrer no acesso e herdar audiência da interação; signed URL por si não prova ACL/scan/expiry/audit adequados.
9. Publicar conteúdo interno, notificar cliente, configurar automação e administrar escopo exigem capacidades distintas da simples visualização/adicionar nota. Dar todos esses poderes a `notes_add` contrariaria V2.
10. Lock de unidade atual serializa todos os writers da Unit. Preservar garantias enquanto claim-next usar concorrência real; revisar contenção ao expandir volume, sem remover isolamento para otimização especulativa.
11. Integração externa email/WhatsApp deve reutilizar providers nativos e declarar canal indisponível/resultado desconhecido; não há autorização para comunicar clientes reais nem ativar políticas nesta rodada.
12. Aprovações de ticket, incidentes e catálogo precisam evoluir modelos existentes ou adicionar entidades mínimas; não duplicar CRM/cliente/portal/projetos/executor/pesquisas.

## Sequência mínima proposta de implementação

1. CP9: preservar criação/idempotência/ACL/lifecycle; reorganizar cockpit com cabeçalho/contexto/timeline 360 sobre projeções existentes, mostrando honestamente indisponibilidade. Validar API/readback e estado de negócio persistido.
2. CP10: fundação V2 no backend, migration aditiva e backfill somente internal; capabilities/audience/policy central, append-only/correção/republicação explícita. Aplicar em APIs/IA/timeline/attachments/exports/portal. Só então habilitar ações públicas no composer sob policy/canal/destinatário real.
3. CP11: tarefas/checklists/anexos com policy, workflow de aprovação e incidente/pai, catálogo/formulário. Reutilizar Projetos/Help Center/identidade portal e não declarar provider inexistente. Adicionar testes negativos de objetos relacionados.
4. CP12: completar snapshots/seleção SLA, OLA e relógio atendimento/primeira resposta real; distribuição elegível e claim-next atômico. Jobs backend versionados/observáveis de limiares/notificações/lembretes, desativados para clientes reais.
5. CP13: integrar encerramento SD à avaliação do motor compartilhado de pesquisa, preserving policy/version/cycle/source e uma só cadeia de health/risco/ação. Sem sistema survey paralelo e sem envio incondicional.
6. CP16: concorrência PostgreSQL, RBAC Account/Unit/empresa negativa, V2 em mensagens/tarefas/anexos/portal/export/IA, calendário/feriado/fuso/pausas, reopening, provider ausente/falha parcial/unknown e E2E do fluxo completo; git diff --check e documentação de rollout/backfill/recuperação. Homologação continua separada de código e validação local.

CP0_SERVICE_DESK=CONCLUIDO_SOMENTE_LEITURA
CODE_CHANGED=NAO
TESTS_EXECUTED=NAO
MIGRATIONS_EXECUTED_ON_SERVER=NAO
COMMIT_EXECUTED=NAO
PUSH_EXECUTED=NAO
IMAGE_PUBLISHED=NAO
DEPLOY_EXECUTED=NAO
ATIVACAO_EM_CLIENTES_REAIS=NAO


---

# Auditoria NICO HelpDesk no CP0

Leitura das fontes e inspeção estática do Git aprovado em 08/10/2026. Nenhum código, Git, banco, segredo, container ou integração foi alterado por esta auditoria. Nenhuma mensagem real foi enviada. A inspeção não estabelece homologação funcional: os testes existentes foram localizados, mas não executados neste subtrabalho.

## Base e fontes efetivamente usadas

- Repositório esperado: `ClaudioHideki/jrc-conversas-lab2`.
- Base de referência: `4ce8241d35ce862e9d53e9a5dce4df9a1858432c`.
- Checkout inspecionado: `C:/Users/DEV03/Documents/Jrc/ia-provedor-unico-20261007`.
- Instruções: `AGENTS.md` desse checkout e texto de continuidade `C:/Users/DEV03/.codex/attachments/a1653d0b-2d80-4a95-a934-6c23d0960ebc/Texto colado.txt`, integralmente lido.
- Word: `C:/Users/DEV03/Downloads/Proposta NICO Automacao HelpDesk Thiago Ribeiro - R1 - Out26.docx`, SHA256 `9b21f674bc1bd9f66d0103204d12c04a935af55757539d7e6c582a4d303a0953`. 29 blocos de corpo, 26 parágrafos e 2 tabelas; partes de rodapé, comentários e notas também extraídas. Localizadores `BODY_BLOCK` e `T… R…C…` constam de `nico-source.txt`.
- Excel: `C:/Users/DEV03/Downloads/Automacao NICO HelpDesk JRC - R1 - Out26.xlsx`, SHA256 `6a4beb0845cdce62fced210819b8850e8a6125650fd8a5c40797f710406d9bd3`. Fontes efetivas sem sufixo `(1)`, conforme os arquivos anexados existentes autorizados. Os sufixos não foram tratados como nova versão funcional.
- Todas as cinco abas foram percorridas: Resumo `A1:D29`; Catálogo NICO `A1:L16`; Regras de alerta e N2 `A1:H20`; Relatório diário (modelo) `A1:K37`; Fases e KPIs `A1:E42`. Total: 1.085 posições, 571 células não vazias, 63 fórmulas, todos os 63 caches preenchidos, nenhum comentário de célula e nenhum nome definido. `workbook-source.txt` contém endereço, tipo, valor/fórmula, cache, formato numérico, nota e hyperlink de cada posição, incluindo vazias; mesclagens e validações estão registradas.
- Runtime de extração: Python empacotado `C:/Users/DEV03/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`, `python-docx`/OOXML e `openpyxl` somente leitura. Fontes originais não foram salvas ou recalculadas. Não foi usado LibreOffice desktop.

Conferência aritmética independente: soma de Catálogo `D5:D15` = 1.439, igual ao cache `D16` e Resumo `B10`; atrasos positivos de `I10:I18` no modelo = 6, igual ao cache `B19`, de 9 linhas em `D19`. Isso confere o exemplo histórico; não transforma os valores em métricas atuais nem prova recálculo em Excel. Os 1.302 registros internos em Resumo `A28` ficam fora da base de 1.439 chamados. O potencial de 207 autônomos + 451 semiautônomos é estimativa histórica, não resultado do produto.

## Evidências reutilizáveis existentes

Os caminhos abaixo são relativos ao checkout inspecionado e os números de linha referem-se à base aprovada.

| Ref. | Evidência real | Limite que impede declarar o novo HelpDesk pronto |
| --- | --- | --- |
| N1 | `app/services/jrc_nico/tool_catalog.rb:2`, `:62`, `:92`: catálogo finito por perfil, campos permitidos/obrigatórios e tipos; escritas marcadas com confirmação. `tool_executor.rb:9` valida antes do dispatch. | Não contém comandos Billing, reset PABX/OTP, URA, provisionamento, diagnóstico técnico ou os 11 grupos desta planilha. |
| N2 | `app/services/jrc_nico/domain_tool_catalog.rb:6`: ferramentas de Service Desk R2 para catálogo, consulta, criação, atribuição, notas e ciclo de vida. `domain_actions.rb:165`, `:173`, `:184`, `:205` delega aos serviços nativos; `:64` gera chave a partir de comando persistido com Account/usuário. `domain_access.rb:25`, `:58`, `:110` reutiliza políticas nativas e escopos de unidade. | Ferramentas existentes não equivalem a triagem automática, reincidência ou escalonamento por regra. Nota atual é interna. |
| N3 | `app/services/jrc_nico/operator_session.rb:52`: reautoriza, valida cliente de origem, bloqueia Account/sessão/comando, exige estado de confirmação e cancela prévia após 15 minutos. `:75` persiste aprovador; `:77` usa o executor existente; `:506` sanitiza falha e atribui `unknown` à execução interrompida. `:106` revalida ação de navegador e seu destinatário. | Confirmação do operador não comprova aprovação pelo administrador do cliente nem validação de OTP. Faltam política HelpDesk, vínculo explícito a payload/escopo do cliente e capacidades externas com conciliação. |
| N4 | `app/controllers/api/v1/accounts/jrc_nico/proposals_controller.rb:28`, `:44`, `:51`: prévia comercial com digest, prazo e revalidação, executada em transação. | Aprovação cobre atividades/negócios comerciais, não telefonia nem faturas/senhas do cliente. Reutilizar padrão, sem alegar cobertura universal. |
| N5 | `app/services/jrc_nico/delegation_service.rb:7`, `:23`: flag por Account e bloqueio de conversa já controlada por bot/Flow; expiração até 8 horas, pausa/handoff e versionamento. `delegated_actions.rb:17` revalida tenant, usuário, conversa, versão e conjunto finito de ferramentas. `customer_request_scope.rb:2` revalida vínculos da conversa/contato. | Delegações atuais são comerciais; não habilitam automaticamente Service Desk/Billing/PABX. Não existe lista de clientes piloto HelpDesk ou limite de ações por hora específico. |
| N6 | `app/services/jrc_flows/actions.rb:9` executa mensagens/notas, atribuição, status, etiquetas, atividades CRM e webhook; `:101` envia chave de idempotência. `workflow_engine.rb:12` limita profundidade a 4 e passos a 200; `:127` isola Redis por Account/Flow; `:166` bloqueia HTTP no simulador. Definition/Runner/RecoveryJobs existentes. | Não há nós HelpDesk específicos, aprovação do administrador do cliente ou garantias de conciliação para telefonia; nó HTTP genérico não comprova API de negócio integrada. O agente legado de Flow tem segredo OpenAI próprio (`workflow_engine.rb:148`); novos usos NICO devem manter `AccountProvider` sem introduzir fallback global. |
| N7 | `app/services/jrc_broker/client.rb:29`, `:33`, `:37`, `:53`, `:57`, `:65`: context/resources/onboarding, status, pair QR, disconnect, confirmação de identidade do canal e agentes. `control.rb:9`, `:17`, `:28` reautoriza antes/depois de operações e filtra ações. `response.rb:30` projeta Health. Context/configuration/credential_store validam vínculo de Account e chave protegida. | Cliente Broker não oferece Billing, PABX, URA, ramais/troncos, Reporter ou desbloqueio de IP. Confirmação da identidade do número WhatsApp não é validação OTP do administrador do cliente para A2. |
| N8 | `app/services/jrc_ai/account_provider.rb:7`, `:33`: provider/model/base URL da conta, erro explícito sem configuração, validação de Account. `operational_inference.rb:27` grava consumo por conta. `runtime_client.rb:130` anexa configuração protegida fora do prompt e valida resposta/escopo; `:96` registra somente request_id/código. `config/initializers/00_ruby_llm_logging.rb:7` e `lib/llm/safe_logger.rb:18` descartam conteúdo SDK. | Preservar integralmente; nenhum novo provider global, chave de teste ou chave em payload de frontend. Não aumentar reservas de tokens neste escopo. |
| N9 | `app/services/jrc_nico/erp_context.rb:6`, `:16`: leitura ERP condicionada a Account permitido, binding habilitado do contato, modo correto e administrador; indisponibilidade explícita. `agent_catalog.rb:9`, `:11`, `:13` informa limitações de HelpDesk, segunda via e provisionamento. | Leitura ERP autorizada não entrega fatura/contrato, não executa cobrança e não valida identidade do destinatário externo. |
| N10 | `app/services/jrc_service_desk/lifecycle_transition_service.rb:39` e `lifecycle_rules.rb:24` reabrem conforme política histórica; clocks/snapshots preservam calendário/ciclos. `ticket.rb:29` valida chave de criação por Account/unidade/criador; empresa cliente usa vínculo canônico distinto da empresa operadora. | Não há detector de resposta negativa/reincidência nem campos/relações especiais R01–R04 demonstrados no modelo Ticket. Reabertura deve respeitar janela/transição existente. |
| N11 | `app/services/jrc_relationship/processor.rb:99`, `:104`, `:109` gera ações/riscos por satisfação, chamados críticos/SLA e contagem recorrente; `customer_signals.rb:63` fornece chamados recentes. | A contagem de chamados recentes não compara defeito/serviço/ativo nem fechamento anterior; não satisfaz R01/R02/R03. Efeitos de satisfação existentes não comprovam R10/R15 por atendimento. |
| N12 | `app/services/jrc_service_desk/dashboard_service.rb:8` usa TicketQuery autorizado e KpiCounts; `:17` declara indisponíveis SLA violado, CSAT, séries e capacidade. `config/schedule.yml` tem recuperação NICO/Flows, sinais CS a cada 15 minutos e monitores Operations/CS a cada 5 minutos. | Não foi encontrado job específico do relatório NICO às 18h ou implementação dos sete KPIs da fonte. Cadências existentes não comprovam reação de 5 minutos contando fila/latência. |

Testes encontrados: `spec/services/jrc_nico/domain_actions_spec.rb`, `commercial_delegation_spec.rb`, `runtime_client_spec.rb`, `erp_context_spec.rb`; requests NICO operations/proposals/runs/history; requests Broker contract/inbox/control; services Service Desk lifecycle/clock/concurrency; `spec/services/jrc_ai/account_provider_spec.rb`; `spec/lib/llm/safe_logger_spec.rb`; frontend `nicoRunSession.spec.js`, `nicoBrowserActions.spec.js`, `nicoAutomaticCalls.spec.js`, `FlowsWorkspace.spec.js`. Sua existência é evidência de estrutura de verificação, não resultado de execução nesta auditoria.

Rotas existentes em `config/routes.rb:203` (Broker), `:367` (Flows), `:564` (NICO), `:574` (confirmar), `:576` (claim), `:577` (receipt), `:588` (propostas). Não foi localizado CRUD de políticas/11 grupos/R01–R16/KPIs/relatório HelpDesk. Nenhuma migration nova nesta auditoria.

## Cobertura dos 11 grupos do catálogo

Status considera o fluxo completo solicitado, não a presença de ferramentas genéricas. Os anexos oferecem requisitos; as ações abaixo não foram realizadas.

| ID / fonte | Comportamento esperado e fase | Status CP0 / implementação existente | Lacuna, dependência e checkpoint | Critério de aceite |
| --- | --- | --- | --- | --- |
| A1 — Catálogo `A5:L5`; Word T12 R2 / T22 R2 | Mensagem WhatsApp/e-mail ou solicitação financeira; validar identidade/acesso, consultar fatura/débito/contrato, entregar só documento autorizado, registrar/concluir; contestação/juros/multa ao Financeiro. Fase 1. | BLOQUEADO_DEPENDENCIA. N9 oferece leitura ERP; N1/N7 não oferecem segunda via/Billing. | Contrato/API Billing, documentos protegidos, identidade do solicitante e destino Financeiro. CP15A/B/E. | Sem identidade/provider não entrega/finge consulta; documentos e conclusão verificados; autorização por empresa/Account; contestação encaminhada; retry não duplica envio/fechamento. |
| A2 — `A6:L6` | Solicitação de acesso/painel; administrador do cliente + OTP; API de usuários, link seguro; perfil maior ou não validado ao N1. Fase 1. | BLOQUEADO_DEPENDENCIA. N3 confirma operador; N7 valida número do canal, sem OTP PABX. | API de usuários PABX, emissor/verificador OTP, vínculo ao administrador cliente, expiração/aprovação da ação. CP15A/B/E. | Sem OTP/admin/provedor não executa; não aumenta privilégio; link protegido; nenhuma senha/OTP/token em UI/logs/histórico. |
| A3 — `A7:L7` | Pedido Reporter/relatório/gravação; consulta sob demanda/agendada por data; consistência antes de abrir tarefa; divergência real ao N2 de dados. Fase 1. | BLOQUEADO_DEPENDENCIA. N1/N9 consultam escopos; chamadas internas não comprovam Reporter. | APIs Reporter/gravações, armazenamento/link autorizado, regras de divergência e destinatário N2. CP15B/E. | Escopo de data/empresa/Account conferido, dado real e link protegido, ausência de API visível, divergência só após evidência. |
| A4 — `A8:L8` | Pedido/calendário; texto/locução aprovados pelo administrador, publicar áudio/URA/feriado, voltar ao padrão, bloqueio de número/fila simples; regras complexas/locução humana ao N1. Fase 2. | BLOQUEADO_DEPENDENCIA. N6 oferece webhook genérico, N3 confirmação de operador. | APIs URA/filas/telefonia, voz aprovada, versões/agenda/compensação e aprovação cliente. CP15A/C/E. | Payload aprovado e vigente; verificar alteração e retorno real; sem API/admin não altera; falha pós-envio fica desconhecida até conciliação. |
| B1 — `A9:L9` | Pedido de cadastro; coletar nome/e-mail/ramal/perfil, confirmar administrador e criar/alterar por Flow/API; duas tentativas incompletas ou limite do plano -> N1. Fase 2. | BLOQUEADO_DEPENDENCIA. N1 cadastra contatos internos, N6 executa Flow; não cadastra ramal. | PABX/limites de plano, contrato de cadastro, aprovação cliente, contador de tentativas. CP15A/C/E. | Duas tentativas e plano tratados sem loop; ação exata aprovada; autorização de maior privilégio negada; releitura prova resultado. |
| B2 — `A10:L10` | Instalação/configuração SIP/DeskPhone/softphone/app; guia/provisionamento e verificar registro real; após duas falhas -> N2 com dossiê. Fase 2. | BLOQUEADO_DEPENDENCIA. N1 channel_status verifica configuração do operador, não registro do ramal do cliente. | API status/provisionamento, guias aprovados e vínculo ao equipamento/cliente. CP15C/E. | Registro real conferido; duas falhas encaminhadas com tentativas/evidências; segredo SIP nunca exposto. |
| C1 — `A11:L11` | Defeito de voz; checklist, status ramal/tronco, número/horário/operadora; ação segura autorizada e N2 em persistência, reincidência ou massa. Fase 3; alertas Fase 1. | BLOQUEADO_DEPENDENCIA. N1 KB aprovada/N10 ticket; não há API técnica. | APIs de ramal/tronco/desbloqueio, whitelist de ações, aprovação cliente e R01–R04. CP15A/B/D/E. | Diagnóstico tem fontes; não inventa registro/solução; ação segura verificável; falha/reincidência encaminha N2. |
| C2 — `A12:L12` | Health degradado ou mensagem; avisar conforme política, pair/reconexão por QR/API; falha/bloqueio Meta -> N2. Fase 2. | IMPLEMENTADO_PARCIAL. N7 Health/pair/status/operação estão disponíveis para operador com grant. | Conectar evento Health a política NICO/Flow, escopo/piloto/destinatário/template, estado de reconexão e handoff. Provider real/configuração não inspecionados. CP15C/E. | Respeita allowedActions/grants/identidade; status real antes/depois; não contorna bloqueio; nenhum aviso em conta/cliente indevido. |
| D1 — `A13:L13` | Todo novo chamado; inferir serviço/tipo/prioridade/equipe/dados faltantes, sinais de reincidência/reclamação; confiança baixa -> N1. Fase 1. | IMPLEMENTADO_PARCIAL. N2 consulta/cadastra/atualiza por serviços nativos; inferência NICO de conversa/intent classifier não é triagem HelpDesk. | Gatilho backend, esquema de classificação permitido, confiança, revisão humana, catálogo/unidade e R01/R10/R16. CP15A/B/E. | Campos/IDs só de catálogo autorizado; não inventa unidade; confiança baixa não aplica ação; nenhuma instrução cliente amplia permissão. |
| D2 — `A14:L14` | Contratos/comercial/cancelamento/ouvidoria/logística: sempre humano; classificar/alertar/escalar/acompanhar. Fase 1 alertas. | IMPLEMENTADO_PARCIAL. N1/N3/N11 dispõem de consulta/contexto e encaminhamento comercial/CS. | Detector/destinatários de reclamação e risco, prazo, visibilidade interna e acompanhamento; sem cancelamento/acordo automático. CP15B/E. | Humano obrigatório preservado, alerta auditado ao papel correto e sem exposição jurídica interna ao cliente. |
| E — `A15:L15` | Outros: humano/caso a caso; resposta/chamados similares autorizados. Fase 3. | IMPLEMENTADO_PARCIAL. N1 busca KB aprovada por Account; N2 lê tickets visíveis. | Recuperação de semelhantes por empresa/unidade/Account com proveniência; não criar treino global a partir de fechados. CP15D/E. | Só fontes autorizadas, explicação da similaridade e decisão humana; nada aprende/publica globalmente com dados privados. |

Registro automático de atendimentos, Fases `C6` e Resumo `A28`: ESTRUTURA_EXISTENTE. Conversa/ligação e TicketConversation já existem, mas geração idempotente de registro operacional distinto de ticket com evidência não foi comprovada. CP15D/E: não criar ticket para cada registro interno, não contar retry/mensagem como ocorrência, não inflar volume resolvido.

## Cobertura das 16 regras

Parâmetros abaixo são sugestões da fonte e permanecem sujeitos a aprovação operacional. Meta de reação não é duração de SLA. Canal ou destinatário ausente deve gerar bloqueio explícito. Fontes são linhas completas `A…:H…` da aba Regras de alerta e N2.

| Regra / fonte | Gatilho e ação transcritos em síntese | Destino / canal / reação | Status CP0, evidência e lacuna | CP / aceite decisivo |
| --- | --- | --- | --- | --- |
| R01 `A5:H5` | Mesmo cliente/defeito; novo até 14 dias do fechamento anterior **ou anterior aberto**; marcar/vincular, subir uma prioridade, anexar histórico/solução. | N2 + supervisor / Service Desk + WhatsApp / 5 min | NAO_IMPLEMENTADO como regra. N2/N11 são extensões; recorrência CS não compara defeito nem janela/estado anterior. | CP15B/E. Empresa canônica/defeito/serviço/ativo, anterior aberto, fronteira 14 dias, retry sem nova elevação nem alerta duplicado. |
| R02 `A6:H6` | 3 ou mais ocorrências do mesmo defeito em 30 dias no cliente; tarefa de causa-raiz em Projetos, CS proativo e gerente. | N2 + Thiago + CS / e-mail + WhatsApp / 15 min | NAO_IMPLEMENTADO como regra. N2 pode criar projeto/tarefa nativa; não há contagem canônica nem causa-raiz correlacionada. | CP15B/E. Não contar mensagens/retries/reabertura como tickets novos; tarefa única por evento/nível, janela e destinatários. |
| R03 `A7:H7` | 5 ou mais ocorrências do mesmo defeito em 60 dias; diretoria + reunião técnica cliente. | Diretoria + Thiago / e-mail + WhatsApp / 1 h | CONFLITO_DOCUMENTO_CODIGO / NAO_IMPLEMENTADO: Excel define 60 dias; Word bloco 15 só diz “com 5, a diretoria”. | CP15B/E. Proposta de 60 dias em rascunho, confirmação pendente; não ativar nem inventar concordância entre fontes. |
| R04 `A8:H8` | 4 clientes **distintos** no mesmo defeito em 60 min; pai/filhos, NOC/N2 e comunicado de template aprovado. | NOC/N2 + Thiago / WhatsApp + Campanhas / 10 min | NAO_IMPLEMENTADO. N1 tem rascunho/revisão de campanha, não incidente-pai nem agregação autorizada. | CP15C/E. Um cliente com quatro tickets não atinge limiar; Account/escopo autorizado, único pai, template/público aprovados. |
| R05 `A9:H9` | Atingiu 80% do prazo (`D9=0.8`); pendências para responsável/supervisor. | Responsável + supervisor / JRC/NICO / imediato | CONFLITO_DOCUMENTO_CODIGO / NAO_IMPLEMENTADO: clocks nativos existentes; não há alerta HelpDesk específico demonstrado. | CP15B/E. Política versionada de precedência 80 vs 70/90/100; sem duas séries duplicadas; processamento prioritário medido. |
| R06 `A10:H10` | SLA estourado; avisar supervisor e incluir relatório do dia. | Supervisor + Thiago / e-mail + WhatsApp / imediato | IMPLEMENTADO_PARCIAL somente sinais CS de SLA (N11); falta regra, delivery por canal, destinatário/relatório. | CP15B/E. Backend e corte temporal, novo vencimento vs backlog, idempotência por canal, sem sucesso fictício. |
| R07 `A11:H11` | Mais de 24 horas **após vencimento**; N2/gerência e plano registrado. | N2/gerência / e-mail + WhatsApp / 1 h | CONFLITO_DOCUMENTO_CODIGO / NAO_IMPLEMENTADO; horas úteis/corridas não definidas operacionalmente na fonte. | CP15B/E. Base temporal aprovada e fronteira >24; não contar desde abertura; plano e entrega reais. |
| R08 `A12:H12` | Mais de 72 horas após vencimento; diretoria e contato CS. | Diretoria + CS / e-mail + WhatsApp / 1 h | CONFLITO_DOCUMENTO_CODIGO / NAO_IMPLEMENTADO, mesmas dependências temporais. | CP15B/E. Base/fuso/calendário aprovados e >72; mudança de nível preserva evento anterior. |
| R09 `A13:H13` | Mais de 7 dias após vencimento; CEO. | CEO / WhatsApp / imediato | CONFLITO_DOCUMENTO_CODIGO / NAO_IMPLEMENTADO. Modelo compara atraso útil a 168 e o chama “7 dias”. | CP15B/E. Sete dias têm unidade explícita; nunca 168 horas úteis = sete dias corridos; ausência de papel/canal bloqueia. |
| R10 `A14:H14` | Insatisfação textual (“novamente”, “mesmo problema”, “absurdo”, “reclamação”, “cancelar”) ou nota baixa; marcar, reconhecer por comunicação autorizada, avisar CS/Thiago. | CS + Thiago / WhatsApp + e-mail / 5 min | IMPLEMENTADO_PARCIAL: N11 satisfação CS e NICO sentimento; falta flag/classificador por ticket, evidência/regra, reação/delivery/correlação. | CP15B/E. Evidência permitida; classificação separada da decisão; R15/detrator correlacionados para evitar efeitos duplicados. |
| R11 `A15:H15` | Procon, Anatel, advogado, notificação extrajudicial, processo; marcar risco jurídico e máxima prioridade. | Jurídico + Thiago + CEO / WhatsApp + e-mail / imediato | NAO_IMPLEMENTADO. NICO/CS genéricos não demonstram regra jurídica nem roteamento interno. | CP15B/E. Sem decisão jurídica automática; alerta somente interno autorizado; não elevar repetidamente em retry. |
| R12 `A16:H16` | Cliente de lista crítica aprovada abre defeito; prioridade alta e N2/gerente de conta. | N2 + CS / Service Desk + WhatsApp / 5 min | NAO_IMPLEMENTADO. N11 conta prioridades críticas de tickets; não é lista crítica de empresas aprovada. | CP15B/E. Lista explícita por Account/empresa; não inferir criticidade pelo nome/histórico Excel. |
| R13 `A17:H17` | Sem movimentação relevante por 2 dias -> responsável; 5 -> supervisor; 15 -> Thiago. | Responsável/supervisor/Thiago / JRC/NICO / imediato no limiar | NAO_IMPLEMENTADO como regra. TicketEvent/history existem; ausência de contato CS não significa ticket parado. | CP15B/E. Definir evento relevante; alertas automáticos não reiniciam inatividade; política temporal e idempotência por nível. |
| R14 `A18:H18` | Resposta negativa após encerramento/aguardando aprovação; reabrir **mesmo** ticket, preservar vínculos e contar reabertura. | Responsável original + N2 / Service Desk / 5 min | IMPLEMENTADO_PARCIAL. N10 reabre mediante regra histórica; não detecta resposta negativa nem encaminha automaticamente. | CP15B/E. Mesmo ID/número, janela/transição permitida, estado de aprovação compatível, um evento por origem/ciclo. |
| R15 `A19:H19` | Encerramento -> avaliar política compartilhada; uma pergunta WhatsApp elegível; <=6 aciona R10 só na escala NPS 0–10. | CS / WhatsApp / encerramento | IMPLEMENTADO_PARCIAL de satisfação (N11); não há envio R15 por ciclo/ticket provado. | CP13/15B/E. Um motor compartilhado, ON/OFF/frequência/canal/versão; sem pesquisa incondicional nem corte NPS aplicado a CES/CSAT. |
| R16 `A20:H20` | Sem serviço/tipo/prioridade; classificar, equipe/fila autorizadas e pedir faltantes; baixa confiança -> N1. | Fila correta / Service Desk / imediato | IMPLEMENTADO_PARCIAL como ferramentas N2; falta gatilho/classificação/limiar de confiança/handoff. | CP15B/E. IDs do escopo autorizado, sem default inventado, prompt injection não autoriza escrita. |

Cada regra requer positivo, negativo, fronteira de tempo/contagem, idempotência, concorrência pertinente, permissão negativa, canal ausente e falha externa. Nenhum desses conjuntos específicos foi executado nesta auditoria. Uma ocorrência deve ser definida separadamente de mensagem, retry e reabertura; uma mudança de nível pode criar novo evento sem apagar o anterior.

## Relatório diário

Fonte Word bloco 20 e Excel Relatório diário `A1:A2`, `A8:K19`, `A22:F30`, `A33:F37`. Status: NAO_IMPLEMENTADO como fluxo completo; N1 operational_report e N2 leitura autorizada são pontos de apoio, N12 não demonstra job às 18h.

CP15B/E deve oferecer configuração real por Account: papel destinatário, escopo de empresa/unidade, horário/fuso, e-mail/WhatsApp habilitados, template/versão, ativação OFF inicial, período/corte, prévia/teste controlado e histórico. Não adivinhar pessoa/telefone/e-mail/ID a partir de “Thiago”. Sem destino/canal válido, BLOQUEADO_DEPENDENCIA. Persistir delivery independente por Account/escopo/data/destinatário/canal; e-mail confirmado não é reenviado quando WhatsApp falhar. Timeout externo pode ter resultado desconhecido e deve ser conciliado antes de retry.

Conteúdo: (1) tickets, cliente, serviço, tipo, responsável, status, meta/prazo, atraso/unidade e nível; (2) reclamações/riscos com evidência autorizada e ação/responsável; (3) reincidência/N2/causa-raiz; (4) massa com abrangência permitida; (5) autonomia NICO, confirmação cliente, participação humana, falhas/escalonamentos, denominadores. Separar novo vencimento do dia de backlog, preservando tickets antigos e data/hora de corte. Risco urgente não espera 18h. Nenhum dos nomes, números de ticket ou trechos históricos do modelo deve ser fixture pública ou dado operacional.

## Sete KPIs

Fonte Fases e KPIs `A10:D16`. `B10:B16` são histórico do período e não podem preencher coluna atual. Todos são NAO_IMPLEMENTADO como KPI específico; N12 KpiCounts fornece somente distribuição por fase/status. Fórmulas abaixo são critérios de implementação propostos, que exigem definir janela/população, ciclo, origem e política temporal antes da ativação.

| ID / fonte | Métrica e referência de meta | Fórmula/população a definir e prova necessária | Dependência / CP |
| --- | --- | --- | --- |
| K1 `A10:D10` | Resolvidos NICO sem humano; 15% na Fase 2 | Resoluções verificadas atribuíveis ao NICO sem participação humana / total de resoluções da mesma população/janela. Decidir resolved vs closed e ciclos. Ações executadas e sugestão aceita por humano não contam como resolução autônoma. | Proveniência de execução/resolução, confirmação cliente e intervenção humana. CP15C/E. |
| K2 `A11:D11` | Defeitos que reabrem em 14 dias; <10% | Defeitos da coorte de fechamento com reabertura válida em até 14 dias / defeitos elegíveis da coorte. Janela de observação completa ou indicar coorte ainda aberta; deduplicar ciclos. R01 detecta reincidência além de reabertura, não substituir definição silenciosamente. | Datas, fechamento anterior, mesma ocorrência vs ticket novo, regra de coorte. CP15E. |
| K3 `A12:D12` | Fechados acima de 72h; <10% | Tickets fechados da janela com duração >72 na base temporal aprovada / tickets fechados elegíveis. Informar horas úteis/corridas, pausas e ciclo. | Clock/snapshot histórico e definição temporal. CP12/15E. |
| K4 `A13:D13` | Vencidos avisados antes do vencimento; 100% | Tickets vencidos elegíveis com aviso R05 comprovado anterior ao deadline / tickets vencidos elegíveis da janela. Persistir provider/status e timestamp, sem considerar só tentativa/queued como entrega. | R05, deadline e recibos canal. CP15B/E. |
| K5 `A14:D14` | Reincidência até N2; <=5 min | Duração entre detecção/evento autorizado e recebimento/atribuição N2 comprovados; apresentar distribuição e percentual no alvo. Definir estatística de comparação da meta. | R01, fila de processamento, N2 configurado e timestamps. CP15B/E. |
| K6 `A15:D15` | Reclamações avisadas até 5 min; 100% | Reclamações elegíveis com aviso comprovado ao papel configurado em <=5 min / reclamações elegíveis na janela. Falhas/desconhecido separados; correlação R10/R15. | R10 e delivery real, escopo destinatário. CP15B/E. |
| K7 `A16:D16` | Pesquisa; 20% dos fechados | Pesquisas elegíveis, enviadas e respondidas como contagens/razões distintas sobre coorte de tickets fechados correspondente. Definir qual indicador recebe a meta sem impor amostragem ao motor compartilhado. | Política/versionamento/origem/ciclo/canal de pesquisa. CP5/13/15E. |

Todos precisam unidade, fórmula, denominador, janela, origem, filtro autorizado e meta administrável. Denominador inexistente ou indisponível é `sem dados`/indisponível, não 0% saudável. Medir fila/latência/tentativas/falhas separadamente do sucesso de regra/resolução.

## Conflitos e decisões pendentes

| ID | Fontes/localizadores | Decisão necessária e tratamento recomendado |
| --- | --- | --- |
| C-NICO-01 | Service Desk V2 seção 7, `servicedesk-source.txt:160`, e exemplos `:295`/`:296`/`:297` usam 70/90/100%; NICO Regras `C9/D9`, Word bloco 17 usam 80%. | Política versionada por escopo com precedência explícita. Rascunho separado, OFF. Não trocar contrato existente nem disparar as duas séries duplicadamente. Operations/backoffice tem 50/75/90/100 (`sla_clock.rb:80`), domínio distinto que não deve ser reutilizado como SLA HelpDesk. |
| C-NICO-02 | Relatório `A5:B6` = 8/24h úteis; `G9/H9/I9` rotulam útil; `J10:J18` e `K10:K18` comparam atraso útil a 24/72/168 e rotulam 168 “7 dias”; regras `C11:D13` e Word bloco 17 falam 24/72h e 7 dias. | Definir base temporal por regra (business_hours/elapsed_hours/days), fuso/calendário/pausas e contagem depois do vencimento. Até aprovação, ativação temporal ambígua pendente. Não converter 168h úteis em sete dias corridos. |
| C-NICO-03 | R03 `C7/D7` = 5 ocorrências/60 dias; Word bloco 15 “com 5, a diretoria” sem janela. | Registrar 60 dias como sugestão estruturada em rascunho e pedir confirmação operacional; não afirmar que Word diz 30/60 dias. |
| C-NICO-04 | R15 `E19` manda uma pergunta/<=6; Fases `C16` meta 20%; prompt exige política compartilhada ON/OFF e escala NPS. | Encerramento avalia elegibilidade; <=6 só para NPS 0–10; distinguir elegível/enviado/respondido. Meta não concede permissão de envio nem altera frequência/amostragem. |
| C-NICO-05 | Resumo `A2/A26:A29`, Catálogo `A2/D5:F15`, Diário `A2/B4/A10:K37`, Fases `B10:B16`; Word blocos 6/13/16/20. | Estimativas/histórico de 01/04 a 07/10/2026. Não importar clientes/tickets/frases, não aplicar metas retroativamente, não alegar 45% automatizado ou 6/9 atuais. |
| C-NICO-06 | Fases `A42`: decisões registradas e opção de desfazer. | Compensação por capacidade verificável; envio WhatsApp/e-mail não pode ser prometido desfeito. Registrar correção/limite irreversível e estado desconhecido pós-timeout. |
| C-NICO-07 | Catálogo `H15` “aprende com os fechados”, Fases `D6`; prompt preserva Account e proíbe treino global automático. | Recuperação autorizada com proveniência, decisão de aprendizado adicional pendente; nenhum treino/globalização de conteúdo privado. |
| C-NICO-08 | R07/R08 “mais de” vs `C11/C12` “24/72 horas após”; R14 `C18` inclui aguardando aprovação e lifecycle atual só permite regras publicadas. | Operadores/fronteiras explícitos e testes; reabertura somente transição permitida no mesmo ticket. Não forçar regra histórica nem criar duplicata. |

## Dependências externas e sequência de implementação

1. CP15A: estender o executor/políticas/catálogos existentes com definição versionada e OFF inicial, identidade/empresa/unidade/Account, lista piloto, limites por hora, aprovação atrelada a payload/escopo/prazo, revogação/revalidação, auditoria e resultado desconhecido. Não usar texto de documento/LLM como autorização. Preservar N8 e N5.
2. CP15B: regras determinísticas/triagem/relatório em jobs backend com eventos e persistência idempotentes, destinação por papel configurado e estado por canal. A1/A2/A3 só terão contratos/adaptadores indisponíveis enquanto faltarem APIs; demais partes independentes prosseguem.
3. CP15C: C2 pode reutilizar Health/pair/operações/grants do Broker. A4/B1/B2 exigem documentação e APIs reais PABX/URA/filas/provisionamento. R04 precisa relação pai/filhos e agregação de clientes canônicos autorizados, aprovação de template/público e proteção de Account.
4. CP15D: diagnóstico voz/registro automático/E com contexto autorizado e APIs disponíveis; não liberar fase só porque código existe. Prazos 30/60–90/90–120 dias são roadmap, não espera artificial nem promessa de homologação.
5. CP15E/16: cobertura de todas as regras/KPIs, testes e falhas externas; comunicação real/ativação continua fora desta rodada.

APIs/documentação não fornecidas/não demonstradas no cliente atual: Billing de segunda via/débito; usuários/reset/OTP PABX; Reporter/consulta/gravações; publicação URA/áudio/calendário/restauração; ramais/troncos/status/provisionamento; desbloqueio IP; planos/limites. Também faltam configurações reais de destinatários/papéis N2, N1, CS, NOC, gerente, Thiago, diretoria, jurídico, CEO e templates/canais autorizados. Não inferir valores a partir do Excel. Configuração real e teste de provider não foram consultados; código de Broker disponível não prova integração operacional conectada.

## Estado deste subtrabalho

`CP0_NICO=CONCLUIDO_LEITURA_E_MATRIZ`

`VALIDACAO=INSPECAO_E_CONFERENCIA_ARITMETICA_DE_FONTES; TESTES_FUNCIONAIS_NAO_EXECUTADOS`

`CODE_CHANGED=NAO; GIT_CHANGED=NAO; RUNTIME_CHANGED=NAO; COMPOSE_CHANGED=NAO; MIGRATIONS_CHANGED=NAO; REAL_MESSAGES_SENT=NAO; REAL_CUSTOMERS_ACTIVATED=NAO`

Próximo passo exato: consolidar esta matriz no inventário integrado e os conflitos/dependências nos documentos de continuidade; após confirmar base/worktree, iniciar CP15A pelos pontos de extensão existentes, com todas as políticas novas desativadas e provas negativas de tenant/identidade/aprovação.



## R345 — checkpoint funcional R3 (fotografia r3-checkpoint)

Continuidade: branch `codex/relacionamento-servicedesk-v2-20261008`, HEAD
`4ce8241d35ce862e9d53e9a5dce4df9a1858432c`; baseline acumulada R1+R2 mantida.
Nenhum commit, push, merge, envio real, ativação de automação, imagem ou deploy.
Fotografia congelada: 479 arquivos, hashes conferidos 479/479; arquivo externo
`r345-r3-checkpoint-overlay.tar`, SHA-256
`f955e6e1f431ac2649bddd1eeae802e4142857816a5a8a93905295b9217a2131`.
Validação PostgreSQL exclusiva em `jrc_rel_sd_r345_r3_retry_test` (clone descartável).
As alterações de qualidade posteriores exigem nova validação; este registro não
as declara aprovadas. R4 e R5 prosseguem automaticamente no mesmo workspace.

| Requisito R3 | Situação do checkpoint | Evidência/limite |
|---|---|---|
| SLA/OLA/atendimento, pausas e violações | IMPLEMENTADO_E_VALIDADO_LOCALMENTE | Relógios e histórico persistidos; avaliação explícita autorizada, sem scheduler operacional ativado |
| Tipos, subcategorias, campos e defaults | IMPLEMENTADO_E_VALIDADO_LOCALMENTE | Catálogo versionado, contratos CRM canônicos, autorização atual e releitura |
| Abertura com anexos | IMPLEMENTADO_E_VALIDADO_LOCALMENTE | Upload real, checksum e GET da nota/anexos; replay idempotente e envelope conflitante 409 |
| Aprovação por equipe/papel, tarefas/subtarefas | IMPLEMENTADO_E_VALIDADO_LOCALMENTE | Efeitos e progressão só com política válida e grants atuais |
| Problems/Changes/Assets | IMPLEMENTADO_E_VALIDADO_LOCALMENTE | Recursos nativos, vínculos, filtros, histórico e autorização |
| Portal, conhecimento, histórico/SLA/pesquisas | IMPLEMENTADO_E_VALIDADO_LOCALMENTE | Identidade ContactInbox, contrato e retenção atuais; nenhuma interação interna exposta |
| Política por evento/tipo/serviço e preferências | IMPLEMENTADO_E_VALIDADO_LOCALMENTE | Escopo preciso, opt-out e auditoria; não houve entrega externa |
| Entrega externa e homologação de providers | IMPLEMENTADO_COM_HOMOLOGACAO_EXTERNA_PENDENTE | Testes não enviam mensagens reais |
| Concorrência completa R345, UI visual e build final | TESTE_LOCAL_PENDENTE | Gates cruzados após R4/R5; resultados R2 permanecem históricos |
| Qualidade final RuboCop/ESLint | TESTE_LOCAL_PENDENTE | Não declarar aprovado nesta fotografia |


## R345 — retomada após interrupção de créditos (retomada-creditos-1)

Workspace e histórico preservados: `C:\Users\DEV03\Documents\Jrc\relacionamento-servicedesk-v2-20261008`, branch `codex/relacionamento-servicedesk-v2-20261008`, HEAD
`4ce8241d35ce862e9d53e9a5dce4df9a1858432c` e origin exclusivo `ClaudioHideki/jrc-conversas-lab2`.
Os 404 paths acumulados R1+R2 continuam presentes, assim como os 506 paths da
fotografia de recuperação, inclusive os arquivos modificados antes da interrupção.
Referência b2001cb permanece ancestral. Estado exato salvo externamente em
`r345-retomada-creditos-git-status.txt`: 136 modificados,
370 untracked, zero staged e zero removidos versionados.
Arquivo externo `r345-retomada-creditos-1-overlay.tar`, SHA-256
`929e2aea8ba684411f84868db76ffebd2859815e0abcf0a628f7d212e1c63772`. Não foi aplicado reset, clean, restauração ou descarte.

R3 funcional: 56/56 direcionados; integração 578 = 567 aprovados, uma falha
histórica CP5, dez pendentes de concorrência dedicada. Alterações posteriores
de qualidade continuam exigindo repetição dos gates afetados.
R4: implementação local e 38 testes JS direcionados existentes; gate PostgreSQL
`r345-r4-targeted-2.json` terminou com 108 exemplos, 92 aprovados e 16 falhas:
cinco fixtures de contrato sem pedido nativo, dez bootstraps externos WhatsApp
bloqueados pelo WebMock e um fixture com travel_to aninhado. Não chamar esse
gate de aprovado. Correções dirigidas em andamento, sem remover assertions,
relaxar timeouts ou liberar conexões externas.
R5: auditoria/matriz/desenho de grupos, R01–R16, K1–K7 e diário já preservados;
implementação adicional inicia após checkpoint funcional R4. Nada da R1/R2
deve ser refeito. Gates finais: Ruby/JS/preservação/concorrência/boot/build/lint,
autorização/tenant e Vue→API real→PostgreSQL, ainda pendentes desta fotografia.

Revisão automática recusou exclusivamente a leitura Docker do log R4 e a cópia
da atribuição de lint porque os créditos acabaram; não classificou as ações como
inseguras. Após a retomada, as cópias originais foram concluídas pela revisão
normal, sem contornar o controle. Scripts/classes e fontes congeladas preservados.
Comparador externo de lint: dez selftests aprovados; prova AST de fixtures Flow:
23 exemplos integralmente preservados; prova catálogo R3: 57 assertions antigas
mantidas, 58 atuais. RuboCop R3 qualidade2: 306 ocorrências/93 paths; atribuição
conservadora 95 históricas comprovadas e 211 novas/ou não atribuídas. Não declarar
lint aprovado nem inferir herança somente por contagem. pause_waiting explícito
permanece sem default false. Continuar qualidade pontual e registrar impedimentos.

Automação nova OFF. Nenhum commit/push/merge, imagem, deploy, mensagem real,
alteração de dados reais, Compose ou Runtime. Migrations somente em clones
locais descartáveis autorizados; nenhuma em servidor.


## R345 — checkpoint dirigido R4 (targeted-4)

Fonte congelada `/r345-r4-targeted4-candidate`, 506/506 hashes conferidos.
Arquivo externo `r345-r4-targeted-4-overlay.tar`, SHA-256
`537fad0170216551f7f9c1ca3591ea1f39746344c5d9a665a6a0e1add7866e91`;
manifesto `b94d22eb6ee27ef9f2f160ffd7de6d548229581302ebec696e133a209efb01f4`.
R4 e preservação dirigida R3: **114 exemplos, 114 aprovados, zero falhas,
zero pending e zero erros externos aos exemplos**, em 303 segundos.
As rodadas anteriores com falhas permanecem evidência histórica de tentativas,
não aprovação; este resultado substitui seu estado corrente para os seletores
dirigidos. Nenhuma soma com a suíte ampla ou JS para inflar cobertura.

Correção objetiva descoberta pelo teste: SurveyDispatchJob após rollback tinha
lock_version desatualizado e falhava ao registrar o bloqueio. O rescue agora
relê e bloqueia a pesquisa, preservando resposta/entrega concorrente. Foram
mantidas as validações nativas de renovação e os bloqueios de provider; fixtures
reutilizam a cadeia real proposta → pedido → Backoffice → contrato assinado.
Prova Flow AST corrigida: 45 + 28 + 12 expectations preservadas; controles
rejeitam valor alterado, expectativa removida e inventário vazio. A prova antiga
de inventário vazio foi explicitamente rejeitada e não serve de aprovação.

Regressão ampliada R4 em execução, exclusivamente no PostgreSQL descartável
`jrc_rel_sd_r345_preservation_test`. R5 em implementação independente no mesmo
workspace; suas alterações não entraram nesta fotografia R4. Nenhum commit,
push, merge, publicação, deploy, mensagem real ou migration em servidor.
HEAD/branch/origin permanecem os autorizados. Automação nova OFF por padrão.

R4: indicadores/denominadores e renovação canônica, CES publicado com direção,
QR real do link assinado, preparação de voz com o mesmo parser e template Meta
oficial com revalidação na fronteira do provider estão validados neste gate.
Matriz de 18 áreas: `r4-native-coverage-matrix.md` externo; homologação de URA,
APIs de reunião e providers reais continua dependência, não sucesso simulado.
Flow privado reutiliza Runner, aprovação e journal nativos, sem segundo motor.


## R345 — fotografia final-4 e validação integrada em andamento

Continuidade da execução autorizada: branch codex/relacionamento-servicedesk-v2-20261008,
HEAD 4ce8241d35ce862e9d53e9a5dce4df9a1858432c e origin exclusivo lab2.
Não reiniciar R1/R2 nem descartar o overlay acumulado. Foto final-4: 558 arquivos,
558/558 hashes conferidos em /r345-final-4-candidate. Arquivo externo
r345-final-4-overlay.tar SHA256 363029c9b1b77d13f08a45bdad1f02efd776ab93c5d4d35b84703e58a2625e0c;
manifesto SHA256 7c0ebd18ba2027a2966b853f7ceacd822c433c37f3d68127dc5f364ba7952d5d.
O b2001cb continua ancestral; 157 arquivos e 8 migrations históricas intactos;
todos os 404 caminhos iniciais preservados, sem staged/deletion/protected changes.
Prova externa r345-preservation-target3.json, sem formas de secrets detectadas.

R4/Agenda dirigidos: 127/127 passaram após o reparo do fixture UTC/local;
JS completo final: 669/669 passaram (52 arquivos). R5 target3: 350 exemplos,
6 falhas corrigidas objetivamente e 21 testes de concorrência opt-in não executados
naquela rodada. A correção ainda depende do reteste final-4, não de declaração.
Concorrência target3: 42/43 passaram, um timeout Flow sem alteração de limites;
repetição isolada dos dois testes desse arquivo passou 2/2. Rodada completa final pendente.

Preservação target3: 243 exemplos, 236 aprovados e 7 falhas. Seis têm as exceções
históricas R2; a adicional ProjectPlanning [1:9] foi reproduzida na R2 congelada:
Date.current fora em UTC versus dentro da requisição em São Paulo. Quatro blobs
do módulo e as assertions continuam idênticos. Não houve alteração em Projetos.
IDs sintéticos variam na mensagem; prova estrutural por ocorrência em
r45-project-planning-date-attribution-final.json, sem afirmar igualdade textual falsa.

Build1 passou em 2m24 antes da revisão de layout. Build2 após layout falhou por OOM
do processo/esbuild sob testes concorrentes. Repetir serialmente o mesmo comando;
não corrigir código, memória do Docker/WSL ou limites de teste para mascarar o evento.
RuboCop target3: 1258 infrações em 412 arquivos, baseline mesma seleção 890 em 325;
552 históricas comprovadas e 706 novas ou sem atribuição suficiente na comparação
conservadora. Esses valores não são o lint final e não representam aprovação.
Layout de 33 + 8 + 12 arquivos foi importado somente com hashes prévios e AST Ruby
inteira idêntica. Nenhuma assertion, guard, string ou contrato foi removido para lint.
ESLint final: 224 erros existentes; zero novos sem prova individual; 26 ocorrências
reformatadas comprovadas por AST idêntica e origem exata. 83 warnings novos/alterados
permanecem dívida documentada, sem suppression ou mudança de configuração.

Correções R5 confirmadas: filtros Parameters.each_pair e retorno vazio explícito;
Contact é lido pelo access.contact nativo no manifesto de recibo; R15 preserva
survey_id canônico, SurveyDecision e ciclo; halt usa Controls e versão publicada
imutável; retry otimista usa a mesma OperatorSession/Command nativa; foreign Broker
fixture cria Integration do mesmo Account. Não houve handlers/ACL permissivos.
K1 não inventa autonomia; K3/C10 não escolhe regra de negócio e exibe observações
reais separadas; recibo de e-mail tem claim COMMIT, transporte :test e nunca confunde
aceitação com entrega. Nova migration 180000 é aditiva; nenhuma histórica alterada.

Continuar sem nova autorização: reteste final-4, concorrência opt-in final,
Ruby integrado + preservação, boot/eager-load, PostgreSQL/schema, build serial,
lint final, browser real Vue/API/PG e relatório por categorias. Não fazer commit,
push, merge, imagem, deploy, migration em servidor, dados/mensagens reais ou ativação.

Matrizes externas atuais: r4-native-coverage-matrix.md (18 áreas), r345-r5-native-tasks-groups-ledger.md e r345-r5-rules-native-chain-ledger.md. A presença de um menu não prova integração externa.


## R345 — complementos nativos e revisão de cobertura após final-7

HEAD/branch continuam 4ce8241d35ce862e9d53e9a5dce4df9a1858432c / codex/relacionamento-servicedesk-v2-20261008, sem stage/commit/push.
Os checkpoints anteriores são evidência histórica, não uma aprovação final da fonte atual.
Final-6 (585 caminhos): concorrência real COMMIT 61 exemplos, 60 passaram, 1 assertion de contrato errada no novo teste do teto de steps. O transporte da etapa já debitada, recibo response_received, POST único, steps=2 e ausência de efeito posterior passaram. O Runner nativo retorna failed/playbook_flow_execution_failed, e o teste foi alinhado ao contrato existente, sem alterar limite/assertions de efeitos.
Final-7: complemento local 61 exemplos, 60 passaram, 1 fixture de pesquisa tentou abrir link no estado scheduled. O link é corretamente rejeitado. O teste agora confirma 422 nesse estado e prepara available pela validação nativa antes de testar 200 e posterior rejeição de cache Meta ausente. Reteste final pendente.
MRR dirigido 12/12 aprovado; ações nativas HelpDesk/Flow dirigidas 57/57 aprovadas. Não representam aprovação dos últimos complementos ainda em desenvolvimento.
CS16 opcional usa a estrutura Meta oficial, valida template APPROVED, inbox/Account/WABA, executor, consentimento e substituição do marcador de URL assinada no backend. Automação segue OFF por padrão. Sem seletor/parser paralelo, mensagens reais ou conexão com provider externo.
Revisão de cobertura identificou lacunas locais adicionais: registro de snapshot SLA sem endpoint/editor; menu automações com placeholder e avaliação explícita sem scheduler; contratos/pesquisas extras em placeholder apesar dos módulos nativos existentes. Estão em conclusão dentro do escopo autorizado: POST/GET de snapshot append-only com ACL distinta para condições, editor finito, Job de relógio com opt-in automático/executor explícito e reaproveitamento de telas nativas com Unit/Account/permissões atuais.
Snapshot histórico NÃO é cálculo automático de SLA por contrato. Recatalogação de Ticket.service_id imutável, mapeamento contratual estruturado, fórmulas comerciais não definidas, cohorts de campanha e integrações externas sem contrato/credencial continuam explícitos na matriz, sem implementação fictícia.
Build1 passou antes dos últimos complementos. Build3 serial falhou por VirtualAlloc/esbuild errno1455, condição de memória local; tentativa final isolada usará somente orçamento do processo Node/GOMAXPROCS, sem alterar máquina/WSL/Docker/dependências/configuração.
RuboCop final-5: 995 infrações, 501 históricas comprovadas e 494 novas ou sem atribuição suficiente. Não declarar lint aprovado. Full gates serão repetidos em fotografia nova após freeze de todos os complementos.
Nenhuma migration em servidor, dado real, mensagem real, ativação de cliente, imagem ou deploy. PostgreSQL usado somente nas quatro cópias descartáveis locais já autorizadas. pause_waiting permanece boolean explícito sem default.

Matrizes: r45-cs12-cs16-completion-ledger.md, r5-final-requirements-matrix.md; matriz R3 em atualização. Os menus extras só devem ser chamados funcionais após testes de API/UI e permissões.


## R345 — retomada dirigida aprovada e gates finais em execução

O workspace autorizado permanece na branch `codex/relacionamento-servicedesk-v2-20261008`, HEAD `4ce8241d35ce862e9d53e9a5dce4df9a1858432c`. A baseline é o acumulado R1/R2, nunca apenas o HEAD. A prova `r345-resume-preservation-6.json` mantém todos os 404 caminhos iniciais e os 157 caminhos da referência; oito migrations históricas permanecem com conteúdo canônico idêntico. Nesse instante: 151 modificados, 468 novos, zero staged/deletados/arquivos protegidos/secrets detectados, `diff --check` limpo. Alterações posteriores exigem a prova final.

Fotografia `r345-final-9`: 610 caminhos congelados, todos conferidos por SHA-256 na cópia local de testes. Gate `r345-final-9-complements.json`: **123 exemplos, 123 aprovados, zero falhas/pending**. Inclui 14 casos de monitoramento SLA/OLA nativo, 20 snapshots HTTP, 10 projeções de autorização, regras Meta/legado, MRR observado, mediana e scheduler. As três fixtures Clock incorretas foram corrigidas sem modificar produção; `config/schedule.yml` preserva conteúdo funcional e usa LF para o parser histórico. A aprovação dirigida não substitui a suíte integrada final.

R3/R4: editor explícito de snapshot→POST→GET/digest/version, monitoramento publicado com executor e guardas atuais, automações OFF e reuso restrito dos contratos/pesquisas nativos estão comprovados localmente no gate acima. Navegador segue pendente: Browser8 falhou no bootstrap descartável por atributo `company=` inexistente; Browser9 corrigiu somente a fixture para `company_id`. Primeiro cenário visual apontou overflow com chaves de paginação não traduzidas no harness; a tradução oficial foi incorporada somente no harness ignorado, antes de atribuir regressão à aplicação. Reexecução na mesma fixture encontrou 409 legítimo de nome de política duplicado; nova conta sintética foi criada sem apagar dados/provas anteriores.

R5: os adaptadores finitos de rascunho de campanha do incidente exato e conhecimento privado/revisado pelo humano estão em fechamento com testes nativos. A revisão confirmou reconstrução das fontes após locks e preservação da sessão sem ampliar o reader global de conhecimento aprovado. Também está sendo completado o e-mail imediato de Event, reutilizando a cadeia diária/receipt/claim/ActionMailer já existente, apenas nas regras/canais/papéis explicitamente documentados. Nenhum deles é declarado integralmente aprovado antes do gate atual correspondente. Chaves EN dos novos campos foram compiladas sem erro; não houve mudança em outras traduções.

Continuam pendentes a fotografia final, Ruby integrado/preservação/concorrência com COMMIT e webhook opt-in explícito, JS/ESLint completo, RuboCop com atribuição conservadora, boot/schema e build de produção isolado. O build anterior falhou por memória/VirtualAlloc; a próxima tentativa limita somente o processo, sem instalar recursos ou alterar máquina/WSL/dependências. RuboCop não está aprovado no checkpoint anterior; infrações novas ou sem prova histórica não serão reclassificadas como antigas sem evidência.

Nenhum commit, push, merge, imagem, deploy, Compose/Runtime/secrets, migration de servidor, mensagem real ou ativação em cliente foi realizado. As cópias PostgreSQL e contas sintéticas são exclusivamente descartáveis locais. A continuação entre R3/R4/R5 permanece autorizada sem nova aprovação. Decisões de negócio e contratos externos ausentes permanecem separados das lacunas e validações locais; não se presume conclusão apenas pela existência de menu ou mock.


## R345 — bloqueio ambiental final (2026-10-09)

C: livre=0; Docker Read-only filesystem/API500. Copia final11 incompleta: nao usar.
JS: 60 arquivos/759 PASS; exit1 no JsonReporter por ENOSPC. ESLint final ENOSPC.
Ruby integrado/COMMIT sem resultado recuperavel. Preservacao final10:237 PASS/6
falhas R2; complementos final9:123 PASS; Snapshot UI:40 PASS. Boot/eager/schema
local aprovados. Build, RuboCop, browser, isolados e 27 requests R04/E+18 Event
email ainda pendentes. Estado:152 modificados+468 novos,0 removidos/staged.
HEAD/branch autorizados mantidos; politicas OFF. Nenhum commit/push/imagem/deploy,
Compose/Runtime ou migration de servidor. Nao refazer R1/R2 nem limpar dados.
Retomar gates somente apos restabelecer espaco/ambiente local e verificar fonte.

ESLint em memoria:219 erros (207 historicos;12 novos/nao atribuidos),580 warnings;143 novos/alterados. Nao aprovado; detalhes em TESTES_E_EVIDENCIAS.md.
Atual:214 historicos;5 novos.


## R345 — fechamento local da retomada e bloqueios remanescentes (2026-10-09)

Retomada executada sobre o estado acumulado R1/R2, sem reiniciar o projeto. Repositório `ClaudioHideki/jrc-conversas-lab2`; workspace `C:/Users/DEV03/Documents/Jrc/relacionamento-servicedesk-v2-20261008`; branch `codex/relacionamento-servicedesk-v2-20261008`; HEAD `4ce8241d35ce862e9d53e9a5dce4df9a1858432c`, inalterado. Origin exclusivo desse repositório.

Estado preservado: **152 arquivos tracked modificados + 468 untracked = 620 caminhos; zero staged e zero removidos**. Todos os 404 caminhos do estado inicial permanecem presentes/não vazios. A referência `b2001cb40ebe1eb1e8f3a97e1559b901199adf71` continua ancestral; os 157 arquivos anteriormente ausentes estão presentes e as oito migrations históricas mantêm conteúdo canônico idêntico. Há nove migrations candidatas novas e sete helpers de migration, apenas locais. `pause_waiting` permanece boolean obrigatório, NOT NULL, sem default.

**STATUS: BLOQUEADO PARA CONCLUSÃO INTEGRAL / NÃO APROVADO PARA COMMIT OU PUBLICAÇÃO.** JavaScript atual aprovado e sem erros novos de ESLint não substituem os gates Ruby/PostgreSQL/navegador/RuboCop e as lacunas R3. O C: recuperou externamente aproximadamente 2 GB após ENOSPC, sem limpeza feita nesta tarefa; Docker continuou sem resposta, após filesystem somente leitura/API 500. A cópia `/r345-final-11-candidate` é incompleta e NÃO pode ser usada como fonte válida.

Nenhum commit, push, merge, imagem ou deploy. Compose, Runtime, Broker, workflows, lockfiles, arquivos .env e configuração dos provedores de IA por Account não foram alterados. Nenhuma migration em servidor, dado/mensagem real ou ativação em cliente. Novas automações seguem OFF por padrão. Histórico dos cinco documentos mantido integralmente; este apêndice retifica estados anteriores sem apagá-los.

Frontend atual: **759/759 testes JavaScript e build de produção APROVADOS; zero erros novos de ESLint**. Build5 exit0 em 2m02s, Node limitado a 4096 MB e GOMAXPROCS=2 somente no processo; 171 fontes seladas inalteradas. A tentativa build4 anterior falhou no limite 3072 MB sem alterar fonte. Não houve mudança de infraestrutura ou configuração do projeto.

### Inventário e cobertura preservada

O estado inicial de 404 caminhos inclui os arquivos da execução interrompida; nenhuma fonte inicial foi descartada. A lista exata do estado atual, status e hashes será registrada em `r345-final-source-manifest-1.json` no diretório externo de auditoria. O inventário por grupo continua: 338 backend, 163 frontend, 94 testes, 16 migrations/helpers, cinco documentos e quatro configurações. Arquivos externos de evidência não são runtime nem entram no Git.

R3 implementado no núcleo nativo: três relógios SLA/OLA/calendários, tarefas/aprovações, catálogo/formulários, recursos, portal, KB, notificações/visibilidade, monitoramento automático com executor explícito, tela de automações e snapshots POST/GET. Contratos e pesquisas reutilizam módulos existentes com Account/Unit/permissões atuais. Não equivale a conclusão de todos os requisitos.

R4 cobre localmente as 18 áreas nativas: visão geral, carteira, ações, saúde/CES, riscos, planos, QBR, renovação, expansão, pesquisas, playbooks/FlowRunner, métricas/MRR, configuração, handoff, Customer360, pós-atendimento/Meta, respostas e agenda/reuniões. A matriz externa `r4-native-coverage-matrix.md` distingue implementação, gates dirigidos, mock e homologação externa.

R5 possui grupos A1–A4/B1–B2/C1–C2/D1–D2/E, regras R01–R16, indicadores K1–K7 e diário de 18h no motor nativo. R04 Campaign draft e E KB privada revisada não disparam campanhas nem publicam conhecimento; Event email reutiliza claim/receipt/ActionMailer. Backend desses complementos ainda não aprovado integralmente.

Último lote de cinco correções ESLint modificou apenas quatro paths SD: clockAutomation.spec.js (inteiro inseguro preservado via MAX_SAFE_INTEGER+1), ConfigurationV2Fields.spec.js (formatação), TicketDetailView.vue (return undefined), TicketDetailPublication.spec.js (map/Promise.all). A prova `r45-final12-five-errors-proof.json` preserva as 160 cadeias expect e os contratos. Fix anterior de confirmação Snapshot evita GET duplicado/perda de recibo e verifica digest autorizado no componente pai.


## CHECKPOINT ADITIVO CHATGPT-20261009-C1 - candidato, sem publicacao

Esta secao e posterior ao pacote de continuidade de 09/10/2026. Os resultados
anteriores do Codex sao evidencias recebidas, NAO execucoes realizadas neste ambiente.
O ZIP original, os 620 hashes do candidato e os 10.972 arquivos do manifesto foram
conferidos antes das edicoes. Nao ha .git: repositorio, branch, HEAD e ancestralidade
continuam METADADOS DECLARADOS, nao verificacoes Git locais.

A continuacao modificou somente o codigo presente no pacote completo, sem restaurar
um HEAD antigo. Os arquivos da referencia continuam presentes. Migrations existentes,
Compose, Runtime, Broker, lockfiles, provedores por Account e SafeLogger nao foram
alterados. pause_waiting conserva seu contrato obrigatorio sem default.

Estado: CANDIDATO_COM_COMPLEMENTOS_R3_VALIDACAO_NATIVA_PENDENTE.
Sem commit/push/merge/imagem/deploy, sem migration em servidor e sem comunicacao real.
Esta rodada NAO aprova R3/R4/R5 integralmente nem substitui os gates pendentes.

### Matriz do delta C1

| Lacuna recebida | Implementacao no codigo | Aceite ainda necessario |
|---|---|---|
| Portal por numero | TicketSearch + Widget controller + rotulo EN | Request Rails e widget autenticado |
| Canal/inbox -> fila | OperationalRuleVersion/Contract/Matcher + IntakeRuleApplication + editor e controles de abertura | FK/ACL/concorrrencia real e Vue -> API -> PG |
| Prazo de aprovacao | ApprovalDeadlineJob/Execution + politica versionada + recibo unico + escalonador nativo | Execucao agendada, concorrencia e revogacao em PG |
| Relatorios/export | OperationalReportQuery/Metrics/Csv + API + painel | SQL, numeros/coorte, CSV, permissao e auditoria Rails |
| Recorrencia/lotes | RecurrenceGrouping/Projection + IncidentBatchService + painel | Preview/replay/versao/ACL/releitura transacional |
| Impacto x urgencia | Predicados e prioridade explicitamente publicada + editor + entrada | Mapeamento aprovado e recusas no backend |
| Selecao SLA/calendario | Predicados/digest/proveniencia/snapshot nativo | Validar calendario real e inicio pelo ciclo de vida nativo |

As duas primeiras regras de selecao nao ampliam acesso a Inbox/Company/Unit. As
condicoes automaticas de SLA exigem as capacidades nativas de registrar snapshot e
ler condicoes. Nao foi criado administrador ou executor implicito para contornar isso.

R4 e R5: implementacoes anteriores preservadas. Nao foram reescritos os 11 grupos,
16 regras ou sete KPIs; os requests Campaign/Knowledge, Event email e Daily email
continuam SEM nova aprovacao neste ambiente. Os testes anteriores fullJS5/build5
nao certificam os arquivos frontend alterados nesta continuacao.

Os paineis novos usam identificadores explicitos dos cadastros existentes. Nao
inventam opcoes, pesos ou destinos. Validacao nativa e refinamento de experiencia
visual permanecem exigidos antes da liberacao; nao foi executado compilador Vue aqui.


## CODEX-20261009-C1-VALIDACAO-DIRIGIDA

PACOTE_SHA256=dc2fe084a9725831476fa58513ba266a53d2451a30842dae37bbbf51a9dbeecc
ORIGIN_BRANCH_HEAD_CONFIRMADOS=ClaudioHideki/jrc-conversas-lab2; codex/relacionamento-servicedesk-v2-20261008; 4ce8241d35ce862e9d53e9a5dce4df9a1858432c
DRY_RUN=APROVADO; CONFLITOS=0; DELTA_APLICADO=38 adicionados,26 modificados,0 removidos
BACKUP_E_JOURNAL=C:/Users/DEV03/Documents/Jrc/backup-retorno-c1-20261009; RECONCILIATION_LOG.json complete,64 operacoes;26 originais com hashes verificados
HASHES_POS_RECONCILIACAO=64 hashes finais do pacote aprovados na aplicacao;10922 originais protegidos;157 caminhos e8 migrations historicas presentes; correcoes posteriores registradas em c1-correcoes-vs-zip.diff
AMBIENTE_E_ESPACO_ATUAIS=Windows C livre 9.67 GiB; Ruby3.4.4,PostgreSQL16; somente os3 containers jrc-rel-sd-tests autorizados; rede interna e sem portas; copia integra /r345-c1-20261009-candidate
MIGRATION_NOVA_NO_CLONE=APROVADA,20261009100000,exclusivamente jrc_rel_sd_r345_c1_test criado por clone; baseline e bancos anteriores preservados; pause_waiting NOT NULL sem default; nenhuma regra nova ativada
TESTES_DIRIGIDOS_APROVADOS_FALHOS_NAO_EXECUTADOS=RSpec89(34 novos+55 relacionados),concorrencia PG3; zero falhas/pending; Ruby isolado21/175 assertions; JS isolado23; Vue10 compilados sem erro
RUBOCOP_ESLINT_DELTA=RuboCop158(137 em arquivos novos,21 em modificados sem atribuicao historica); ESLint6 erros(5 novos,1 comprovadamente herdado),77 warnings; nenhum desabilitado
CORRECOES_REALIZADAS=spec novo com3 contagens por Account/Unit em vez de globais e teste mais forte de imutabilidade/digest;16 arquivos JS/Vue apenas formatacao pelos2 cops autorizados; sem refatoracao funcional
BLOQUEADORES=Vitest7 suites/0 testes em Windows e Linux: falha no preload fake-indexeddb/auto; pnpm disponivel11.25.0 incompatível com engine10.x,sem instalacao; lint novo pendente; contrato historico pause_waiting continua explicito
GATES_FINAIS_PENDENTES=RSpec integrado/preservacao e concorrencia completa; R5 Campaign/Knowledge27,Event email18,Daily email20 com seletores reais; Ruby/JS/lint/build final; navegador Vue->Rails->PG; matriz e atribuicao historica.759JS/build anteriores NAO validam C1; compilacao SFC NAO e build/E2E
SALDO_OBSERVADO_OU_NAO_VISIVEL=janela principal Codex:26% restantes no inicio,24% na medicao final(74%->76% usados); saldo de creditos monetarios indisponivel; sem estimativa
PROXIMO_COMANDO_OU_CHECKPOINT=PARE apos C1; aguardar revisao de saldo e autorizacao para regressao completa; primeiro avaliar lint novo e dependencia fake-indexeddb sem alterar lockfiles/configuracao para mascarar falhas
COMMIT_EXECUTED=NAO; PUSH_EXECUTED=NAO; IMAGE_PUBLISHED=NAO; DEPLOY_EXECUTED=NAO; MIGRATIONS_EXECUTED_ON_SERVER=NAO; REAL_MESSAGES_SENT=NAO

Evidencias externas: C:/Users/DEV03/Documents/Jrc/validacao-retorno-c1-20261009. Falhas iniciais:4 expectativas novas corrigidas(nao falhas historicas); erro externo de seletor UiProjection e CRLF no script shell preservados e corrigidos somente nos scripts de evidencia. Sem alteracoes em Compose/Broker/Runtime/secrets/providers/lockfiles/workflows.

HASHES_FONTE_NATIVA_FINAL=10955 arquivos de codigo/testes iguais ao workspace final;5 documentos excluidos somente por acrescimos apos testes. Evidencia c1-native-final-hashes.log.


## CODEX-20261009-C2-CORRECOES-DIRIGIDAS

BASE_PRESERVADA=C1; branch codex/relacionamento-servicedesk-v2-20261008; HEAD4ce8241d35ce862e9d53e9a5dce4df9a1858432c; origin exclusivo ClaudioHideki/jrc-conversas-lab2.10960 hashes C1 conferidos no inicio;658 caminhos modified/untracked preservados,sem remocoes;157 referencias e8 migrations historicas intactas.
ESLINT=5 erros novos corrigidos;0 novos,1 historico comprovado(one-var em operationalContracts.js),75 warnings.10 SFCs Vue compilados,0 erros.
ALTERACOES_JS=preview sequencial por reduce de promises,mesmos decoders e guardas Account/Unit,interrupcao apos revogacao/cancelamento; escolha de definicao por if/else equivalente; markup do painel de relatorio; .prettierrc apenas acrescenta esse arquivo exato ao override singleAttributePerLine existente,sem desligar regra.
VITEST_CAUSA=Vite isFileLoadingAllowed recusava fake-indexeddb resolvido fora da raiz C1 por node_modules compartilhado; arquivo existe. Config externa /tmp/c2-vitest-shared-deps.config.mjs preserva config/setup originais e fs.strict/deny,pode ler somente raiz C1 e /app/node_modules.153/153 nas mesmas7 suites,sem mudancas em dependencias/lockfiles/vitest.config.ts. Piloto4 nao somado novamente.
RUBOCOP_INICIAL=158:141 novas,11 historicas,6 nao atribuidas.11 fontes anteriores analisadas por --stdin com mesmo config e caminho logico,linha mapeada,cop/mensagem; nenhuma metrica alterada chamada historica sem igualdade.
RUBOCOP_FINAL=82:65 novas,11 historicas,6 nao atribuidas;76 novas corrigidas,nenhum cop/arquivo com aumento de quantidade.20 arquivos Ruby com equivalencia de AST comprovada;parênteses da recorrencia criam somente BLOCK de um valor com mesma multiplicacao,documentado no diff estrutural e guard semantico. Nenhuma regra desabilitada,-A ou refatoracao de interfaces/consultas.
TESTES_C2=89 exemplos RSpec dirigidos sem falhas/pending;25 repetidos apos ultimo layout e5 requests de recorrencia apos parênteses,subconjuntos dos89,NAO somados;21 Ruby isolados/175 assertions;153 Vitest;23 JS isolados;5 isolados novos do callback real/decoders reais com mocks somente de API externa e lease de UI.0 falhas finais.
PRESERVACAO_DB=clone local exclusivo jrc_rel_sd_r345_c1_test; jrc_service_desk_ola_clocks.pause_waiting NO/NULL(default ausente),0 regras operacionais enabled;C2 nao executou migrations nem alterou contratos/FKs. Migration nova C1 teve somente formatacao com AST equivalente,nunca reexecutada C2.
GIT_FINAL=153 modified+506 untracked=659;153 inclui .prettierrc antes nao modificado;0 staged,0 removed;HEAD inalterado;diff-check limpo.24 fontes/configs C2 corrigidas+5 documentos por acrescimo;lista e diffs na evidencia externa.
ESPACO_C=9.67 GiB inicio,9.51 GiB final;sempre acima do piso5GiB;nenhuma limpeza/reparo Docker/WSL.
SALDO_OBSERVADO=janela principal Codex24% restante inicio,22% na ultima leitura(76%->78% usados);saldo monetario nao visivel,sem estimativa ou teto prometido.
BLOQUEADORES=65 infrações novas remanescentes(majoritariamente metricas e ajustes que exigem refatoracao/revisao de interfaces,SQL ou testes),11 historicas,6 nao atribuidas;1 erro ESLint historico e warnings. Novo pause_waiting sem default preservado;pendencia historica nao mascarada.
GATES_NAO_EXECUTADOS=build frontend final,regressao integrada,preservacao comportamental ampla,concorrencia completa eR5 Campaign/Knowledge27,Event18,Daily20,navegador Vue->Rails->PG e matriz final. C2 e153 Vitest dirigidos NAO homologam R3/R4/R5. Nao iniciar R6.
PROXIMO_CHECKPOINT=PARE para revisao do saldo/resultado;eventual proximo lote deve decidir pendencias lint antes da regressao integrada,com autorizacao separada.
AUTO_REVIEW=uma transferencia foi rejeitada por TARs inexistentes apos erro de nome no script de evidencia. Nada extraido nessa tentativa. Resolvido gerando arquivos,conferindo todos membros/hashes localmente e no container e repetindo so nas raizes autorizadas;sem contornar revisao,apagar arquivo ou alterar permissoes.
EVIDENCIAS=C:/Users/DEV03/Documents/Jrc/validacao-retorno-c2-20261009; backups antes-c2,manifests,AST,diffs,lint,Vitest eRSpec. Logs C1 e todas revisoes C2 preservados.
COMMIT=NAO;PUSH=NAO;MERGE=NAO;IMAGEM=NAO;DEPLOY=NAO;MIGRATIONS_SERVER=NAO;MIGRATIONS_C2=NAO;DADOS_REAIS=NAO;MENSAGENS_REAIS=NAO;COMPOSE_RUNTIME_BROKER_SECRETS_PROVIDERS_LOCKFILES_WORKFLOWS_ALTERADOS=NAO.

C2_FONTE_NATIVA_FINAL=10955 hashes de codigo/testes iguais ao workspace final;5 documentos excluidos somente por acrescimos apos testes. Evidencia c2-native-final-hashes.log.


## CODEX-20261009-C3 — checkpoint intermediario da validacao integrada

C1/C2 preservadas. Branch codex/relacionamento-servicedesk-v2-20261008; HEAD 4ce8241d35ce862e9d53e9a5dce4df9a1858432c; origin ClaudioHideki/jrc-conversas-lab2. Estado inicial153 modified+506untracked=659 caminhos,zero staged/removidos.10960 hashes C2 conferidos;10955 hashes da fonte nativa completos conferidos. Referencia b2001cb ancestral,157 caminhos presentes e8 migrations historicas com SHA256 original.

Build Windows de producao APROVADO(exit0,2m49s); fontes intactas. Tentativa Linux bloqueada por postcss-import ausente; sandbox Windows por spawn EPERM; alternativa Windows autorizada passou, sem instalar dependencias ou alterar lock/config. JavaScript integrado759 casos PASS:691Linux+68Windows em arquivos disjuntos.7 arquivos Linux nao carregavam PostCSS; validados com dependencias Windows existentes. Dois titulos repetidos em testes parametrizados sao casos distintos por arquivo/ordinal, nao execucoes duplicadas.

PostgreSQL/COMMIT/concorrencia76 IDs distintos PASS,zero falhas/pending:Capture2,Daily email20,Event email15,Flow/webhook17,Flow concorrente5,mutacao2,pesquisas2,SD/guard13. Campaign15+Knowledge12+Event regular3 PASS apos corrigir SOMENTE duas fixtures:super sem heranca do let e empresa divergente do contato. Todas as linhas expect preservadas; lint dessas fixtures21 antes/depois,sem cop adicional. Nenhuma producao alterada.

RuboCop65 novas analisadas:46manutenibilidade,6performance limitada,5estilo,8organizacao/testes; todas convention,sem risco real confirmado que justifique refatoracao.11historicas+6nao atribuidas C2 mantidas. Nao declarar lint global verde.

Houve queda transitoria do C: a3,58GiB:todos os tres processos pesados foram interrompidos graciosamente;64RSpec integrados e29concorrentes parciais preservados. Build ja havia terminado. Livre voltou acima7GiB SEM limpeza/reparo/reinicio. Retomados apenas IDs pendentes. Banco C1 jrc_rel_sd_r345_c1_test;concorrencia exige exatamente jrc_rel_sd_r345_concurrency_test:aplicada somente migration C1 20261009100000 local nesse descartavel(241->242),pause_waiting NOT NULL/defaultnil,nenhum banco baseline/servidor alterado. Emails Mail::TestMailer,HTTP WebMock,rede interna;zero mensagens/dados reais.

STATUS INTERMEDIARIO:integrado plano1496 IDs;170 ja completos,1326 restantes em execucao. Preservacao243 ainda pendente e sera comparada com seis IDs historicos R2;integrado historico cp5[1:5] nao foi corrigido antecipadamente. C3 NAO HOMOLOGADA;sem R6/E2E navegador completo,commit,push,merge,imagem,deploy ou ativacao em clientes. Compose/Runtime/Broker/secrets/providers/lockfiles/migrations fonte preservados. Evidencias externas em C:/Users/DEV03/Documents/Jrc/validacao-integrada-c3-20261009;continuar do processo c3-integrated-continuation,nao reiniciar fases.


## CODEX-20261009-C3-FINAL — gates integrados concluidos, sem homologacao/publicacao

Este checkpoint fecha a C3 e atualiza o status intermediario acima;todo o historico foi preservado. RSpec integrado1496 IDs totalmente cobertos em execucoes disjuntas/retomadas:1495PASS+1falha historica cp5_integration[1:5]. Preservacao243:237PASS+6falhas historicas. Total1739 IDs distintos:1732PASS,7historicas,zero falhas novas finais,pending ou erros fora de exemplos. Os sete IDs/classes/mensagens iguais aR2 foram comprovados;somente IDs numericos do erro FK variam e foram normalizados. Nada corrigido nos casos historicos.

Historicos:cp5_integration[1:5](FKcontacts/companies impede fixture malformada);Customers operations[1:20]/[1:21](contrato exige pedido aprovado/assinatura);Timeline[1:4](expectativa contracts:false);Proposal[1:3](aceite antes de envio);Commercial migrations[1:1](indice ausente);Operations migrations[1:1](dependenciaProject/SuccessPlan). Comparacao literal registrada em c3-historical-failure-comparison.json. A unica falha do teste de isolamento CP5 continua historica;nao ocultar nem afirmar toda suiteRuby verde.

Os21 testes schemaR5 inicialmente recusados pelo guard do bancoC1 foram repetidos no clone permitido jrc_rel_sd_r345_preservation_test:21PASS. Guard/codigo/migrations fonte nao alterados. Apenas migration C1 20261009100000 aplicada LOCALMENTE aos clones autorizados concorrencia/preservacao(241->242). Tres bancos finais iguais:242versoes,3424colunas,916constraints,1214indices;pause_waiting NOTNULL/defaultnil;indice nico_hd_delivery_once unico e escopado porAccount;0regras operacionais habilitadas. Zero banco baseline/servidor alterado.

Gates R5 completos:Campaign/Knowledge27PASS,Event email18PASS(3normais+15COMMIT),Daily email20PASS,Flow/webhook17PASS. Concorrencia total76PASS,inclusive controles deAccount/Unit/revogacao,claims/locks e transportes test. C1/C2 APIs nativas9PASS(operational_completion5+portalnumber4) incluidos no integrado. AccountProvider/SafeLogger e demais seletores nativos integram1496;sem modificacao deproviders/Runtime/Broker.

Frontend producaoWindows buildPASS exit0(2m49s),759JS PASS(691Linux+68Windows,sem arquivos sobrepostos). Dependencia postcss-import ausente no container bloqueava7arquivos:usadas dependencias Windows existentes,sem instalacao/alteracao lock/config. Avisos anteriores Browserslist/asset runtime/chunks,sourcemap e deprecacoes Rails/Rack/Ruby registrados sem supressao. C2 isolados Ruby21/175assertions,JS23 epreview5 reaproveitados pelos hashes preservados;nao somados ao totalC3 nem declarados reexecutados.

65 novas infraçõesRuboCop C2 analisadas individualmente:46manutenibilidade,6performance limitada,5estilo,8testes;100%convention. Nenhum risco real/gateblocker identificado nelas;sem refatoracao ampla. Permanecem11historicas+6naoatribuidas C2 e lint global NAO verde. Duas fixtures R5 corrigidas,16falhas iniciais eliminadas;expectations byte/linhas preservadas e21infrações nessas fixtures antes/depois,nenhum cop adicional. Nenhuma alteracao funcionalC3.

Preservacao:10960 fontes seladas no inicio;10955 hashes nativos atuais conferidos apos testes;157 caminhos de referencia presentes,8migrations historicas SHA256originais,referencia b2001cb ancestral. Delta C3 apenas dois testes+cinco apendices de continuidade.153modified+506untracked=659,zero staged/deleted;HEAD4ce8241d35ce862e9d53e9a5dce4df9a1858432c inalterado. Hashes finais e prefixos dos documentos em c3-preservation-final-proof.json/c3-source-final-manifest.json.

EspacoC:inicio9,48GiB,minimo observado3,58GiB durante carga paralela:processosC3 interrompidos graciosamente sem limpeza/reparo/reinicio;retomadas por IDs preservadas. Encerramento cerca6,87GiB;valor final exato no relatorio externo. Franquia observada22%inicio e19%fim. Nao executar operacoes pesadas abaixo5GiB.

C3 CONCLUIDA COM7FALHAS HISTORICAS;NAO DECLARAR R3/R4/R5 HOMOLOGADAS OU PUBLICACAO APROVADA. R6/E2E completo nao iniciado por escopo. Homologacoes reais deSMTP/Meta/voz/QR/Broker/scanner e demais integracoes continuam externas,sem credenciais inventadas,mensagens reais ou ativacao em clientes. Definicoes de negocio FCR/qualidade/autonomia/recatalogacao permanecem explicitas;nao transformar nil em resultado fabricado. Automacoes novas OFF por padrao. Sem commit,push,merge,imagem,deploy,migration em servidor,alteracaoCompose/Runtime/Broker/secrets/providers/lockfiles. PARAR e aguardar autorizacao posterior.

Evidencias:C:/Users/DEV03/Documents/Jrc/validacao-integrada-c3-20261009/RELATORIO-C3-FINAL.txt; c3-rspec-final-proof.json;c3-js-complete-proof.json;c3-build-proof.json;c3-rubocop-gravidade.json;c3-fixtures.diff; c3-fixture-correction-proof.json;c3-c1c2-api-integration.json;provas schema/hashes e logs separados.


## CHATGPT-20261009-PROTOCOLO-1 - protocolo e atribuicao na abertura

Base: ZIP da branch codex/relacionamento-servicedesk-v2-20261008, comentario
1e358150084864a1517777e60d0c76bbe702df02; SHA-256 de entrada
808c980da9a9d8caa837e552fd047376cc6873025d23eb730c24884c884dee73.
Sem .git: metadados do arquivo conferidos, nao ancestralidade/GitHub/LAB ao vivo.

Defeito reproduzido no codigo original: createTicketDraft envia impact_code/urgency_code,
mas o whitelist de create em serviceDeskOperationsClient rejeita esses dois campos
com TypeError Unsupported fields antes de qualquer POST. Corrigido somente o
whitelist de criacao; update e campos de numero continuam restritos.

Criacao passa a mostrar recibo apos POST e GET independente validados: protocolo
oficial, titulo, estado, fila, equipe e responsavel efetivamente persistidos;
abrir, copiar, lista e criar outro. Sem numero local/prefixo/contador paralelo.
Confirmacao segue sendo bloqueada em readback pendente, troca de identidade ou
perda de permissao. O detalhe/lista/previa destacam o protocolo. Busca interna
aceita numero com # usando TicketSearch nativo; portal e numeracao backend preservados.

A selecao explicita de agente/fila/equipe desmarca roteamento automatico. A escolha
automatica limpa a selecao manual mostrada, evitando apresentar um agente que o
payload omite. A fila Minha fila usa o mesmo filtro de membership; ha atualizacao
manual da lista. Nenhum novo envio/alerta/realtime foi implementado. Atribuicao nao
e comprovacao de notificacao recebida. Sem agente elegivel, exibir nao atribuido.

Executado AQUI: 416 testes Node PASS (390 existentes + 26 novos), fronteira HTTP
simulada; 41 testes Ruby puros/112 assertions PASS (38 existentes + 3 novos);
3665 ruby-c sem erros; 15 scripts/blocos JS com parsing; 6 templates com tags
balanceadas; 12 chaves CREATION estaticas conferidas; 15 testes do reconciliador PASS.
As contagens de parsing/Node nao equivalem a Vue compilado ou HTTP/SQL reais.

Escritos, NAO executados aqui: 11 testes Rails/PostgreSQL do protocolo/atribuicao;
6 testes novos de componentes Vue, 2 novos cenarios no formulario, adaptacoes de
2 testes anteriores para confirmar antes de navegar e wrapper Vitest dos 26 casos.
Ruby3.3.8 difere do requerido3.4.4; bundle bloqueado, Rails/RSpec/PG/Docker/Vue e
lint nativos indisponiveis. Gate puro completo Relacionamento/Operations bloqueou
por ActiveSupport ausente; nao foi aprovado. Sem alteracao de deps/config/lockfiles.

Nenhuma migration nova/alterada. Nenhum arquivo original removido. Broker, Runtime,
Compose, providers por Account, SafeLogger e historicos preservados. Defaults OFF e
pause_waiting inalterados. Cinco continuidades mantidas por prefixo + este apendice.

STATUS=CODIGO_CANDIDATO_COM_TESTES_PUROS_APROVADOS_VALIDACAO_NATIVA_PENDENTE.
Nao certifica a causa da ocorrencia no LAB sem requisicao/log/versao instalada.
Nao homologa R3/R4/R5/R6. Sem Git, commit, push, imagem, servidor, envio real ou deploy.
Proximo passo: reconciliar delta com backup, rodar testes nativos dirigidos, compilar
Vue/build e validar com dois usuarios sinteticos antes de aprovar publicacao.


## Protocolo/atribuicao - validacao nativa controlada - 2026-10-09

Base preservada: 1e358150084864a1517777e60d0c76bbe702df02. Delta:9 novos/15 modificados; zero remocoes. Manifesto:11003 hashes verificados. CRLF resolvido por espelho externo verificado contra os10961 blobs Git, sem normalizar o workspace inteiro. Backup Windows e journal externos;10946 originais fora do delta byte a byte preservados.
Correcoes adicionais restritas:formatacao apenas de diagnosticos novos de ESLint e dois executores Promise dos testes com bloco explicito; nenhuma assertion removida ou enfraquecida.
Ruby3.4.4/Bundler2.5.16:136 exemplos PASS(11 novos/125 existentes),zero falhas/pendentes. Concorrencia:5 PASS(2 criacoes PostgreSQL/3 guardas). Numero nativo:3 testes/19 assertions PASS. Node:416 PASS(390 existentes+26 novos). Vitest Service Desk:598 PASS/37 arquivos;reexecucao final afetada38 PASS/4 arquivos. Os26 casos compartilhados Node/Vitest e as reexecucoes nao devem ser somados como cobertura distinta.
ESLint delta15 arquivos:zero erros novos,62 historicos;13 warnings(12 anteriores+1 novo vue/no-root-v-if). RuboCop3 arquivos:16 convencoes,12 historicas em TicketQuery/4 novas no spec de request(MultipleExpectations1;HashAlignment2;LineLength1). Nenhuma infracao de gravidade warning/error/fatal. Nao refatorado nem reduzida cobertura para zerar estilo.
Build frontend completo:PASS,2m05s,5383 modulos,apos a ultima alteracao funcional/de testes. Avisos anteriores Browserslist/assets runtime/chunks e sourcemap mantidos.
Banco novo exclusivamente descartavel:jrc_rel_sd_r345_protocol_test,clone de jrc_rel_sd_r345_preservation_test;242 migrations existentes,pause_waiting NOT NULL sem default. Bootstrap inicial RSpec recarregou automaticamente o schema antigo na copia descartavel C1(242->220),antes de executar exemplos. C1 nao foi apagada/recriada;incidente registrado. A origem preservation/concurrency permaneceu242. Solucao:harness externo usa snapshot real242 do clone novo via SCHEMA oficial e metadado correto nesse clone;verificacao nativa de migrations mantida. Nenhuma migration foi executada nesta etapa. Nenhum schema/migration do repositorio modificado.
Reconciliador:14 testes PASS;1 nao validado por WinError1314 na criacao de symlink. Tentativas no sandbox bloqueadas por WinError5 registradas separadamente,sem alterar permissoes.
Browser local:pendente. Preview Vite127.0.0.1 preparado com componente real e fixtures;CUA falhou duas vezes com failed to write kernel assets/os error3. Nenhuma screenshot ou homologacao visual alegada. Fluxo completo com dois operadores no browser/LAB continua pendente;API/PG e componentes testados separadamente.
Notificacao:este delta confirma atribuicao e visibilidade Minha fila;nao cria envio WhatsApp/email/push/realtime.
Sem commit/push/merge/GHCR/imagem/deploy/R6;Compose,Runtime,Broker,providers por Account,SafeLogger,lockfiles/workflows/migrations intactos. R3/R4/R5 candidatos;homologacao integral pendente;nao aprovados para producao.
Evidencias:C:/Users/DEV03/Documents/Jrc/validacao-protocolo-atribuicao-20261009/.
