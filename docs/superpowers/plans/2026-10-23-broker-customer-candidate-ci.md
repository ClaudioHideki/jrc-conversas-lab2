# Broker and Customer Master candidate regression plan

**Authorized goal:** Prepare CI for full JRC Vitest and the locally validated Broker/customer/campaign Rails regression without repeating the 85-minute suite on the constrained local host.

**Scope:** Add only `.github/workflows/broker-customer-candidate.yml` and this plan. The application source is frozen. No local full suite, workflow dispatch, commit, push, image build, publication, deployment, new secret or change to an existing workflow is authorized here.

**Design:** Pushes on `codex/jrc-campaign-direct-audience-20261022` and manual dispatch may enter the workflow; both jobs also require that exact branch. Verify the checkout SHA and ancestry from `dc23e8e0348cae7881ce47a9f6ecca0803313b6c`. Both Ubuntu 24.04 jobs have a 45-minute limit and `contents: read` only.

- [x] Reuse the declared Node/pnpm versions, frozen lockfile, UTC and full default Vitest discovery with two workers and normal file parallelism. Require at least the current 568 files and zero failed/pending tests; never update snapshots.
- [x] Reuse the digest-pinned PostgreSQL/Redis services, Ruby/Bundler, native packages and schema preparation from the campaign/flow candidate workflows. Use the bounded official HTTPS APT setup from build-ghcr.
- [x] Give the Rails job a disposable database name derived from run ID and attempt, check its exact expected name before database creation, and dump migrations to a temporary schema. Run all Broker/customer services (including Bemtevi), all three Broker request files, campaign services/requests and the Broker webhook job. Require at least 230 examples, zero failures and zero pending. The separate external TLS contract is not enabled.
- [x] Validate YAML, GitHub contexts/permissions, local spec paths and shell/embedded script syntax without executing the workflow. Check the final diff and source/schema preservation steps.

## References and boundaries

- `campaign-workflow-candidate.yml`: campaign services/requests and isolated Rails setup.
- `flow-broker-candidate.yml`: digest-pinned services, temporary schema and RSpec JSON count/failure/pending gate.
- `build-ghcr.yml`: bounded signed/TLS-verified APT setup through official HTTPS archives, without its image/publication steps.
- The source inventory currently contains 568 matching Vitest files. The authorized local evidence is 137 Broker/campaign examples plus 93 customer examples; the CI Rails selection is a superset and retains the 230-example floor.
- Local validation is static only. CI has not run; installation on Ubuntu and complete test results remain unproven. Commit, push and dispatch belong to the principal implementer under the user's existing authorization. This subagent performs no external mutations.

## Static validation ledger

- YAML 1.2 parsed with duplicate-key rejection; exactly two jobs and only `contents: read`. Push filtering and both job guards match the authorized branch; checkout SHA/ancestry checks preserve the verified full base SHA.
- Node reads `.nvmrc` (24.13.0); pnpm setup reads the existing `packageManager` declaration (10.2.0), with `--frozen-lockfile`. The actual configured application inventory is 568 test files. The command retains default file parallelism and contains no snapshot-update flag.
- PostgreSQL and Redis image strings match both reference workflows byte for byte, including their SHA-256 digests. The database name depends on run ID/attempt and is checked against that exact expected name before creation; a foreign DATABASE_URL is rejected.
- All eight RSpec file/directory arguments exist, including Bemtevi through the customer-services directory. The three Broker request files are `jrc_broker_spec.rb`, `jrc_broker_inbox_spec.rb` and `jrc_broker_contract_spec.rb`; no external contract fixture or flag is supplied.
- Bash 5.2 syntax checking (`-n`) passed for all nine extracted run blocks. Syntax-only checks passed for embedded Node and Python. No shell block, database command or test suite was executed by validation.
- Prettier and whitespace checks passed for the candidate/plan. Existing campaign/flow/build workflows and application source were not edited by this scope. Temporary validation material lives under the existing local `.sessions` directory, outside the candidate source files.
- The principal implementer reviewed the complete workflow and confirmed its service pins, branch/ref/SHA checks, database guard, RSpec selection and inactive external TLS context. The prepared candidate is stable for the authorized commit/push/CI step.
