# Campaign webhook failure implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop reporting a locally rejected campaign message as an indefinitely sending delivery, without retrying or erasing uncertainty.

**Architecture:** Keep the existing signed webhook and reserved-intent protocol. Record only a bounded server-owned diagnostic (phase, exception class, HTTP status, outcome and callback-admission markers) on campaign messages. Reconcile a correlated local failure into the campaign delivery before polling the remote receipt; a definitive rejection fails the recipient and pauses the campaign, while legacy/ambiguous outcomes remain unknown.

**Tech Stack:** Rails, ActiveRecord/PostgreSQL, ActiveJob/Sidekiq, existing SafeFetch and WebMock/RSpec.

**Spec:** Root-approved investigation/proposal of 23/10/2026: Message2054 failed with a generic rejection while Delivery6 remained sending; a missing JSON marker caused the original reservation refusal and is corrected by the root in a separate change.

## Global constraints

- Reuse the existing isolated JRC worktree. No production changes, commit, push, deployment, provider calls or new dependencies.
- Do not edit the message JSON partial/controller contract owned by the root, or Sender/resolver/image normalization owned by other agents.
- Do not infer delivery or definite refusal from the legacy generic error alone. Preserve `unknown`, `sent`, `delivered` and `read`; never replay a message.
- Require exact Account/inbox/message/delivery/campaign/actor/conversation correlation. Normal conversations keep the existing behavior.
- Store/log no URL, content, request/response body, secret or raw exception message.
- Retain the current bounded retry policy. A prior callback timeout, incomplete attempt or accepted callback prevents a later rejection from being classified as proof that no callback was admitted.

## Review focus

1. Timeout then permanent refusal, or process interruption after callback start: retain uncertainty.
2. A late failure cannot downgrade a confirmed delivery or a replied recipient.
3. Legacy generic rejection: stop misleading polling by retaining unknown rather than fabricating a failure proof.
4. Foreign or stale correlation: do not modify another delivery or ordinary conversation.
5. Diagnostics: only fixed phases, safe exception class, numeric status and bounded state; no payload/credential leakage.

## Task 1: Reproduce and pin the failure/outcome contract

**Files:** Create `spec/services/jrc_campaigns/broker_delivery_failure_spec.rb`; extend existing webhook job regression only if needed.

- [x] Write database-backed examples through the real Trigger, WebhookDelivery and BrokerStatusJob: permanent intent/callback refusal, context change, legacy rejection, timeout followed by refusal, exhausted retry, duplicate processing, confirmed/unknown states, ordinary/foreign message, and sanitized diagnostics.
- [x] Run the focal file against the guarded local Rails test database and observe functional RED before product edits.

## Task 2: Preserve causal diagnostics and propagate local campaign failures

**Files:** Modify `lib/webhooks/trigger.rb`, `app/services/jrc_broker/webhook_delivery.rb`, `app/jobs/jrc_campaigns/broker_status_job.rb`; create `app/services/jrc_campaigns/broker_delivery_failure.rb` and `app/services/jrc_broker/webhook_diagnostic.rb`.

**Interfaces:** `WebhookDelivery` records a callback start/success and sanitized failure for campaign messages only. `BrokerDeliveryFailure.call(message:, delivery: nil, failure_code: nil)` returns true only for a handled correlated local failure; it rechecks terminal state under the delivery lock. `BrokerStatusJob` invokes that reconciliation before any remote receipt poll.

- [x] Implement the smallest journal needed to distinguish definite rejection from incomplete/previously accepted callback attempts, outside HTTP-spanning database locks.
- [x] Propagate confirmed rejection through the native status tracker and pause the campaign. Preserve ambiguous/legacy results as unknown and stop polling, without sending another message.
- [x] Keep ordinary webhook handling and retry configuration intact; add safe structured error logs.
- [x] Run focal tests to GREEN, including timeout-to-refusal and late-result precedence.

## Task 3: Adjacent regression and delivery

