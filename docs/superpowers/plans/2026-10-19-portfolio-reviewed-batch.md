# Reviewed portfolio batches implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline, as the user authorized. Do not dispatch implementer agents.

**Goal:** Extend the existing Relationship portfolio with a frozen review and durable per-customer outcomes, before adding versioned cadence enrollment.

**Architecture:** Rails retains identity, permissions and native business operations. The batch ledger snapshots the selected customer rows, operation inputs and playbook version. Execution calls `JrcRelationship::PortfolioBatch` for one authorized customer per transaction; it never becomes a second message/Flow executor. No real batch, cadence, bot or campaign is activated during development.

**Tech stack:** Existing Rails/PostgreSQL/Sidekiq, Relationship services and Vue account-bound API.

**Spec:** `docs/superpowers/specs/2026-10-16-nico-jornada-candidata-design.md`, component 5.

## Constraints and review focus

- Preserve production ancestor 98a4be7 and the other developer's modules. Candidate only; no image or deployment until the complete cut passes.
- Freeze the exact IDs and inputs on the server. Never rerun a search to determine an approved audience.
- Revalidate current actor, tenant, native scope and source revisions before every native effect.
- Receipt and native SQL effects commit together; cancellation serializes with each item and prevents subsequent items.
- Keep customer-facing Flow/message approval separate. A bulk preview never authorizes an unreviewed public send.
- A receipt records native resource creation, not provider delivery or completed customer work.

## Task 1 — ledger and application

- [x] Add additive batch + item tables, tenant-composite references, immutable review snapshot and bounded status transitions.
- [x] RED tests: preview has zero effects; exact replay; changed input/revision; two companies; current permissions revoked; cancellation; item rollback/restart.
- [x] Implement server snapshot over 1–50 selected portfolio assignments, native operation options and playbook version.
- [x] Implement approval/execution/get/cancel with current authority and one durable receipt per customer, using the existing native operation service.
- [x] GREEN PostgreSQL/request regression. Record limits, errors and the exact native results.

## Task 2 — interface and worker

- [x] Replace direct portfolio form submission with a readable preview, explicit confirmation and per-item progress/cancel.
- [x] Bind requests and cached preview to the original account; discard late responses and edited-selection previews.
- [x] Continue approved work through Sidekiq after process replacement without rerunning completed items.
- [x] GREEN Vue tests for account switch, cancellation, stale preview and partial result.

## Task 3 — cadence enrollment

- [x] Freeze playbook version and finite native step schedule in a durable enrollment; do not silently adopt later book changes.
- [x] Bind the explicitly selected conversation/customer, retain an event watermark and stop on a new contact reply, human intervention or cancellation.
- [x] Keep public sends in Broker and require its own approval/transport receipts. Native task creation is not a WhatsApp delivery.
- [x] RED/GREEN restart, deduplication, concurrent cancellation/reply, revoked role and tenant isolation.

## Completion

- [x] Native unit/request + Vue regressions, migrations and rollback review, current production-base compatibility.
- [x] Update consolidated ledger honestly. Remaining commands/events, bounded agents/knowledge and voice acceptance stay separate criteria until implemented and demonstrated.

## Focal implementation evidence — 2026-10-19

Tasks 1 and2: implemented. Task3: implemented for finite native steps, one explicitly selected customer/conversation per enrollment. Rails owns CRM/tasks/agenda; public Flow/message approvals remain separate. Book snapshot/version, schedule, current authority, customer digest, conversation control revision and contact reply watermark are persisted; receipts and native effects commit in one transaction. Completed items are never repeated; cancellation serializes with a locked item. Queue is the existing Sidekiq default, already consumed in config/sidekiq.yml; no new runtime bot or deployment flag.

RED/GREEN: nonexistent cadence service; arbitrary uniqueness retry; changed portfolio owner (would execute for an unreviewed new owner). The owner fix also exposed that an incoming message touches Contact.updated_at; stop reason now prioritizes the actual contact reply. The final PostgreSQL regression passed33 examples with zero failures/pending, including real independent-connection duplicate admission/worker/cancellation tests in the explicit disposable database (`/tmp/cadence-final-green.log`). Previous failure due to global fixture counts was corrected to assert tenant-scoped state, not by removing isolation checks.

Vue/API regression:4files25tests PASS (`.sessions/cadence-vue-green.log`), covering explicit approval, stale previews/reads, account/actor switch, cancellation, recovery and scoped cadence requests. New Vue files lint0errors/7warnings (dynamic translations/separators). Ruby9new cadence/batch files lintPASS (`/tmp/cadence-ruby-lint-final.log`). Both candidate migrations applied only in the dedicated local database; native schema dump is intentionally not substituted for migration functions/triggers.

Remaining focal closure: independent review, refreshed composition proof after final source freeze and exact migration rollback/upgrade review. No production image, publication, bot, cadence or message was activated. Rest of consolidated program components6–8 and external/capacity acceptance are separate unfinished criteria.

## Fechamento local verificado

Conjunto nativo consolidado: 343 exemplos aprovados, sem pendentes, incluindo migração ausente, upgrade, cobertura corporativa e concorrência. Broker:421 arquivos/3221 testes, typecheck, bundle e auditoria aprovados. Interface NICO:96 testes; carteira/cadência:25; editor nativo:7 jornadas reais locais sem requisições externas. Build completo do host aprovado (5439 módulos). Manifestos são regenerados após este fechamento. CI, publicação, implantação e homologação real são etapas distintas; nenhum bot ou envio real foi ativado. O runtime NICO separado não mudou.
