# Explicit campaign window timezone

Base: 6d0adde51ff8ed125a901c3058625b90bfbb097e. Authorized bounded backend/UI fix, with synthetic focal and adjacent regressions only. No production action, existing-job mutation, commit, push or image build here. Preserve the media fix and two pre-existing snapshot edits.

The window currently calls `in_time_zone` and `Time.zone.parse` without a zone. A Monday 13:40–14:00 window created at 16:49 UTC (13:49 Sao Paulo) is consequently deferred one week instead of running inside the operator's intended window.

Approved design:

- Store an explicit IANA timezone in `sending_window`, already covered by the approved configuration digest. Validate it in the model and interpret calendar weekday, start and end in that zone, including DST transitions.
- New UI drafts automatically use account timezone or browser timezone. New API drafts without a timezone capture account timezone or UTC at creation. Existing saved configurations with no timezone retain UTC semantics; do not silently alter active approvals or scheduled jobs.
- Expose tenant-scoped account timezone as metadata. Display timezone and estimated next start in the wizard/review, with no extra menu or approval gate. Keep scheduling input instants consistent with the displayed zone.
- Test local-time windows, next permitted day, DST, invalid timezone, account default, explicit precedence, legacy UTC, reviewed timezone changes and UI payload/display. Keep approval and multitenant controls unchanged.

Operational recovery of the four existing jobs belongs to the root agent and is excluded from this source change.

## Completed implementation and evidence

- Legacy approved/running windows still resolve to UTC. Editing a legacy draft with no explicit timezone and no approval adopts account/browser timezone in form state, without mutating the input object; explicit UTC is retained. The persisted change is covered by the existing review digest.
- Account metadata is IANA only when reporting_timezone is actually configured; nil/false becomes JSON null, allowing browser fallback. The API model default remains account/UTC for newly created drafts.
- Scheduled datetime-local values round trip through the displayed timezone, preserving the original instant when the wall time and zone have not changed, including both offsets of an ambiguous DST hour. Late account metadata replaces only an automatic new/unapproved-draft default; explicit and approved legacy configurations are retained. Approved legacy payloads keep an originally absent timezone absent.
- The wizard displays an estimate; review uses the backend estimate. Manual triggers ignore stale scheduled_at values. Running serializer output reads queued recipient timestamps and never moves jobs or makes HTTP calls.
- Backend RED: 9 examples/8 failures, expanded 13/11. Blank account false regression: 3/1 before the presence normalization. Final focused/adjacent backend run: 112 examples/0 failures, exit 0.
- Review backend regression: 2 examples/1 failure exposed manual-trigger stale scheduled_at affecting ETA; false model settings already fell back safely, and presence normalization was added for consistency. Final backend delta: 16 examples/0 failures after both review adjustments; the preceding adjacent run was 112/0.
- UI RED: 5 failures. Initial green attempt exposed two test panel-selection errors; those were corrected. Cleared-time regression: 9 tests/1 failure, then guarded preview of incomplete input. Legacy-draft regression: 12/1, then corrected initialization. Review preservation regression: 14/2; late-metadata regression: 17/3, retaining those two failures until the bounded fixes. Final five-file UI run: 51 tests passed, one worker.
- ESLint: 0 errors; 122 inherited warnings (121 Wizard, 1 Approval) match baseline. Ruby focused lint has 26 inherited offense categories; ScheduleWindow and both new Ruby specs are clean. Existing Campaign class length increases from 190 to 204, and Metadata.show ABC from 32.2 to 38.33; no claim of globally clean Ruby lint.
- No Enterprise override of this campaign implementation was found. ApprovalService/ReviewConfiguration remain unchanged, as do pending jobs, migrations, existing-media fix and snapshots. No generic full suite/build/deploy or real message was run in this subtask.
- Final provenance is recorded in `.sessions/campaign-timezone-manifest-20261026.json` with source hashes and local test/lint logs. Production recovery and validation belong to the root agent's separate evidence.
