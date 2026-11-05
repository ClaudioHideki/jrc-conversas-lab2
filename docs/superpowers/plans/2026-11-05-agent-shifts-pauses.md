# Agent schedules and pause recovery implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Apply Thiago's eligibility flow including individual weekly shifts, manual pauses, capacity release and automatic queue recovery.

**Architecture:** Extend the existing per-inbox policy with optional `agent_schedules`, keyed by canonical user ID. Each schedule has seven weekday keys (0 Sunday through 6 Saturday), each containing up to four `{start: HH:MM, end: HH:MM}` periods. Periods may cross midnight; evaluate in the inbox timezone, including the previous day's overnight tail. Missing individual schedules retain inherited behavior for compatibility. Check both inbox and individual calendars again inside the assignment transaction. PostgreSQL remains the request ledger; the existing one-minute RecoveryJob handles calendar transitions without a new scheduler.

**Tech Stack:** Rails/PostgreSQL/Redis, Vue 3, RSpec, Vitest.

**Spec:** User-supplied Thiago flow, attachment a0138809-2f81-46f5-9188-9f38eec62c67/Texto colado.txt, and explicit clarification that each agent has their own shift. Existing distribution candidate 4724688e is preserved.

## Constraints and design decisions

- No production, credentials, engine, real messages, migration or backup/dump/restore changes.
- Reuse the current clean isolated worktree and branch. No merge or push.
- Pausing must never transfer an already assigned conversation.
- FIFO, proportional occupancy, tie round robin, RBAC and history admission boundaries remain intact.
- Individual schedules are configured per agent per inbox and use the inbox timezone. Holidays and separate account-wide workforce calendars are outside the defined weekly-shift requirement.
- Outside hours keeps central requests waiting. Automatic messages, Flow, bots or on-call routing are possible future configured actions, not unconditional new sends.
- Never silently turn a calendar-dependent rule into 24/7 when its calendar is disabled later.

## Tasks

- [x] Add RED tests for individual shifts, lunch, overnight/week boundaries, invalid/overlapping schedules and a calendar closure during assignment.
- [x] Implement the bounded schedule contract and clock evaluation; preserve omitted fields from older API clients.
- [x] Filter candidates and revalidate calendars before assigning; requeue immediately when automatic distribution is re-enabled for an online agent.
- [x] Prove existing return/capacity-release/periodic recovery behavior and FIFO using actual Rails, PostgreSQL and Redis.
- [x] Add an accessible per-agent weekly schedule editor to the existing distribution form; test save/reload, validation and removal/inheritance.
- [x] Run affected integration, concurrency, UI and lint/syntax checks; review the final diff.
- [x] Update checkpoint and deliver evidence, limitations and local commit. Full build/CI/deployment remain distinct gates.
## Execution ledger

- Base: 4724688e, clean reused isolated worktree. Source requirement SHA-256 6ab6ccd346b510826e846d37ace1ae73804029d08d39810086771b653d71cd4c.
- RED integration: 17 examples, 7 real failures. Focused GREEN: 30 examples, 0 failures. UI RED: 2 missing-editor failures; focused initial GREEN: 41/41.
- Review: stale member schedule and full-day edit order corrected after RED UI coverage. Current focused UI GREEN: 44/44. pt_BR catalog deferred per explicit AGENTS.md translation policy.
- Ruling: retain optional inherited schedules for existing policies; individual schedule must be explicitly configured per agent/inbox. This preserves working installations without inventing employee shifts.
- Ruling: reuse the existing one-minute RecoveryJob rather than add another scheduler; production worker readiness remains unverified.
- Ruling: out-of-hours automatic messages/Flow/on-call were described as future configurable actions. Keep requests queued and do not create real outbound side effects.
- Broad Rails regression passed 308/308 with PostgreSQL/Redis concurrency enabled. New validator was subsequently refactored for lint; fresh focused service regression is running.

- Final gates: broad Rails308/308, fresh focused Rails107/107 after validator refactor, final Vitest227/227. Prettier passes, ESLint0 errors/22 existing warnings, Ruby Lint9files/0offenses. Full Ruby metrics/style remains21 vs baseline25, no full frontend build or CI.
- Ruling on reviewer minor translation request: follow AGENTS.md (en source catalogs only); pt_BR must go through Crowdin. No bypass translation literals added to Vue.
- Ruling on reviewer scope exclusions: company-wide workforce planning and holiday exceptions are not this weekly per-inbox increment; preserve existing FIFO/locking design and do not claim physical/production verification.
- Last presentation changes: overnight day-off label clarified and next-day note uses a paragraph to avoid a new ESLint warning; focused component rerun recorded.

- Final maintenance case: removing a former member's saved shift now also explicitly removes their obsolete individual capacity/supervisor references. Two RED cases (empty inbox/current member present) passed after the fix. Fresh focused UI44/44; event naming and lint rechecked afterward.
- All code/test tasks of this increment are complete locally. Commit/report packaging only; build/CI/browser/production gates remain open.
