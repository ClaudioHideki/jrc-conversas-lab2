# Broker and Customer Master candidate regression plan

**Authorized goal:** Prepare CI for full JRC Vitest and the locally validated Broker/customer/campaign Rails regression without repeating the 85-minute suite on the constrained local host.

**Scope:** Maintain `.github/workflows/broker-customer-candidate.yml`, this plan and the combined-candidate plan. The application source is frozen. The principal implementer owns commit/push and CI execution; this subagent performs static checks only, with no local full suite, dispatch, image build, publication, deployment or new secret.

**Design:** Pushes on `codex/jrc-campaign-direct-audience-20261022` and manual dispatch may enter the workflow; both jobs also require that exact branch. Verify the checkout SHA and ancestry from `dc23e8e0348cae7881ce47a9f6ecca0803313b6c`. Both Ubuntu 24.04 jobs have a 45-minute limit and `contents: read` only.

- [x] Reuse the declared Node/pnpm versions, frozen lockfile, UTC and full default Vitest discovery with two workers and normal file parallelism. Require at least the current 568 files and zero failed/pending tests; never update snapshots.
- [x] Reuse the digest-pinned PostgreSQL/Redis services, Ruby/Bundler, native packages and schema preparation from the campaign/flow candidate workflows. Use the bounded official HTTPS APT setup from build-ghcr.
- [x] Give the Rails job a fresh PostgreSQL service container per job/run, with the existing approved concurrency database profile `jrc_rel_sd_r345_concurrency_test` and `JRC_SD_CONCURRENCY=1`. Before creation require the literal database name, test environment, localhost host and absent `DATABASE_URL`; dump migrations to a temporary schema. Run all Broker/customer services (including Bemtevi), all three Broker request files, campaign services/requests, the Broker webhook job, Contact Center/Operations/Service Desk requests and Service Desk services. Require at least 305 examples, zero failures and zero pending. The separate external TLS contract is not enabled.
- [x] Validate YAML, GitHub contexts/permissions, local spec paths and shell/embedded script syntax without executing the workflow. Check the final diff and source/schema preservation steps.

## References and boundaries

- `campaign-workflow-candidate.yml`: campaign services/requests and isolated Rails setup.
- `flow-broker-candidate.yml`: digest-pinned services, temporary schema and RSpec JSON count/failure/pending gate.
- `build-ghcr.yml`: bounded signed/TLS-verified APT setup through official HTTPS archives, without its image/publication steps.
- `service-desk-global-native.yml`: approved literal database profile and explicit concurrency opt-in. The profile name is not shared storage: each GitHub job/run creates its own PostgreSQL service container and runner-local port.
- The initial source inventory contained 568 matching Vitest files. Initial local evidence was 137 Broker/campaign examples plus 93 customer examples; the integrated selection now includes the modules above and preserves a 305-example floor.
- Local validation of this workflow remains static only. CI results below are separate remote evidence and do not establish production delivery. Commit, push and dispatch belong to the principal implementer under the user's existing authorization. This subagent performs no external mutations.

## Initial static validation ledger

- YAML 1.2 parsed with duplicate-key rejection; exactly two jobs and only `contents: read`. Push filtering and both job guards match the authorized branch; checkout SHA/ancestry checks preserve the verified full base SHA.
- Node reads `.nvmrc` (24.13.0); pnpm setup reads the existing `packageManager` declaration (10.2.0), with `--frozen-lockfile`. The actual configured application inventory is 568 test files. The command retains default file parallelism and contains no snapshot-update flag.
- PostgreSQL and Redis image strings matched both reference workflows byte for byte, including their SHA-256 digests. The initial database name depended on run ID/attempt; the concurrency correction below replaces only that name and its guard while preserving the service pins and rejection of a foreign `DATABASE_URL`.
- The initial eight RSpec file/directory arguments existed, including Bemtevi through the customer-services directory. The integrated workflow adds four module directories; all twelve must remain present. The three Broker request files are `jrc_broker_spec.rb`, `jrc_broker_inbox_spec.rb` and `jrc_broker_contract_spec.rb`; no external contract fixture or flag is supplied.
- Bash 5.2 syntax checking (`-n`) passed for all nine extracted run blocks. Syntax-only checks passed for embedded Node and Python. No shell block, database command or test suite was executed by validation.
- Prettier and whitespace checks passed for the candidate/plan. Existing campaign/flow/build workflows and application source were not edited by this scope. Temporary validation material lives under the existing local `.sessions` directory, outside the candidate source files.
- The principal implementer reviewed the complete workflow and confirmed its service pins, branch/ref/SHA checks, database guard, RSpec selection and inactive external TLS context. The prepared candidate is stable for the authorized commit/push/CI step.

## Integrated CI finding and concurrency correction

- Run `39978603091`, candidate `05c0a5e8bd2e4d1760925dfa3dbc81a9540ce29e`, Rails job `120499661872`: **1055 examples, zero failures, 11 pending, zero errors outside examples**. The job correctly failed its unchanged zero-pending assertion. This is not a passing regression result.
- The expanded Service Desk selection contains opt-in concurrency specs. Five examples require `JRC_SD_CONCURRENCY=1`; six additionally require the existing exact disposable-database allowlist. The original run-derived name is outside that allowlist. No assertion, product test, suite selection or allowlist is changed to address this configuration error.
- The minimal correction follows `service-desk-global-native.yml`: use `jrc_rel_sd_r345_concurrency_test` inside the fresh job-local PostgreSQL service and enable concurrency explicitly. Guard test mode, localhost, absent `DATABASE_URL`, the exact database literal and opt-in before database creation. Keep all twelve RSpec arguments, the 305-example floor, zero-failure/zero-pending assertions and the full Vitest job unchanged.
- The full Vitest job `120499661378` from the same run finished successfully: **580 files, 5703 tests, zero failures and zero pending**, in 598.21 seconds. Its source/snapshot/lockfile preservation step also passed. The result was collected before any corrective push, so the complete evidence was preserved.
- Static checks of the correction passed: YAML 1.2 with unique keys, exact branch guards and read-only permissions; all twelve RSpec paths exist; the full Vitest job, RSpec selection/assertions and service image pins match the previous revision. Prettier passed, all nine extracted run blocks passed `bash -n` in the local test PostgreSQL container without execution, and `git diff --check` passed. A fresh complete CI result is still required before an image can be approved; no image or deployment is established by the 1055-example report.
