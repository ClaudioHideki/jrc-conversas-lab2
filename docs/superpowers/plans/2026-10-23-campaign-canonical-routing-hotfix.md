# Campaign sender, recipient routing and audience preview correction

Approved scope: repair the existing campaign path for the selected inbox and recipient without changing historical contact identities, replaying uncertain sends, activating bots or changing the provider's conversation-cycle authority. No migration, dependency, environment variable or separate module is required.

## Diagnosis and implementation

- A contact-inbox source is an opaque identifier. It can be a UUID, `jrc-` identifier or LID and must not be interpreted as the recipient phone. Validate the selected Contact's normalized phone plus the exact Account, Inbox, Conversation and ContactInbox relationship instead.
- Multiple legitimate links are preserved. Before creating a new campaign or individual-test Message, inspect at most 20 coherent local conversations using the existing scoped, read-only Broker attendance GET. Select exactly one positive snapshot with matching organization, integration, Account, inbox, contact, conversation **display ID**, destination revision, UUIDs and revision fields. Never select by source prefix, first record or last activity when a positive Broker map exists.
- An explicitly assigned recipient conversation stays pinned and requires its own positive proof. Two positive proofs, more than 20 candidates, malformed/context-mismatched snapshots or HTTP 403/409/5xx fail closed. Only an unpinned lookup with no positive map retains the existing fresh-selection path, still subject to the Broker worker's canonical GET and conversation-cycle guard. A 404 proves absence only for that candidate.
- Lookup HTTP runs before the caller's local locks. Recheck native administration, active Account, configuration/callback, contact phone and opaque link identities after the lookup. Revalidate the chosen native relationship at Message creation. Message, delivery metadata and recipient contact/conversation correlation commit in one transaction before the callback.
- The authenticated Accounts conversation `show` response exposes only `contact_inbox: {id, contact_id, inbox_id, source_id}` from that actual conversation; a legacy absent link returns null. The shared partial and widget response are unchanged. No pubsub token is exposed.
- A Broker transport read failure during campaign response serialization yields `approval_valid: false`, so a successfully persisted pause can return its actual state. Approval and send checks continue to fail closed.
- The audience-preview API wrapper now forwards only the four supported recipient pagination/search options outside `campaign`. The old summary-only request and Account-scoped route stay unchanged. This fixes the manager showing an eligible count without any recipient rows.
- The dashboard categorizes a contact-binding mismatch separately from invalid phone numbers. Image caption preservation and bounded static WebP-to-PNG handling are documented in `2026-10-23-campaign-webp-normalization.md`.

## Evidence ledger

- Canonical identity/GET/transaction/pause fixes: functional REDs were observed before implementation. The first adjacent Rails regression passed 240 examples with zero failures and zero pending before the attendance resolver was added.
- Attendance resolver functional RED: one real DispatchStepService example selected the newer unmapped conversation instead of the sole Broker-proven older conversation. This failed on the conversation ID, without a real provider call.
- First combined resolver/canonical/WebP run: 100 examples, one failure. All 23 new resolver cases and 29 WebP cases passed. The remaining earlier pinned-conversation fixture deliberately returned 404; it was updated to provide the exact positive attendance snapshot now required, retaining its no-reroute assertions.
- Audience wrapper: RED 3 failures/4 tests, then GREEN 4/4 on the actual wrapper. Tests cover the unchanged summary request, all four options, allowlisting without overriding campaign, actual paginated response and Account switching.
- Final combined Rails regression: **102 examples, zero failures and zero pending**, 44.52 seconds plus 17.93 seconds boot, on the final unified source. This includes 25 attendance/cache cases, 46 canonical/intent/pause cases, 29 image-normalizer cases and two dashboard-classification cases. The two added cache cases preload contact/pinned-conversation associations, change them through another native record after lookup, and prove the final transaction fails without leaving a Message or delivery correlation.
- Final focused RuboCop: six files, zero offenses (resolver service/spec, image normalizer service/spec, intent validation and new dashboard spec). Existing whole-file lint debt in older sender/dispatcher/test-service/serializer/spec code remains; no blanket suppression or relaxation was added and this is not a green whole-file lint result. The new pin guard was extracted without changing its behavior, and the final 102 cases ran after that extraction.

## Production limits

These are source and isolated local-test results. Existing UNKNOWN deliveries remain untouched and must not be resumed or resent as validation. Final deployment, version/migration/health checks and a single explicitly authorized fresh text/image delivery remain separate release evidence.
