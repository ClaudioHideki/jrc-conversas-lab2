# Native URA standard image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the current Grupo JRC/LAB2 standard with generic native URA support, install it in authorized HML, keep the production Broker compatible, and deliver a complete tenant setup report. Do not modify GoPure or other customer repositories/images.

**Architecture:** Preserve LAB2 `e7dba8149be63708dc1b9e38ab9479ec7cca2ffe` and port only the native changes validated in `f6a83b3ebc68a4f74ebbff11d9046037db2a267b`. Broker `2d30a5a544aa0eae12c208867e4912c369626787` remains the executor. Availability defaults do not create operational bindings or credentials.

**Tech Stack:** Rails/Ruby 3.4.4, Vue/Vite, Node 24.13.0, PostgreSQL/pgvector, Redis, Docker, GitHub Actions/GHCR.

**Spec:** `docs/superpowers/specs/2026-11-04-native-ura-standard-image.md`

## Global Constraints

- Preserve current LAB2 connections, availability, NICO, Cockpit, CRM and customer branding behavior.
- No operational Typebot, Bot Bridge or Budibase dependency.
- No customer payload, credential or HML resource ID in generic runtime code/images.
- Configure and deploy only the authorized LAB; keep tenant/account/inbox scopes and native registration checks.
- Keep current HML database, Redis and encryption keys. No credential regeneration.
- Treat CI, image publication, runtime health and physical WhatsApp evidence separately.

## Review Focus

- Inactive AgentBot links must still prevent a null native responder pair.
- A senderless CSAT template may travel without taking human control or being delivered twice.
- Newly available modules must not create bindings or grant another account access.
- Explicitly disabled existing account features and deployment flags must stay disabled.
- The standard branding mechanism and the newer availability rules must remain intact.

### Task 1: Port native correctness changes with regression evidence

**Files:**
- Modify: `app/models/jrc_broker_webhook_obligation.rb`
- Modify: `app/services/jrc_broker/webhook_delivery.rb`
- Modify: `app/services/jrc_flows/native_responders.rb`
- Modify: `app/services/message_templates/template/csat_survey.rb`
- Modify: `config/application.rb`
- Test: `spec/models/jrc_broker_webhook_obligation_spec.rb`
- Test: `spec/services/jrc_broker/webhook_delivery_spec.rb`
- Test: `spec/services/jrc_flows/native_responders_spec.rb`
- Test: `spec/services/message_templates/template/csat_survey_spec.rb`
- Test: `spec/config/application_time_zone_spec.rb`

**Interfaces:** Preserve existing public method signatures, native domain command contracts and CSAT event shape. Add only `deliverable_message?(message)` and the private lookup used by WebhookDelivery as already validated in R2.

- [x] Copy the targeted regression cases from the validated R2 tree, run them against unchanged LAB2 and record expected failures. 61 examples, 13 expected failures, no pending.
- [x] Apply only the corresponding runtime deltas. Preserve all unrelated LAB2 code.
- [x] Run targeted specs including CSAT concurrency and current native ownership/callback tests; require zero failures. 61 examples, zero failures and pending.
- [ ] Run the newer LAB2 availability and connection request regressions.
- [ ] Review `git diff --check` and commit the bounded port.

### Task 2: Ship generic availability and verifiable module artifacts

**Files:**
- Modify: `docker/Dockerfile`, `config/features.yml`
- Create: `spec/models/jrc_native_module_defaults_spec.rb`
- Modify: `app/javascript/dashboard/routes/dashboard/jrcFlows/nativeEditorBuild.js`
- Modify: `public/jrc-flow-editor/EDITOR-BUILD-MANIFEST.json`, `public/jrc-flow-editor/editor.js`
- Regenerate: `config/jrc_flow_ownership_guards.json`, `deploy/jrc/MODULE-COMPOSITION-MANIFEST.json`
- Update: `deploy/jrc/module-composition-input.json`
- Create: `deploy/jrc/native-ura.env.example`; use the existing module composition manifest for capability provenance rather than duplicating that inventory.
- Create: `.github/workflows/native-ura-candidate.yml`
- Test: existing `deploy/jrc/module-manifest.test.mjs`, `script/lab2_release_gates.test.mjs` and native configuration/policy specs.

**Interfaces:** New accounts can see Broker/Flows capabilities; their integration and binding tables remain empty. Per-deployment false flags and explicit account opt-outs remain authoritative. The public Broker origin is a deployment setting; no credentials are image defaults. The common editor remains pinned to Broker source `2d30a5a544aa0eae12c208867e4912c369626787`.

- [ ] Add a failing model example: a newly created account has Broker/Flows available with no integrations, native registrations or bindings.
- [ ] Add a regression example: an explicit account opt-out persists across reload/save; retain existing account isolation and credential-negative cases.
- [ ] Enable new-account capability defaults and supply image/deployment availability defaults, preserving explicit overrides and required encryption/origin setup.
- [ ] Port the frozen editor and regenerate manifests from this actual LAB2 source.
- [ ] Add a generic candidate workflow with native backend/UI/MinIO gates and a final production-image smoke. Use repository-derived immutable GHCR tags; preserve existing workflows.
- [ ] Run manifest/node checks, targeted Rails tests and UI/availability regressions. Commit only after checks pass.

### Task 3: Publish standard candidate and install in authorized LAB

**Files:**
- Create: `docs/operations/native-ura-setup.md`
- Update: source release receipt and external HML delivery artifacts.

**Interfaces:** Guide separates image/install defaults, per-account control credentials, optional delegated editor credential/registration, and per-inbox flow/agent configuration. Published image ref includes registry digest and source revision.

- [ ] Push the isolated candidate branch and run all candidate gates before publishing.
- [ ] Verify GHCR provenance/source, platform and digest. Keep prior HML image ref recorded.
- [ ] Replace only the authorized LAB application image; preserve DB, Redis, keys and bindings. Run required database preparation and verify Rails/Sidekiq/source SHA.
- [ ] Verify Grupo JRC/LAB branding and current connections screens, then repeat the OIA sample checks supported by the authorized contact.
- [ ] Complete or precisely identify remaining scoped native-editor registration inputs. Never reuse the QR/control key as Flow authority.
- [ ] Document the exact UI/operator procedure, real findings and remaining physical checks.

### Task 4: Deliver the standard-image and production-Broker report

**Files:** Standard capability manifest, deployment receipts and a complete user-facing report with setup instructions and screenshot evidence.

**Interfaces:** Future customers derive from the Grupo JRC standard, with their own branding/configuration. This delivery changes only LAB/Grupo JRC source and the authorized production Broker; other customer images remain unchanged.

- [ ] Record the production Broker API/WEB images, migration, native Flow behavior and remaining setup inputs.
- [ ] Explain image-wide capabilities versus installation/account/inbox credentials, membership, hours, CSAT and bot ownership.
- [ ] Publish only the Grupo JRC standard/LAB candidate; preserve GoPure and all other customer sources/images.
- [ ] Deliver the complete report, image refs, source/CI/runtime receipts and proof matrix. Mark unfinished setup and untested physical routes explicitly.
