# Central inbox visibility and distribution implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce per-inbox exclusive human assignment while preserving shared inboxes and improving the existing JRC dispatcher.

**Architecture:** Reuse account-scoped connection policies, the authoritative conversation authorization layer and the existing dispatcher. Add explicit visibility, supervisors and individual inbox limits; never infer privacy from bot presence. Check realtime recipients again at delivery time.

**Tech Stack:** Rails 7.1, PostgreSQL, Redis/ActiveJob, Vue 3, RSpec and Vitest.

**Spec:** `output/distribution-analysis-20261105/ANALISE-DISTRIBUICAO-E-VISIBILIDADE.md` in the parent workspace, approved by the user on 05/11/2026.

## Global constraints

- No production changes, credentials, sends, deployment, backup/dump/restore or automatic policy activation.
- Preserve shared inbox behavior, existing commits, multi-tenant boundaries and bot ownership.
- Only supervisors see the central queue; agents see their assigned conversations.
- Historical imports must not create distribution requests or change assignees.

## Review focus

- Enterprise overrides must not bypass the new visibility restriction.
- A delayed cable job must not reveal a message after assignment changes.
- A participant or contact-history query must not bypass exclusive visibility.
- Repeated incoming messages must not reset queue age.
- Capacity changes must preserve legacy account-wide limits for existing shared policies.

## Task 1 — authoritative visibility

Files: `app/services/conversations/inbox_visibility.rb`, conversation policy, core and Enterprise permission filters, search service, notification finder, unread-count scopes, contact-history/export consumers as found.

Interfaces: `Conversations::InboxVisibility.new(account:, user:).restrict(relation)`, `.visible?(conversation)`, `.exclusive_inbox_ids`.

- [x] RED: same-inbox colleague, unassigned queue, participant, foreign tenant, supervisor, admin and legacy sharing policy tests.
- [x] Implement one account-scoped restriction; compose it with existing RBAC without widening permissions.
- [x] GREEN: run RSpec visibility and affected authorization/search tests.

## Task 2 — realtime and revocation

Files: cable listener, broadcast job, notification delivery boundaries, dashboard cable handler and conversation store.

- [x] RED: peer never receives full payload; delayed message and transfer revoke the old owner.
- [x] Filter both event creation and job execution; emit content-free revocation and remove local messages/attachments.
- [x] GREEN: Ruby cable and JS mutation/connector tests.

## Task 3 — validated configuration and UI

Files: JRC policy/controller, `ConnectionDistributionPolicy.vue`, English translations, request/component specs.

Interfaces: additive `visibility`, `supervisor_ids`, `agent_limits` connection-policy fields, backward-compatible defaults.

- [x] RED: reject foreign supervisors/limits and unsafe exclusive options; round-trip new configuration.
- [x] Add visibility, supervisor and individual capacity controls using existing distribution endpoint.
- [x] GREEN: policy/request and component tests; lint changed files.

## Task 4 — capacity, selection and FIFO

Files: JRC dispatcher, workload selector, DispatchJob, IncomingMessageRequest.

- [x] RED: 6/20 beats 4/5, equal ratio round robin, final-slot concurrency, inbox-specific capacity, repeated-message FIFO.
- [x] Preserve legacy shared account-wide capacity; exclusive policy uses per-inbox individual limits. Revalidate under existing account/conversation/member locks.
- [x] Implement stable queue cursor by request timestamp/ID; keep first request timestamp.
- [x] GREEN: distribution, incoming request and concurrency suites.

## Task 5 — return and reopening

Files: AccountUser callbacks, presence entrypoint, assignment handlers and jobs.

- [x] RED: return schedules immediate distribution, pause preserves existing assignments, reopens prefer eligible previous agent and otherwise queue.
- [x] Enqueue after commit and presence recovery; retain periodic recovery; preserve bot and historical boundaries.
- [x] GREEN: availability/reopen/integration tests.

## Task 6 — regression and checkpoint

- [ ] Run available Rails suites, affected Vitest suites, frontend lint/build and Ruby lint/syntax.
- [x] Fresh whole-diff review; fix important findings with RED/GREEN evidence.
- [x] Document actual results, infrastructure limitations and Broker handoff gaps; do not label synthetic coverage as real WhatsApp homologation.

## Execution ledger

- Start: LAB2 `5dcf046b63eb79740b30d76893828f4cbed52280`, clean worktree `codex/shared-inbox-history-20261104`; Broker untouched.
- Ruling: reuse existing isolated task checkout to preserve the previous history/grouping increment; no reset or cherry-pick.
- Ruling: user approved execution of the delivered concrete analysis; implement inline without another approval cycle.
- Local test runtime being prepared from `chatwoot/chatwoot:v4.16.2`; missing test gems are installed in a separate container, not a running app.

- Final regression: 285 Rails examples and 219 Vitest tests passed; PostgreSQL/Redis concurrency gate enabled in disposable local DBs. See docs/atendimento/DISTRIBUICAO-CENTRAL-20261105.md.
- Remaining gate: full frontend build exited 134 (heap OOM at 1536 MiB); no full-product CI/E2E or deployment. Full RuboCop still reports metrics/style debt; Lint-only passes.
