# Controlled publication, product 5640793988fbf63ac46b0db3466722fc650f0d01

Authorized scope: rebuild, real isolated smoke, publish exactly that image to ghcr.io/claudiohideki/jrc-conversas-lab2:sha-5640793988fbf63ac46b0db3466722fc650f0d01, then fresh-runner pull and full smoke. No latest, overwrite, product change, migration of production, merge or deploy.

Approved execution base: 06cadd75e9804f7aa38a8594146650d36d3ad837. Approved gate: 48b8a4f891f5cdd0ea3fcf4a3846c8b10c95015d. Native evidence: run 43344850748, 36 identities, 5554 executions. Prior image smoke: 43361093613. Product checkout is immutable, separate from CI infrastructure.

The original workflow is retained byte-for-byte in approved_execution_workflow.yml and on the immutable approved execution reference. The registered ag-native-candidate.yml path is used only on this separate infrastructure branch and is manually dispatched once on its exact infrastructure SHA. Admission binds only the new branch/workflow and three named jobs. Guard differences are only the branch authorization and attempt metadata (fifth build, previous successful build 43361093613). Original resource, identity, source, migration and smoke checks remain. Lock differs only in infrastructure_branch.

Minimum effective RAM 8 GiB, disk 3 GiB; reserves 750 MiB and 750000000 bytes. Original frontend-only 6144 MiB heap. Packages write is restricted to image-build; fresh verification gets packages read. Registry login credentials are never arguments or artifacts. Push is refused unless the SHA tag is absent, real build/smoke passed and image config/revision match. No automatic job reruns.

Post-push verifier recovers the build artifact by run identity and SHA-256, pulls the remote digest into a fresh Docker store, compares config ID to the actually tested image, validates tag/manifests and repeats all original schema/native/Scout/Sidekiq/PDF/XLSX/OCR/assets/HTTP smoke steps. AST denial tests enforce full smoke preservation. Verification does not build or push. Only synthetic isolated PostgreSQL/Redis/network and owned containers are used. No external providers are homologated.

On failure stop and preserve evidence. If publication succeeded but fresh verification fails, the image is not released for deploy and the existing tag is not overwritten automatically. Any correction is checkpointed on a separate infrastructure branch and affected gates are revalidated. After three corrections without progress for the same issue, stop. Registry/dependency/resource/billing blockers stop immediately.

Before any separately authorized deployment record the old Rails/Sidekiq immutable digests, Compose and environment securely. Application rollback uses both old digests and requires compatible schema; no automatic down migrations or data restore. This workflow never deploys.

Correction r2: GitHub creates downstream job records lazily. Build admission validates the two required logical jobs and permits only an unstarted optional verify-published row; final verification requires all three. Both phases reject duplicate/unknown jobs, incomplete API counts and wrong SHA/attempt. Five new denial/acceptance tests cover the observed API states. The failed pre-build run 43388956916 is preserved; no Docker build or push ran.
