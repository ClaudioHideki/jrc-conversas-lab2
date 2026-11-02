# JRC performance and refresh implementation plan

> **For agentic workers:** Use superpowers:executing-plans for the parent and focused independent implementation tasks. Use TDD for each correction.

**Goal:** Stop unnecessary visible refresh and reduce the read cost amplified by imported projects, preserving account boundaries and current authorization.

**Architecture:** Same-identity background refresh retains confirmed presentation while current authorization is revalidated. Denial, identity changes, invalid contracts and filters still invalidate state. Project read serialization uses a request-bound authority projection and batched page data, while mutation paths retain fresh checks. Existing Cláudio optimizations remain.

**Tech Stack:** Vue 3, Vitest, Rails, PostgreSQL, RSpec.

**Spec:** User request of 26/10/2026: compare Cláudio's performance work with production764de083, investigate refresh/slow pages and implement measured corrections. Existing permission and isolation contracts are unchanged. No messages, campaign starts or reconnections.

## Global constraints

- Start from764de083 and preserve the four integrated fronts and campaigns.
- Preserve dirty DateSeparator/Spinner snapshots and private .sessions; stage only task files.
- Never cache authorization globally or across requests/users/accounts. Mutation checks remain current.
- No production migrations, data edits or resource-limit changes as a performance experiment.
- Record source findings separately from production measurements and mock/local tests.

## Review focus

- Account/identity changes while read is pending must clear immediately and discard late responses.
- Denied/unauthenticated/invalid response must invalidate retained content.
- Query or selected ticket changes must not retain another scope's data.
- Background read must not close ticket preview or lose scroll/selection.
- Authorization snapshots may not leak into later requests or write effects.

## Task1 Navigation refresh

Files: helpers/nativeIntegration.js; composables/useServiceDeskNavigation.js; composables/useServiceDeskStructure.js; their existing ServiceDesk tests.

- [x] Reproduce menu disappearing during a deferred same-identity context recheck and duplicate focus/visibility starts.
- [x] Retain confirmed same-identity navigation while pending; clear on identity/feature/error/denial; coalesce overlapping same-identity rechecks without permanent cache.
- [x] Run helper/component tests including abort/unmount/account change/revocation. Do not restructure unrelated shell state.

## Task2 ServiceDesk background presentation

Files: helpers/session.js; helpers/operationalSession.js; TicketListView.vue; OverviewView.vue; existing session/IntegratedRefresh/OverviewLoading/ticketNavigation tests; LiveKpis if required.

Interface: optional background flag on read/load; default foreground semantics unchanged. Background only retains completed resource from same request scope and current authority generation.

- [x] Add deferred refresh tests proving rows/KPIs/preview remain and denied/account changes invalidate.
- [x] Introduce scoped background read semantics and separate query/identity load from revision refresh.
- [x] Run focused real helpers + component tests and relevant permission regressions.

## Task3 Project read cost

Files determined from serializer/access/authorization and projects/tasks GET paths; existing project request/policy specs.

- [x] Measure project-card serialization1 vs5 in read-only production transaction; print only counts/timings.
- [x] Add query-scaling regression using real models and compare exact capability output for administrator/member/denied/cross-account.
- [x] Build immutable authority projection once for read request and batch current page memberships/companies where needed. Do not weaken allowed? on writes or introduce cross-request memoization.
- [x] Verify bounded query growth and the existing revocation/mutation suites.

## Task4 Project page first render

Files: ProjectDetail.vue and existing component tests.

- [x] Reproduce project identity waiting on all task pages.
- [x] Display authorized project as soon as its fetch completes, with independent task-loading state and stale-navigation protection.
- [x] Retain complete task dataset semantics for existing board/list; no unplanned pagination redesign.

## Final checks

Additional measured scope: Task3 includes task GET permission projection with creator/assignee contributor restrictions; Task2 includes same-scope supervision report retention. Both preserve mutation checks and authority invalidation.

### Task5 Requester picker pagination

Files: requester_people_controller.rb and focused requester people request specs, plus existing Directory/ContactPolicy scope references.

- [x] Reproduce eager Contact instantiation beyond requested page and repeated company serialization on the actual GET path with synthetic contacts.
- [x] Preserve visible_contacts corporate/tenant scope and current per-record show authorization. Paginate/count in SQL when equivalent to current ContactPolicy (including Enterprise overlay); batch serialization for the selected page.
- [x] Verify page/meta/search equivalence, foreign account/company denial, unauthorized/custom-role behavior and bounded instantiation. Never bypass unknown policy semantics merely for speed.
- [x] Record local-only measurements and run affected requester/permission regressions.

- [ ] Run full candidate CI and production frontend build for the final committed candidate (local focused suites and lint delta passed).
- [ ] Recheck latest remote/production revision before release (independent source/security/race review passed).
- [x] Report measured improvements and remaining unmeasured bottlenecks. Do not call all modules fast from one test.


## Local verification record

- Full ServiceDesk regression: 1,087 tests across 82 files passed before style-only cleanup; focused final reruns cover edited helper/component boundaries.
- Project/task operations and corporate scope: 146 RSpec examples passed; additional projection bypass fixtures passed.
- Requester/assignment/completion/contact policy: 41 RSpec examples passed.
- JavaScript lint compared with exact base: zero new errors; four additional Vue test-harness warnings. Four new Ruby files lint clean; optional read_projection keyword adds one ParameterLists metric in existing serializer.
- Synthetic local HTTP GET query scaling: project cards 1/5/25 now 35/35/35 SELECT notifications versus 183/755/3655; task page 1/25 now 40/40 for member/contributor versus 57/561. These include cached notifications and are not production latency measurements.
- Production read-only baseline (serialization only): 5 project cards used 245 uncached SELECTs, 485 cached, 510ms wall. Existing Cláudio optimizations were already deployed in 764de083.
- Production cgroup baseline: 1CPU/1GiB, no OOM/failcnt observed. No resource changes, data writes, migrations, messages, campaign sends or reconnections performed.
- No database migrations or dependency changes in this candidate.
