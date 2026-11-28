# Configurable exceeded-pause warning

Status: user-approved business decision; implementation prepared, native acceptance pending.

The Word specifications describe an exceeded-pause warning and per-reason alert configuration. The user approved configuring that warning per reason and clarified: “Somente os avisos de pausa”. This decision does not change ACW warnings.

Use the existing pause catalog and its native revision and event snapshots. An explicitly stored `time_alert_enabled: false` hides only the exceeded-pause warning in the existing agent and supervisor views. A missing field retains the enabled legacy warning and is not inserted just by opening or saving an unchanged reason. Elapsed time, factual exceeded status and configured limits remain observable.

The original local event snapshot determines the warning for a pause already in progress. Editing the catalog affects subsequent pauses. It does not rewrite old events, end a pause, authorize return to distribution, change approval/justification rules, grant rights or publish a PABX configuration.

No migration, separate registry or new permission is introduced. Native account, corporate/unit and profile authorization remain in the existing catalog and operational services. Four existing real-browser cases will be extended without replacing their earlier assertions; Rails and Vue tests must prove both explicit choices and legacy absence before acceptance.
