# Real LAB2 → HTTPS → Broker custody laboratory

This is an explicit, opt-in fixture. It must not be used against production, customer databases, numbers or shared queues. It starts no Broker transport/messaging worker and does not contact WhatsApp.

## Exact gate

Two independent LAB2 consumers use the same materialized Rails code with separate fresh PostgreSQL databases (`jrc_broker_https_a_test`, `jrc_broker_https_b_test`) and Redis databases0/1 on a fixture-only Redis. Real account, inbox, conversation and message IDs intentionally collide between consumers. Each maps to a different Broker organization/integration/instance.

The receiving API is the official Broker image pinned by registry digest, running its actual `buildApp`, `createChatwootService`, `integrations.ts` callback, HMAC verification, PostgreSQL migrations, `jrc_app` role and tenant transactions. The bootstrap reuses the integration PostgreSQL/global-role-lock helpers. The database helper's destructive `dispose()` is never called. Provider instances are synthetic `CREATED` fixtures; no physical worker consumes `CHATWOOT_REPLY` jobs.

The claimed result is **LAB2_TLS_BROKER_DURABLE_CUSTODY**: one real attendance observation and one real reply job per tenant, after retries, with producer obligations settled as delivered to HTTP ingress. It is not physical WhatsApp delivery, stock Chatwoot/CCLX homologation, a session/QR test, two installed Chatwoot UIs, production boot/configuration validation, or full bidirectional messaging.

`X-Chatwoot-Delivery` and body SHA256 must remain identical across attempts at the producer/proxy. The Broker does **not** deduplicate by that header. Its tested keys are `message:<message_id>` and `reply:<destination_revision>:<account_id>:<inbox_id>:<message_id>`, scoped by organization/integration/destination/account/inbox. PostgreSQL counts and cross-tenant reads prove the receiving effect and RLS isolation.

## Fault sequence

1. Cold-load the reviewed host schema110000 into two new Rails DBs, seed API inboxes/secrets and create two Broker organizations. Capture actual outgoing `Message`/outbox rows in committed transactions, using the real Sidekiq adapter.
2. Start only the CA-validating TLS proxy. The real Broker process is still absent. Run each real Sidekiq worker, one at a time: its real SafeFetch POST gets503 from the proxy's actual failed upstream connection. The obligation must become pending without receiver custody.
3. Start the real Broker ingress. Positive TLS must work; separate real SafeFetch processes must reject the untrusted CA and wrong hostname. A signed A payload sent to B's route must receive401 and leave B unchanged.
4. Arm A's proxy barrier and recover its pending obligation. After the real API replies200 (after COMMIT), the proxy independently queries Broker PostgreSQL/RLS and requires exactly one observation/job before withholding the producer ACK.
5. A's real Sidekiq process observes that committed barrier while its obligation is running and kills **itself with SIGKILL**. The Docker exec supervisor must observe exit137. The worker lease remains running. B recovers normally.
6. Explicitly expire only A's fixture lease (this does not claim five minutes elapsed), run the real recovery job and enqueue a duplicate. The resumed worker reuses the same obligation/delivery/body. A settles delivered with attempts3, B with attempts2; the Broker still has one observation/job for each, including colliding IDs.

## Transport/process boundaries

No SafeFetch method is stubbed or prepended. The worker verifies its source location and consumes only its own queue, concurrency1. It boots Rails as a Sidekiq client before CLI startup so the shared/general cron is never loaded. `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` is set **only on these fixture processes**, because the Docker network is internal; production SSRF files/settings are unchanged.

The CA and leaf certificates are generated only for this run. `SSL_CERT_FILE`/Node's explicit CA trust apply only to the fixture processes; `VERIFY_PEER` remains enabled. Nothing is installed into the OS trust store. Wrong-CA/wrong-hostname probes require an actual SSL error, not a timeout/refused connection.

The launcher uses a new `--internal` network, no published ports, separate PG containers/volumes and an immutable Broker API image. It attaches only the existing label-verified Rails laboratory to that network. It does not change the runtime/workflow of production. Node entrypoint is explicitly overridden so no default production worker/bootstrap is started.

Private CA keys, synthetic credentials and private manifests live in a new ACL-restricted Windows temporary directory, outside Git/workspace ZIP paths. Only selected metadata, hashes, state snapshots and TLS results go to the public evidence directory. The proxy never writes webhook body, HMAC signature or secret to logs.

## Commands and status

Lightweight checks (no Rails/Redis/HTTP):

```sh
bundle exec ruby spec/homologation/broker_https_unit_test.rb
```

Windows orchestrator, **only after the shared heavy-runner slot is released**:

```powershell
$env:BROKER_HTTPS_EXECUTE = '1'
./spec/homologation/broker_https_lab.ps1 -Execute `
  -BrokerImage 'ghcr.io/claudiohideki/brokerjrcia-api@sha256:ae6229ed0d67cf2bd582291e4c6275dd641d57fbb75c88931fee14476cff6cd1' `
  -ImageIdentityPath '<reviewed broker-api-image-identity.json>' `
  -BrokerSourceSha 'ea7dc741d0c63792a969dddeac2bd35b6cbdf514' `
  -BrokerRoot '<reviewed Broker worktree>' -Lab2Root '<reviewed LAB2 worktree>' `
  -OutputRoot '<public evidence directory>'
