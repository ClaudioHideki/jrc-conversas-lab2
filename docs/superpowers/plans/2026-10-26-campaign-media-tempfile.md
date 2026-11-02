# Campaign remote media tempfile lifetime

Scope: `JrcCampaigns::BrokerMessageSender` at cfd5099. Preserve the two pre-existing frontend snapshot changes. No commit, push, deployment, real message or replay in this task.

## Cause and regression

The sender creates an ActiveStorage attachment inside `delivery.with_lock`. For a fetched PNG/JPEG/document, the attachable still refers to SafeFetch's Tempfile. SafeFetch closes and unlinks it when its block exits; ActiveStorage's upload waits for the outer transaction commit. Converted WebP uses StringIO and conceals this timing defect in existing specs. The regression must use the real SafeFetch fetcher and ActiveStorage storage, with HTTP/DNS replaced only by synthetic responses and committed test fixtures.

## Bounded implementation

1. Prove successful fetched media fails before the fix, with real transaction commit.
2. Persist uploaded bytes while SafeFetch owns a live stream, using the ActiveStorage blob path already established in Flow/proposal delivery.
3. Track only blobs created for this send, clean their storage on a rollback/upload failure, and retain committed attached blobs if an after-commit callback raises.
4. Preserve SSRF public-only mode, MIME and 10 MB input limits, WebP normalization, canonical correlation and idempotency.
5. Run the focused new specs, campaign/SafeFetch adjacent specs and focused Ruby lint. Record RED/GREEN and hashes under `.sessions`.

Enterprise has no BrokerMessageSender or BrokerImageNormalizer override; no shared API or attachment authorization contract changes are intended. The stale error displayed after confirmed READ is a separate StatusTracker/UI issue and is excluded.

## Local results

- Initial RED: 9 examples, 6 failures. Real PNG/JPEG/document uploads attempt to consume a closed SafeFetch stream after commit; SSRF/MIME/size guards pass.
- Expanded RED: 12 examples, 8 failures, including external rollback cleanup and retaining committed media when a callback fails.
- Focal GREEN: 12 examples, 0 failures. Final adjacent run: 174 examples, 0 failures across the new media spec, image normalizer, Broker integration/delivery failure/conversation resolver and SafeFetch.
- An intermediate adjacent run had one test-only NameError after removing an any-instance stub; the literal dispatcher event fixed it. Both attempts are retained in evidence.
- RuboCop: the helper and new spec have no offenses. The sender retains the same 12 inherited offense locations; its existing attach-media ABC measure changes from 41.55 to 42.49. Full focused lint therefore still exits 1; no claim of a clean repository lint.
- Rails/ActiveStorage 7.1.5.2 transaction hooks were inspected in the installed runtime. `BrokerMediaUpload` uses the same create/upload stages as `create_and_upload!`, registering its new server-owned key before upload. Rollback removes the external object; commit and later callback failures preserve it. The original library blob path is unchanged.
- Source hashes, RED/GREEN logs, runtime equality, untouched snapshot hashes and limitations are recorded in `.sessions/campaign-media-tempfile-manifest-20261026.json`. No generic suite, production send, replay, build, commit or deployment was performed.
