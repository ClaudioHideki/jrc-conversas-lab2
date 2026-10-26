# Four fronts and automatic campaign delivery implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Consolidate the four published JRC updates and make the campaign module recover safe interrupted work without server intervention or duplicate sends.

**Architecture:** Preserve the current candidate and integrate the reviewed, disjoint source commits in their supplied order. Campaign recovery uses durable watchdog jobs, fenced local claims and the existing canonical-message/Broker idempotency contracts. Unknown external outcomes remain protected and visible; no recovery fabricates a delivery receipt.

**Tech stack:** Rails 7.1, PostgreSQL, Sidekiq/Redis, Active Storage, Vue, Vitest, RSpec and Node.

**Spec:** User integration instructions supplied 2026-10-26; source branch `codex/servicedesk-overview-performance-20261026`, source tip `2d07bc0f46ec786cbae9aad52da543c801eaf538`.

## Global constraints

- Destination starts at `40d87928a1f58971035698fe8bcfb017c2dfe184` on `codex/jrc-campaign-direct-audience-20261022`.
- Preserve both pre-existing modified shared snapshots and local `.sessions` files.
- No reset, clean, force push, automatic main merge, data deletion or functionality removal.
- No Docker/GHCR image generation or publication, deployment, production migration, Dokploy, Compose or ENV changes in this phase.
- Tests use synthetic fixtures and disposable local databases only; do not send more real campaign messages.
- Maintain Account/project/inbox ownership, approval digests, recipient selection, opt-outs, audit and provider idempotency.

## Review focus

- Interrupted pre-provider claims must resume once; old concurrent workers must be fenced.
- A canonical message or reserved intent must be reused rather than recreated.
- Callback uncertainty and provider UNKNOWN states must never be erased or blindly resent.
- Refreshing sender metadata must preserve the operator's explicit selection.
- Financial versions and private rich-comment files must preserve history, cents and authorization across retries.

## Task 1: Selective four-commit integration

- [x] Inspect remote, branch, HEAD, worktree, local changes and ancestry/equivalent patches.
- [x] Verify source tip and sequence A/B/C/D; compare changed paths and review behavior.
- [ ] Integrate `aaf70f416993d05a6cad522ca7879f9a43651a45`, `24064ed7fcf15d4c5c68e4b41d29572abd8e48f2`, `4ac43ca85cfb59170b8e81a25f59012958ec47df`, `2d07bc0f46ec786cbae9aad52da543c801eaf538` in order with provenance.
- [ ] Reconcile schema version/columns/indexes with both additive migrations; never replace a newer schema.
- [ ] Verify preservation of all destination-only paths and snapshots.

## Task 2: Automatic campaign backend recovery

Owner: campaign recovery agent. Files: campaign dispatch/sender/reservation/status services and jobs, Broker context/client call sites, minimal webhook listener, focused service/job/request specs.

- [ ] Reproduce interrupted claims, post-commit callback interruption and retained database leases with failing tests.
- [ ] Add durable bounded watchdog and fenced claims without new schema unless review proves necessary.
- [ ] Persist a stable callback identity atomically with canonical message correlation; retry only the normal safe callback using existing message and intent.
- [ ] Release idle AR connections before Broker HTTP outside transactions; verify one-slot pool reentrant behavior.
- [ ] Cover pause/cancel, approval change, tenant/inbox mismatch, blacklist, concurrent/stale workers, unknown/accepted/in-flight outcomes and callback idempotency.

## Task 3: Explicit sender and complete module workflow

Owner: campaign UI agent. Files: CampaignWizard and campaign component/page specs.

- [ ] RED/GREEN: no implicit sender; deselect then refresh; metadata reorder; removed sender without substitution.
- [ ] Exercise pasted/manual and CSV recipients, native image upload plus personalized caption, explicit sender, review approval and launch through real components with synthetic API boundaries.
- [ ] Preserve timezone, ETA, legacy approval payloads and canonical media asset IDs.

## Task 4: Integrated validation and candidate report

- [ ] Exercise affected Vitest/RSpec/Node suites and frontend build without creating a Docker image.
- [ ] Run rich-comment PostgreSQL concurrency with its explicit synthetic-database guard enabled; do not count a skipped suite as proof.
- [ ] Test financial cents/version preservation, rich private uploads and permissions, navigation, Service Desk and both migrations in disposable databases.
- [ ] Compare lint against the exact initial baseline; record inherited offenses separately.
- [ ] Independently review the complete diff and run broader regression gates.
- [ ] Record destination/start/final commits, integrated provenance, conflicts/resolutions, changed files, tests, migrations and remaining limits. Present the candidate for review; await image-publication authorization.