```

The launcher stops only nonce-labelled fixture containers and detaches the network link it created. It preserves containers, volumes, every DB and private fixture directory for review. It never removes volumes/DBs, truncates tables, starts a backup/restore, creates ZIPs, commits or pushes. A failed run remains failed; a missing/false gate is not converted into success.

Cleanup checks command exit codes and then independently observes each owned container stopped and Rails detached. Unreadable inventory, wrong ownership, an unsuccessful command or an unconfirmed final state makes cleanup unverified and the run nonzero. A primary stack failure remains the primary error if cleanup also fails. `result.json` and the positive cleanup message are emitted only after verified cleanup. The injected-runner contracts can run without Docker or Pester: `powershell.exe -NoProfile -File spec/homologation/broker_https_cleanup_test.ps1`.

Image identity is checked against the reviewed registry index digest and platform image ID artifact. Source revision is attributed explicitly to the reviewed release evidence; this image has no OCI source-revision label, and no such label is invented. A present contradictory label is rejected. The first preflight stopped before creating any stack because it initially required that absent label; it is not a receiver/transport test result.

Current preparation evidence: the first pure-Ruby contract RED had8 runs (5 failures/3 errors from explicit not-implemented guards); initial GREEN8/17assertions passed. Redis-isolation RED then required separate Redis databases; final pure-unit GREEN is **9 runs/19 assertions, zero failures/errors/skips**. This does not replace the real-stack run, whose result must be recorded separately.

## Recorded real run: 2026-11-02

Run `e4603a88-5311-42e9-b3d2-319cdeae8f5a` completed with launcher exit0. Public evidence is under the workspace's `output/specs-20261102/broker-https-e4603a88-5311-42e9-b3d2-319cdeae8f5a/`.

- Both fresh Rails DBs produced actual account/inbox/message IDs1/1/1. Rails7.1.5.2 and Sidekiq7.3.1 were recorded by the worker.
- Both obligations first became pending after a real HTTPS request reached the proxy while the Broker process was absent (upstream DNS `EAI_AGAIN`, HTTP503 returned).
- Trusted TLS succeeded. Wrong CA and wrong hostname failed with actual `OpenSSL::SSL::SSLError`; A's valid signature on B's integration returned401 without changing B.
- A's receiver committed one observation and one reply job before the proxy withheld the ACK. The actual Sidekiq worker self-SIGKILL exited137 with the obligation running/attempts2. Only that fixture lease was explicitly expired before real recovery.
- Final A: delivered/attempts3. Final B: delivered/attempts2. Each organization had one real observation and one `CHATWOOT_REPLY` job, cross-tenant observation count0. Delivery UUID and body SHA256 remained stable across attempts. Jobs remained PENDING; no physical worker consumed them.
- All six nonce-labelled containers stopped with exit0 during cleanup, with no published ports. The Rails network link was detached. The worker SIGKILL137 is a separate asserted process exit, not a PostgreSQL/container shutdown inferred as a worker crash.

Earlier failed preflights/runs remain failed and preserved. They exposed fixture setup requirements: absent image revision label/Docker index identity semantics, atomic organization owner creation, a conversation committed/reloaded before message capture, and an explicit stdlib `tempfile` require for the standalone TLS probe. No production constraint, SafeFetch implementation, authentication check or receiving deduplication rule was relaxed.

After this real run, only Ruby layout/naming/UTC-certificate style was adjusted. Explicit fixture guard and X509-builder complexity has narrowly documented local RuboCop exceptions; no global lint configuration changed. The final source passed pure-unit9/19, all six Ruby parser checks, RuboCop6files/0offenses, three certificate checks, three JS parser checks and PowerShell parsing. The full stack was not repeated after those style changes.

## Final cold run on committed source

The original `e4603a88` record above remains historical and is not attributed to commit283378b1. A later complete cold run, `bb759c3f-76e6-4f87-a9a8-d57d172276b3`, passed with launcher exit0 on exact harness source commit **`f1ffd1b9de2bc773ad8c1983f25f1dd352579bb5`**, including the final Ruby style and fail-closed cleanup. This closes the earlier post-style rerun limitation for that source commit.

The preflight matched Git blobs for all13 fixture files and recorded LF-normalized SHA256 hashes. The13 materialized Rails copies matched those hashes after the run. The receiving Broker image remains the separately pinned EA image above. [`broker-https-custody-final-20261102.json`](../../docs/release-integrada-jrc/evidence/broker-https-custody-final-20261102.json) retains the exact tested revision, hashes and sanitized results.

Final result: A delivered/attempts3, B delivered/attempts2, one observation and one PENDING reply job per organization, cross-tenant0, stable delivery UUID/body hash, real TLS positive/two certificate negatives, cross-signature401, and worker SIGKILL137 after receiver COMMIT/withheld ACK. Cleanup returned Verified=true, Errors=[], all6Stopped=true and RailsDetached=true before `result.json` existed. An independent final inventory also observed all6 containers exited0 and zero published ports.

Final checks: cleanup contracts15/15 on Windows PowerShell (initial RED3pass/8fail; null-inventory RED14pass/1fail), pure Ruby9tests/19assertions/0failures/0skips, RuboCop6files/0offenses, and Ruby6/JS3/PowerShell3 parsers. The following documentation-only commit changes this README/checkpoint/evidence, with executable fixture bytes compared against f1ffd1b9 and left unchanged. It does not claim the documentation commit itself was the source revision executed by the stack.