- [x] Run the new focal plus existing campaign integration, webhook job/listener/Trigger and status-tracker coverage in one coordinated Rails pass.
- [x] Run RuboCop on changed Ruby files, inspect the diff and run `git diff --check`.
- [x] Record exact RED/GREEN evidence, source files and remaining limits. Obtain independent review. Leave changes local for root review.

## Execution ledger

- Design and conservative legacy behavior approved by root before implementation. No Enterprise override for these JRC campaign/webhook services was found.
- RED: 16 examples, 13 expected functional failures and 3 existing guards passed. Log `.sessions/campaign-webhook-failure-red-20261023.log`; no setup errors.
- Local failure reconciliation takes Delivery then Message locks, matching the Sender order, and never spans HTTP. Callback start refuses an already failed message under the Message lock so concurrent stale jobs cannot dispatch after a definitive local refusal.
- First GREEN: 16 examples / 0 failures. Subsequent changes extract small methods and format the new code; no new send/retry path.
- Additional RED: 2/2 expected failures when the campaign marker is removed immediately before acquiring the Message/Delivery lock. Recheck the marker after locking, keeping ordinary messages outside campaign mutation.
- First adjacent GREEN after marker rechecks: 123 examples / 0 failures.
- Independent review found two more concrete gaps: a TestDelivery's own Account could differ from its Inbox Account, and a stale `running?` read could overwrite a cancellation with `paused`. Both were reproduced as 2 examples / 2 functional failures. Log `.sessions/campaign-webhook-failure-review-red-20261023.log`.
- TestDelivery now requires its own Account to match the native Message. The campaign pause uses an Account/ID/status `running` compare-and-set after Delivery/Recipient/Execution reconciliation. A deterministic PostgreSQL interleaving cancels immediately before the pause write, proving cancellation is preserved; no thread scheduling or production record is involved.
- Final focal GREEN: 20 examples / 0 failures. Log `.sessions/campaign-webhook-failure-review-green-20261023.log`.
- Final adjacent GREEN: 125 examples / 0 failures, 44.13 seconds plus 6.27 seconds boot. Files: new failure spec; campaign Broker integration; JRC webhook job; generic webhook job; WebhookListener; Trigger. Log `.sessions/campaign-webhook-failure-final-20261023.log`.
- RuboCop is clean for the three new Ruby files and changed Trigger (4 files). Across all 6 Ruby files, 7 complexity offenses remain in existing WebhookDelivery/StatusJob methods. The same 7 methods/offenses were reproduced against HEAD before the patch; `BrokerStatusJob#perform` adds one local-failure guard (cyclomatic 29 to 30). No lint suppression was added for them. Logs `.sessions/campaign-webhook-failure-rubocop-owned-green-20261023.log`, `...-rubocop-six-final-20261023.log`, `...-rubocop-baseline-20261023.log`.
- Independent final read-only review by `audit_nico_credit_actions` confirmed both Account/cancellation findings closed and found no new blocker in the inspected diff. The reviewer did not execute tests; 125/125 is the implementer's fresh guarded PostgreSQL run. `git diff --check` passed.

## Boundaries and remaining verification

- Local PostgreSQL/WebMock regression only; no provider requests, production edits, historical reconciliation, automatic resend, commit, push or deployment were performed by this task.
- Callback acceptance is admission evidence, never proof that Evolution/WhatsApp delivered a message. Legacy failures without trusted diagnostics remain unknown.
- The Broker receipt default `queued` when no observation exists is unchanged in this correction. Local failed campaign messages now reconcile before receipt polling, so that default cannot keep this local failure indefinitely sending.
- Existing `BrokerStatusJob` remote-receipt/timeout branches still use their earlier `reload.running?` then `pause!` pattern. The new local-failure branch uses the safe conditional transition; refactoring all older status branches is a separate change.
- The root owns the original canonical-message serializer fix and its release. This task does not change that partial/controller contract or mutate the paused production campaign.
