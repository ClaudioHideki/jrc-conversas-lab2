# NICO Terminal Accounting Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans; implement locally in the current JRC worktree with TDD, without publication.

**Goal:** Preserve a complete terminal provider receipt when structured output fails, without releasing unknown consumption or executing an invalid action.

**Architecture:** Runtime error carries only a scoped, bounded complete accounting receipt. Rails validates that proof and uses the existing Account-locked ReservationLedger exactly once before raising the original failure.

**Tech Stack:** Node 24 TypeScript runtime, existing elizaOS engine, Rails/PostgreSQL ledger, Node test and RSpec.

**Spec:** `docs/superpowers/specs/2026-10-23-nico-terminal-accounting-design.md`

## Constraints and review focus

- No production/paid calls, limits, migrations, credentials, old holds, campaigns, Service Desk or client changes.
- Do not treat partial first-attempt usage as complete after a later uncertain attempt.
- Strict Account/request/schema/version/attempt bounds; no foreign receipt, executable output or secret in an error body/log.
- Keep existing successful response and old error contracts compatible.
- Coordinate all Rails/engine tests on the shared local host; use only the disposable test database.

## Task 1: terminal receipt through the real runtime error path

- [x] Add failing provider tests: two invalid measured outputs; one-attempt measured schema failure; estimated first output and measured invalid repair; later timeout/transport/unmetered/usage-invalid remains uncertain; error body/log privacy.
- [x] Run the new tests and observe the missing-receipt failures.
- [x] Add minimal error receipt to `src/provider.ts` and `src/errors.ts`; scope it in `src/server.ts`. No tools execute from this path.
- [x] Repeat focused tests, real engine/HTTP contract and full runtime suite/typecheck when existing dependencies are available.

## Task 2: consume only complete matching proof in Rails

- [x] Add failing real-client/ledger tests in `spec/services/jrc_nico/operational_inference_spec.rb`: exact receipt settles once while operation fails; mismatched request/Account, invalid version/complete/attempts/usage preserve hold; receiptless legacy errors preserve hold; other historical unknown holds untouched.
- [x] Observe RED on the guarded disposable PostgreSQL database.
- [x] Validate strict receipt with `TerminalAccounting` and the existing `RuntimeClient` usage validator before raising the controlled terminal error, then reuse `ReservationLedger#receipt!`; no partial receipt support or ledger relaxation.
- [x] Run focal and accounting/async/action regressions, Ruby lint and diff checks; record exact totals and remaining test limits.

## Evidence ledger

- Diagnosis: 20 October attachment shows RackTimeout at 15 seconds and pool timeouts in the historical synchronous request. Current source already plans asynchronously and releases idle DB connections before runtime HTTP.
- Current source defect: `structuredResponse` accumulates usage, throws `NicoError` on final invalid output, `errorResponse` emits only the code; Rails raises before its receipt path. Old unknown record causes remain unproved.
- Pre-flight: runtime complete receipt is the only new interface consumed by Rails. Existing error without receipt is deliberately compatible and conservative.
- Ruling: do not add a durable runtime journal, paid retry or administrative release in this minimal fix. Response loss/restart still requires independent evidence and remains unknown.
- Provider RED: 21 cases, 4 missing-receipt failures; GREEN: 21/21. Timeout/transport/unmetered/invalid usage continue to omit complete accounting.
- Rails RED: 34 cases, 2 functional failures (fully known usage incorrectly retained as unknown/full hold); focal GREEN 34/34 before adding a stricter null-marker case.
- Real engine/HTTP RED: in a disposable workspace mirror, the original committed server omitted the receipt (1/1 failure). Copying only the corrected server produced GREEN 1/1 through the real elizaOS engine and HTTP, preserving rate-limit/auth errors and log redaction. Existing runtime dependencies were reused read-only from another worktree with identical lockfile hash; no install or dependency change.
- First broader Rails run: 194 cases, 4 failures, all in existing bot/delegation paths lacking FRONTEND_URL in the local test process. Three expose OwnershipGuard's required ENV directly; the fourth is a request 500 in the same setup. Rerun with the workflow's synthetic HTTPS origin is pending; these failures are not silently excluded.
- Strict null-marker RED: 1 case failed because a present null estimate marker was accepted and released its hold. The validator now accepts an omitted marker or boolean true only.
- Corrected-environment Rails regression: all 195 cases passed in one invocation, zero failures/pending (83.89 seconds excluding boot), including the stricter marker case, real-client ledger accounting, unknown preservation, capacity limits, runtime connection release, asynchronous planning, native operations/domain actions and administrative legacy review. The four setup failures are resolved by the workflow's required FRONTEND_URL=https://host.example.test, without product/spec relaxation.
- Final Rails after parser extraction: 35/35, zero failures/pending. The earlier 195/195 broad regression and this final focal are separate runs, not one invocation.
- Ruling: isolate the new wire metadata parser in `app/services/jrc_nico/terminal_accounting.rb` because inlining it added class-size/cyclomatic offenses to the already complex RuntimeClient. Preserve old methods and the existing usage validator; this is a readability extraction only, followed by a fresh focal run.
- Final Ruby lint: new TerminalAccounting file has zero offenses. Existing RuntimeClient has 27 and the existing OperationalInference spec has 7, exactly matching the respective committed-source baselines analyzed with RuboCop --stdin and the same paths. No new offense remains; this is a clean delta, not a claim that both old files are lint-clean.
- Runtime verification environment: the local Rails image has Node but no npm. An offline Linux attempt then exposed borrowed Windows dependency symlinks (`zod` unavailable); no dependency was installed or lockfile changed. The first full host pass ran all 47 tests and had one PGlite initialization failure in another legacy fixed Linux temporary directory. A disposable source mirror now changes only the two fixed temporary database paths (`server.test.ts` and `runtime.test.ts`) into fresh workspace paths; every assertion, test, product source and lockfile remains identical.
- Final full runtime: `npm.cmd test` passed **47/47**, no failures/skips/cancellations, 88.25 seconds; then `npm.cmd run lint` (tsc --noEmit --noUnusedLocals --noUnusedParameters) and `npm.cmd run build` both exited 0. It exercises the real engine/HTTP, two-account concurrent isolation, invalid output, repair, cancellation, usage integrity and log allowlist with simulated provider HTTP only. This is Windows local evidence; Linux image CI remains the release gate.
- Final diff check passed for all ten task files. No production changes, paid calls, reservation cleanup, image, commit or push by this worker.

