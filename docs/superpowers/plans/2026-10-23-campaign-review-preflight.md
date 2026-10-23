# Campaign review preflight implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Review and approve a campaign without retaining database locks/connections across a reentrant Broker read, and prevent concurrent UI refreshes from publishing stale state.

**Architecture:** Materialize local configuration, fetch the scoped sender identity outside the write transaction, then re-read and compare local configuration under the short campaign lock before persisting review/approval or launch state. Serialization checks the integrity, expiry and local configuration of the human approval without an HTTP request; execution still performs a fresh remote identity preflight. Only the review preflight opts into returning an idle database connection before its HTTP reads; an active transaction is never released.

**Tech Stack:** Existing Rails/ActiveRecord/PostgreSQL, Broker client, Vue, WebMock/RSpec and Vitest.

**Spec:** Root-approved correction of 23/10/2026: `ApprovalService#configuration` currently invokes `BrokerConnector#transport` inside review/approval/launch row locks and during list serialization. `JrcCampaignsPage` can overwrite newer refresh/filter/sender results with older pending requests. Necessary glue in Campaign/LaunchService and local-vs-remote approval semantics approved by root.

## Constraints

- Reuse the existing isolated worktree. Local changes/tests only; no commit, push, deploy, provider request or production mutation.
- Do not modify the committed failure-handling patch, NICO, customer import, or timezone validation owned by other agents.
- Retain Account/inbox/binding/integration/actor/identity-revision checks, approval digest, 48-hour expiry and administrator approval.
- Never use remote preflight evidence after local configuration or approval changed while the request was pending.
- Do not release a connection that has an active transaction. No global Broker Client behavior change.
- No new UI polling timer: fix concrete races in existing refreshes, pending approval and component disposal.

## Review focus

1. A reentrant HTTP read must see no campaign row lock, and an idle DB connection should be available to the callback.
2. Changed Step, binding, integration or callback, canceled campaign or revoked approver during HTTP must prevent the stale write.
3. Local serializer validity must never substitute for fresh remote sender identity at launch or dispatch.
4. Multiple refreshes and analytics filters must keep the latest result/loading state, and late results after disposal must have no effects.
5. Repeated approval clicks must not issue concurrent mutations; changing the reviewed campaign must invalidate the old pending result.

## Task 1: Pin and correct the backend boundary

**Files:** `app/services/jrc_campaigns/approval_service.rb`, new `app/services/jrc_campaigns/review_configuration.rb`, `app/models/jrc_campaigns/campaign.rb` (approval/launch methods only), `app/services/jrc_campaigns/launch_service.rb`, `app/serializers/jrc_campaigns/campaign_serializer.rb`, minimal opt-in in `app/services/jrc_broker/context.rb` and `app/services/jrc_campaigns/broker_connector.rb`; create `spec/services/jrc_campaigns/approval_service_preflight_spec.rb`.

- [x] Add functional RED cases for HTTP transaction depth, serialization without HTTP, remote identity mismatch and local/role/status changes during remote reads.
- [x] Add a committed-fixture reentrant PostgreSQL regression for an idle connection returned before HTTP, guarded to the test database.
- [x] Fetch remote configuration before locks, compare fresh local configuration before each state write, and preserve failure/expiry/role behavior.
- [x] Keep normal dispatch validation remote; move launch validation outside its write transaction with recheck inside.
- [x] Verify GREEN and adjacent campaign/governance/serializer regressions.

## Task 2: Pin and correct the UI races

**Files:** `app/javascript/dashboard/routes/dashboard/jrcCampaigns/JrcCampaignsPage.vue`, `components/CampaignApproval.vue`, `specs/campaignPageFlow.spec.js`; add focused approval cases if needed.

- [x] Reproduce out-of-order campaign/metadata/analytics results and pending approval changes with deferred promises.
- [x] Apply per-resource latest-request/disposal guards; prevent concurrent approval mutations and stale completion effects.
- [x] Preserve saved draft, review digest, separate human approval and Start action. No timer added.
- [x] Verify focused Vitest and ESLint, then combined adjacent verification after coordination with NICO/timezone agents.

## Task 3: Review and handoff

- [x] Inspect Enterprise counterparts and final diff, run targeted lint and `git diff --check`.
- [x] Record exact RED/GREEN evidence and local/remote semantic limits.
- [x] Obtain independent review; leave all changes local for root.

