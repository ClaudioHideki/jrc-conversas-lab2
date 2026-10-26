# Campaign production consolidation

> Use superpowers:executing-plans for implementation and a fresh whole-branch review before publishing.

**Goal:** Preserve the current production Service Desk updates while restoring the validated campaign transport, status reconciliation and NICO receipt fixes.

**Spec:** User request on 2026-10-26 and `output/validation-20261026/status.json` in the parent workspace. Production test message2386 failed with JRC_BROKER_DELIVERY_REJECTED; the canonical message JSON omitted additional_attributes and campaign reconciliation was absent.

**Architecture:** Merge production f6f999f37b86aea036e3efff08137f7b0cc44d88 into candidate81ed04e87b6149abc51adcd6797133e9c02d6574. Preserve the latest Service Desk, portal, survey, attachment authorization and assignment behavior; retain candidate campaign provenance, preflight outside locks, rejection reconciliation and NICO accounting. No main merge, credential expansion, historical replay or bulk send.

**Tech stack:** Rails/PostgreSQL, Vue/Vitest, Node NICO, GHCR and Dokploy.

## Tasks

- [ ] Resolve merge conflicts by responsibility; preserve the two unrelated local snapshots.
- [ ] Test canonical message reads, campaign failure/status handling, launch/preflight, webhook routing, surveys and protected Service Desk attachments. Use existing RED/GREEN regression specs; add a focused combined regression only if the merge introduces new behavior.
- [ ] Run the declared candidate regression and build gates against the consolidated commit; inspect every failure before publication.
- [ ] Review the complete branch, compare newest remote and deployed revisions again, publish immutable app/runtime images as needed, deploy without replacing configuration or persistent volumes.
- [ ] Verify actual image SHA, migration outcome, Rails/Sidekiq/runtime health, then a new single-recipient test to authorized number final0891 using inbox1. Confirm text and image/caption delivery; never replay unknown deliveries.

## Review focus

Webhook wrappers must retain survey/notification execution fences and protected attachment authorization; campaign intent preparation must precede callback diagnostics; final errors must reconcile the exact delivery without erasing confirmed statuses; serialization must not make remote HTTP requests; current Service Desk schema and API contracts must remain present.

## Execution ledger

- Production f6f999f and candidate81ed diverged: six production commits and fourteen candidate commits beyond the shared base. The current worktree is isolated; two pre-existing shared component snapshots are excluded from this task.
- Merge is in progress. Service Desk conflicts are being independently inspected read-only; implementation remains with the primary agent.
- Resolved all conflicts. Service Desk source and backend compare identically to production; shared webhook execution retains both production wrappers and candidate diagnostics.
- Two canonical-message regressions fail against the production serializer (text and image), then the consolidated source passes333/333 examples in the isolated PostgreSQL database, including all campaign services/requests and shared message/webhook paths.
- The initial seven unrelated failures came from missing FRONTEND_URL in the local test container. Restoring the test URL fixed the bot and survey examples without product edits; the complete333-example rerun passed.
- Independent whole-tree review found no actionable static issues. Live send remains pending publication and deployment; old uncertain deliveries remain untouched.
