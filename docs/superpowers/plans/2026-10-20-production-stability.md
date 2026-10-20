# Coordinated production stability implementation plan

> Use superpowers:executing-plans, with regression tests before each correction.

Goal: remove observed NICO request timeouts and finish human distribution across
the shared Grupo JRC account, preserving separate Broker/JRC/runtime boundaries.

Spec: the user-approved operating model in the Broker analysis
`docs/analysis/2026-10-20-grupo-jrc-routing.md` and the existing NICO send commit
gate and chat UX designs. Three inboxes, shared Support/Finance, separate Sales.

## Constraints

- No activation of flows/bots, no live customer messages, no automatic deployment.
- Keep unknown provider reservations and external send receipts.
- All authorization is account scoped and rechecked at execution.
- No main merge/publication before results and remaining deployment gates are clear.
- Existing working trees contain prior approved changes; preserve them.

## Tasks

1. NICO asynchronous operator planning: persist the same idempotent command,
   enqueue after creation; worker claims once outside long database transactions,
   revalidates access and plans without occupying a web request. Claim survives
   retries and a stale started request is marked uncertain, never redispatched.
   Prepared/confirmed actions retain their existing authorization contracts.
   Test duplicate requests/jobs, revoked access, queue failure, delayed completion.
2. Operator UI: consume asynchronous results through polling, maintain processing
   status, speak only the new response, navigate once for the submitted command,
   stop voice capture while planning, preserve account-change and failure guards.
   Test pending/succeeded/failed responses, account switch and old-history silence.
3. Human routing: opt-in account policy for account-wide least open workload after
   team handoff. Intersect account/inbox/team/presence/capacity. Serialize selection
   and assignment; queued conversations retry with the same policy. Never change
   inbox/number or assign a conversation while its bot owns it.
   Test three inboxes, independent tenants, offline/full agents, queue recovery,
   preserved manual assignee, bot/pending exclusion, concurrency.
4. Regression/release evidence: full Broker unit/frontend suite and build; JRC
   NICO/Flows/Broker/assignment request/service/UI tests and asset build; runtime
   test suite if its source is available. Review cross-system contract diffs,
   deployment settings and pending environment checks. No production claim based
   solely on local tests.

## Progress

- Existing Broker GROUP_* job-list contract fix is carried forward, with its
  regression tests. Full Broker suite started 20 October locally.
- Existing JRC chat UX commit b3ab140f is retained, not deployed by this task.
- Production validation is a distinct gate after tested candidate images.
- Implemented async planning, worker claim/recovery, permission revalidation,
  connection release outside transactions and UI completion tracking.
- Implemented opt-in human assignment with account-wide load, team/inbox
  intersection, serialized capacity, pagination and periodic recovery.
- Independent review found an overbroad operational-grant check on manual
  administrator reads. Restored the native policy there; automatic Helpdesk
  retains its explicit operational scope. Added regression for both boundaries.
- Broker general suite: 3,227/3,231 passed in the first run; the four timed-out
  cases passed with their two files rerun serially (10/10). Build and bundle
  security scan passed. PostgreSQL integration: 1,196 passed, 12 failed and
  33 skipped in the first run; the affected eight files produced 182/183 passes.
  The remaining short-deadline setup failure passed after separating setup's
  budget from the operation under test (4/4 deadline cases). The catalogue test
  now compares both inventories in the same sort order across SQL collations.
  No runtime deadline or tenant restriction was relaxed.
- JRC frontend: affected NICO/Flows/Broker suites and focused recheck passed;
  runtime 39/39 and Flow sandbox 5/5 passed. Initial asset build was interrupted
  to reduce memory contention; final serial production Vite build passed
  (5,442 modules, 9m33s, process exit 0). Warnings: stale Browserslist data,
  a runtime-served public image confirmed present, mixed static/dynamic webphone
  import and large chunks. These remain optimization items, not build failures.
- Integrated Rails first round: 724 examples, 17 failures, 53 opt-in pending.
  This included an accidental duplicate copied test directory (removed from the
  disposable container). One administrator-access failure matches the review
  fix, two copies of the foreign-tenant fixture hit an unstubbed unrelated
  auto-assignment callback, and 14 native Flow cases lacked FLOW_TEST_REDIS_URL.
  Focused recheck uses isolated Redis DB 4 and corrected fixtures.
- Browser production validation remains unavailable: CUA initialization fails
  with `failed to write kernel assets (os error 3)` before visiting the system.
- Rails evidence consolidated by file and full example description, excluding
  the accidentally copied nested directory: 725 distinct examples passed across
  the integrated run and targeted rechecks, with no remaining failed/pending
  examples in that tested set. This is a multi-run result, not a claim that the
  entire repository test suite ran green in one invocation.
- Inbox scoping + legacy assignment regression: 98 examples passed. Final
  assignment refactor recheck: 17 passed. Four new assignment Ruby files have
  no RuboCop offenses. UI policy/connections: 12 passed after inbox selection.
- Two independent directed review passes found no further actionable issues
  after the administrator-read correction. They are static reviews.
- Broker local browser E2E: 37 passed, zero failures, five intentional
  desktop/mobile combinations skipped. Local fake providers and disposable
  PostgreSQL/Redis only. Owned disposable servers were removed after the tests.

## Handoff status

Implementation and the local regression scope above are complete. No commit,
push, image publication or production deployment occurred in this round.
Production readiness is not certified: candidate installation, real WhatsApp
handoff across the three inboxes, NICO text/voice/actions, provider accounting,
external Chatwoot/Meta and physical capacity still need environment evidence.
No existing production bot or assignment policy was activated.

## Execution deviations

- Keep execution serial for heavy suites/builds on the local 8 GB host. Do not
  stop unrelated apps or containers to recover memory.
- Preserve unknown provider accounting and do not activate any production
  distribution policy or bot during this work.
- No source publication, image publication or deployment occurred in this round.
- Additional regression found that an account-only opt-in would suppress native
  assignment in unrelated inboxes. Require explicit tenant-validated inbox IDs;
  retain aggregate account load but preserve native behavior outside that set.
  Added a failing real-arrival test before changing the callbacks and UI.
- The first committed-send opt-in run hit the local 14-second SQL deadline in
  fixture TRUNCATE, before exercising the send scenarios. Reran against a new
  disposable tmpfs PostgreSQL server (test-only durability disabled). All 18
  send-gate cases passed, as did the 35 committed Helpdesk mail cases. Production
  database settings and application SQL deadlines were not changed.