## Exact handoff files

1. `app/services/jrc_nico/runtime_client.rb`
2. `app/services/jrc_nico/terminal_accounting.rb`
3. `services/nico-runtime/src/errors.ts`
4. `services/nico-runtime/src/provider.ts`
5. `services/nico-runtime/src/server.ts`
6. `services/nico-runtime/test/operation-http.test.ts`
7. `services/nico-runtime/test/provider-reliability.test.ts`
8. `spec/services/jrc_nico/operational_inference_spec.rb`
9. `docs/superpowers/specs/2026-10-23-nico-terminal-accounting-design.md`
10. `docs/superpowers/plans/2026-10-23-nico-terminal-accounting.md`

## Commands and release limits

Guarded Rails selection: `RAILS_ENV=test`, `POSTGRES_DATABASE=jrc_campaign_audience_test`, `POSTGRES_HOST=jrc-audience-pg-20261022`, DATABASE_URL absent and FRONTEND_URL=https://host.example.test, in the existing `jrc-audience-rspec-20261022` container. Run `bundle exec rspec` with these twelve paths:

```text
spec/services/jrc_nico/operational_inference_spec.rb
spec/services/jrc_nico/reservation_ledger_spec.rb
spec/services/jrc_nico/reservation_reconciler_spec.rb
spec/services/jrc_nico/run_capacity_spec.rb
spec/services/jrc_nico/runtime_client_spec.rb
spec/services/jrc_nico/runtime_connection_spec.rb
spec/requests/jrc_nico_async_planning_spec.rb
spec/requests/jrc_nico_json_reliability_spec.rb
spec/requests/jrc_nico_operations_spec.rb
spec/requests/jrc_nico_capacity_spec.rb
spec/services/jrc_nico/domain_actions_spec.rb
spec/services/jrc_nico/legacy_reservation_review_spec.rb
```

Runtime commands are the three existing package scripts above, using already installed frozen dependencies. Local full log: `.sessions/nico-terminal-runtime-final.log`; Rails summaries and baseline lint comparisons: `.sessions/nico-terminal-accounting-*.json`. These private verification artifacts and dependency links are not handoff source files.

The runtime lives in this same JRC repository but deploys as a **separate nico-runtime image**. A future authorized release must publish both the app and runtime components from the reviewed SHA. No migration, new ENV or limit adjustment is required. App-first or runtime-first rollout remains conservative with older error bodies/clients; only the paired versions preserve new terminal receipts. Existing unknown records are never automatically reinterpreted.

Lost responses, process restart and runtime HTTP idempotency still need the separate durable-journal design. This fix proves the current source defect and prevents new fully known errors losing their receipt; it does not prove the cause or settlement of the five historical unknown inferences, nor certify all actions/voice against a live provider.
