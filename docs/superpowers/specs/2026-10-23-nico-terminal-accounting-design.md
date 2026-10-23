# NICO terminal provider accounting

The current runtime accumulates valid provider usage before validating structured output, but loses that receipt when every output is invalid. Rails then retains the full reservation because an error without a receipt is correctly uncertain. This source defect is confirmed; it is not proof of the cause of the five historical unknown production inferences.

## Approved approach

Transport a bounded, authenticated error receipt only when all attempts are covered by valid provider usage or the existing explicitly marked conservative estimate. The receipt includes a version, complete marker, attempt count, model, usage, request ID and Account ID; it carries no action, prompt, credential, provider body or exception text. Rails validates the exact scope/schema and records the existing idempotent usage event before surfacing the original controlled failure. Invalid output never becomes an executable action.

Keeping every terminal error unknown avoids unsafe release but discards available evidence. Releasing on an error code or a partial first-attempt receipt would incorrectly treat an unknown second attempt as free. A durable runtime journal is a separate, larger follow-up for lost responses and restarts; this bounded change does not invent that proof.

Parent approved this minimal implementation on 23 October. Preserve old unknown records, limits, provider settings and all unrelated modules. No production operations, paid calls, commit, push or publication in this task.

## Acceptance

- Two invalid but fully metered answers fail the operation and replace only its own new hold with one exact usage event.
- A valid measured attempt followed by timeout, transport failure, malformed/unmetered response or invalid usage remains unknown with the entire hold; no partial receipt is offered as complete.
- Existing conservative estimates remain explicitly estimated and counted.
- Foreign/mismatched/malformed receipts, unknown versions and absent complete proof never release the hold.
- Reapplying the same receipt to its existing ledger does not duplicate accounting or invoke the provider. Runtime HTTP replay/idempotency and recovery after a lost response are outside this bounded fix. Error logs remain a strict non-PII allowlist.
- Existing runtime error bodies without a receipt stay compatible. Historical holds and action authorization are unchanged.