## Execution ledger

- No Enterprise override of the campaign ApprovalService/model delegates/serializer was found.
- Initial PostgreSQL RED: 12 cases / 11 functional failures. The previous code leased a connection inside an open transaction during HTTP; the independent callback got `ActiveRecord::LockWaitTimeout`. Step, binding, callback, role and cancellation changes during HTTP were not rejected. The existing identity-mismatch guard passed. Log `.sessions/campaign-review-preflight-red-20261023.log`.
- Initial PostgreSQL GREEN: 12 cases / 0 failures, 13.58 seconds plus 16.87 seconds boot. Log `.sessions/campaign-review-preflight-green-20261023.log`. The initial callback used the normal test pool; the final regression uses one slot and a half-second checkout timeout.
- UI RED: 10 cases / 8 functional failures, 2 existing saved-draft/approval/Start flow cases passed. Covered stale full refresh, loading, sender metadata, filter analytics, disposal, changed review target and concurrent approval POSTs. Log `.sessions/campaign-review-ui-red-20261023.log`.
- The opt-in connection release is limited to the review preflight. Active transactions are never released. Configuration and secret-derived fingerprints are captured before HTTP; only public configuration and identity revision are persisted in the existing review snapshot. The private fingerprints never enter API JSON or logs.
- Local approval serialization means the saved human attestation is intact, unexpired and matches the locally recorded campaign configuration. It does not assert remote connection/identity readiness. Launch and dispatch still require fresh remote evidence and fail closed on errors or identity changes.
- Refinement RED: 3/3 failures reproduced a late review clearing a newer approval and LaunchService rescue overwriting concurrent pause/cancel. Minimum corrections compare the approval revision and use a conditional recovery write. Log `.sessions/campaign-review-refinement-red-20261023.log`.
- Focused PostgreSQL GREEN: 17/17, including the one-slot reentrant callback, preservation of an explicit transaction, and five independent `FOR UPDATE NOWAIT` attempts blocked by the source/actor `FOR SHARE` fences. Log `.sessions/campaign-review-preflight-final-20261023.log`.
- Final adjacent PostgreSQL GREEN after lint refactoring: 255/255, 0 pending, exit 0. Includes all `spec/services/jrc_campaigns`, Context sync, campaign request governance and Broker request contract. Runtime 2m04.3s plus 17.53s boot. Log `.sessions/campaign-review-adjacent-final-20261023.log`.
- UI refinement RED: 1 failure/11 passing demonstrated that a successful approval could be posted again before the parent unmounted the dialog. Closing its logical request scope on success prevents that repeated mutation. Focused GREEN 12/12. Logs `.sessions/campaign-review-ui-refinement-red-20261023.log` and `.sessions/campaign-review-ui-green-20261023.log`.
- Final UI regression: 11 files/80 tests passed, exit 0, one worker with no file parallelism, 99.45s. ESLint exit 0 on the four changed Vue/JS files: 0 errors, 22 existing template/i18n warnings. Logs `.sessions/campaign-review-ui-adjacent-final-20261023.log` and `.sessions/campaign-review-eslint-final-20261023.log`.
- Independent static review of all seven Ruby sources, two Vue sources and the focused specs found no blocker. This is a code-review result, separate from the executed local regressions and from production proof.
- Final RuboCop: new ReviewConfiguration, changed ApprovalService/Context and new preflight spec have no offenses. The full eight-file selection exits 1 for 22 pre-existing offenses in BrokerConnector, Campaign, LaunchService#build_recipients and the serializer. The unchanged HEAD versions reproduce those categories; LaunchService#perform's three existing complexity offenses were removed by the extraction. The baseline directory run reports 23 because two model-only inverse-of checks do not match that temporary path; an exact-path stdin run confirms all 14 original model offenses (25 baseline offenses across the four files, versus 22 now). No blanket exclusion or unrelated cleanup was added. Logs `.sessions/campaign-review-rubocop-final-20261023.log`, `.sessions/campaign-review-rubocop-baseline-20261023.log` and `.sessions/campaign-review-rubocop-baseline-model-20261023.log`.
- `git diff --check` passed for the scoped files. The isolated entrypoint helper fix has its own plan/spec and is excluded from this change's manifest. Unrelated shared-component snapshots were preserved.
