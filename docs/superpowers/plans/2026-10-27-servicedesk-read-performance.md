# Service Desk read performance

**Goal:** Remove repeated authorization work from GET serialization while preserving every current response field and every command authorization.

**Baseline:** Production source `8637518b414cdd1ddff56e52a56ecbf88db46cda`; measured 20-ticket serialization 11,201 ms, 104 uncached and 13,719 cached SQL calls. One ticket initializes 144 operational contexts and evaluates TicketPolicy#show? 21 times. Diagnostics are separate read-only runner samples, not HTTP percentiles.

**Design:** An explicitly enabled, response-local projection decorates only the policy instances used by a GET Presenter. It reuses one freshly loaded native identity and memoizes policy checks within that response. Original policy classes and write services remain unchanged. Each new request constructs a new projection. GET operations already run in repeatable-read transactions. The collection preloads page associations without changing filtering, totals, pagination or authorization.

**Constraints:** Preserve tenant, unit, team, supervision and custom-role boundaries; no cross-request/global cache; no projection in write authorization; no migrations, ENV or resource changes. Preserve the newer conversation deduplication commit and unrelated local snapshot edits.

- [x] RED: page association read test failed with 15 queries instead of at most 3; projection tests initially failed because the response-only mode did not exist.
- [x] GREEN: add response-only policy projection and wire only GET presenters; preload page associations.
- [ ] Validate the existing policies, request contracts, lifecycle/SLA and regression suites. Compare query counts and timings on the same data.
- [ ] Review scope isolation and mutable policy inputs; inspect source/production updates before release.
- [ ] Publish immutable candidate only after relevant gates pass; retain current resource configuration and verify production behavior without sending messages.

## Implementation evidence

- Preserved new upstream commit `a183ca9c0fb87cbb818c704597776f5b30ef7089` (native conversation tools and resizable attendance list), fast-forward from the installed base; no conflicts.
- 77 local request/security/supervision examples passed. A separate 55-example serializer/policy run passed, including custom role and restricted-supervision parity, revocation on the next response and uncached command policies. Final changed-test run: 10 examples, no failures/pending.
- Same synthetic 20-ticket page: legacy 13,500 SQL events / 18,445 ms; response projection 1,244 events / 2,350 ms. Full response equality asserted. Timings are local single samples, not production HTTP percentiles.
- New projection file passes RuboCop. Existing touched legacy files retain their pre-existing style/complexity offenses; no broad formatting or autofix was applied.
- Independent static security review found no actionable regression; the response cache must remain local to immutable GET rendering within the existing consistent-read transaction.
