"""Positive and denial tests for the isolated release evidence gate."""
import copy
import io
import json
from pathlib import Path
import unittest
import zipfile
import gate


LOCK = json.loads(Path(__file__).with_name("release-evidence-lock.json").read_text())


class EvidenceGateTest(unittest.TestCase):
    def setUp(self):
        self.lock = copy.deepcopy(LOCK)
        self.run = {"id": self.lock["native_run_id"], "head_sha": self.lock["product_sha"],
                    "head_branch": self.lock["product_branch"], "path": self.lock["native_workflow"],
                    "run_attempt": 1, "status": "completed", "conclusion": "success",
                    "head_repository": {"full_name": self.lock["repository"]}}
        self.jobs = {"total_count": len(self.lock["mandatory_jobs"]) + 1, "jobs": []}
        for e in self.lock["mandatory_jobs"] + [self.lock["approved_skipped_job"]]:
            skipped = e["name"] == "guarded-candidate-build"
            self.jobs["jobs"].append({**e, "head_sha": self.lock["product_sha"], "run_id": self.lock["native_run_id"],
                "run_attempt": 1, "status": "completed", "conclusion": "skipped" if skipped else "success",
                "runner_id": None if skipped else 1, "started_at": "2026-11-12T15:45:00Z",
                "completed_at": "2026-11-12T16:45:00Z", "steps": [] if skipped else [{"conclusion": "success"}]})
        self.report = {"summary": {"example_count": 1, "failure_count": 0,
            "pending_count": 0, "errors_outside_of_examples_count": 0}, "examples": [{"status": "passed"}]}
        self.artifacts = {"total_count": len(self.lock["artifacts"]), "artifacts": [{**e, "digest": "sha256:" + e["sha256"], "expired": False,
            "workflow_run": {"id": self.lock["native_run_id"], "head_sha": self.lock["product_sha"]}}
            for e in self.lock["artifacts"]]}

    def test_positive_exact_run_and_all_jobs(self):
        gate.run_identity(self.lock, self.run)
        self.assertEqual(len(gate.jobs_identity(self.lock, self.jobs)), 36)

    def test_job_order_is_not_identity(self):
        self.jobs["jobs"].reverse()
        self.assertEqual(len(gate.jobs_identity(self.lock, self.jobs)), 36)

    def test_wrong_sha_branch_run_workflow_or_attempt_rejected(self):
        for key, value in [("head_sha", "0"*40), ("head_branch", "main"), ("id", 1),
                           ("path", ".github/workflows/other.yml"), ("run_attempt", 2)]:
            with self.subTest(key=key):
                r = copy.deepcopy(self.run);r[key] = value
                with self.assertRaises(gate.GateError):
                    gate.run_identity(self.lock, r)

    def test_failed_cancelled_queued_aggregate_rejected(self):
        for status, conclusion in [("completed", "cancelled"), ("completed", "failure"), ("queued", None)]:
            with self.subTest(status=status, conclusion=conclusion):
                r = copy.deepcopy(self.run);r.update(status=status, conclusion=conclusion)
                with self.assertRaises(gate.GateError):
                    gate.run_identity(self.lock, r)

    def test_fork_source_rejected(self):
        self.run["head_repository"]["full_name"] = "other/repository"
        with self.assertRaises(gate.GateError):
            gate.run_identity(self.lock, self.run)

    def test_incomplete_matrix_not_deduplicated_or_approved(self):
        self.jobs["jobs"].pop()
        with self.assertRaises(gate.GateError):
            gate.jobs_identity(self.lock, self.jobs)

    def test_duplicate_job_ids_rejected(self):
        self.jobs["jobs"][1] = copy.deepcopy(self.jobs["jobs"][0])
        with self.assertRaises(gate.GateError):
            gate.jobs_identity(self.lock, self.jobs)

    def test_new_job_id_with_old_name_rejected(self):
        self.jobs["jobs"][0]["id"] = 5
        with self.assertRaises(gate.GateError):
            gate.jobs_identity(self.lock, self.jobs)

    def test_failed_mandatory_job_rejected(self):
        self.jobs["jobs"][0]["conclusion"] = "failure"
        with self.assertRaises(gate.GateError):
            gate.jobs_identity(self.lock, self.jobs)

    def test_inherited_attempt_rejected(self):
        self.jobs["jobs"][0]["run_attempt"] = 2
        with self.assertRaises(gate.GateError):
            gate.jobs_identity(self.lock, self.jobs)

    def test_runnerless_mandatory_job_rejected(self):
        self.jobs["jobs"][0]["runner_id"] = None
        with self.assertRaises(gate.GateError):
            gate.jobs_identity(self.lock, self.jobs)

    def test_build_execution_rejected(self):
        self.jobs["jobs"][-1].update(conclusion="success", runner_id=1, steps=[{"conclusion": "success"}])
        with self.assertRaises(gate.GateError):
            gate.jobs_identity(self.lock, self.jobs)

    def test_positive_rspec(self):
        self.assertEqual(gate.rspec(self.report, 1), 1)

    def test_zero_failure_pending_outside_and_boolean_counts_rejected(self):
        for key, value in [("example_count", 0), ("failure_count", 1), ("pending_count", 1),
                           ("errors_outside_of_examples_count", 1), ("example_count", True)]:
            with self.subTest(key=key):
                r = copy.deepcopy(self.report);r["summary"][key] = value
                with self.assertRaises(gate.GateError):
                    gate.rspec(r)

    def test_missing_outside_count_rejected(self):
        del self.report["summary"]["errors_outside_of_examples_count"]
        with self.assertRaises(KeyError):
            gate.rspec(self.report)

    def test_reduced_rspec_coverage_rejected(self):
        with self.assertRaises(gate.GateError):
            gate.rspec(self.report, 2)

    def test_unpassed_example_rejected(self):
        self.report["examples"][0]["status"] = "pending"
        with self.assertRaises(gate.GateError):
            gate.rspec(self.report)

    def test_missing_examples_rejected(self):
        self.report["examples"] = []
        with self.assertRaises(gate.GateError):
            gate.rspec(self.report)

    def test_positive_vue_and_todo_denial(self):
        r = {"success": True, "numTotalTests": 1, "numPassedTests": 1, "numFailedTests": 0,
             "numPendingTests": 0, "numTodoTests": 0,
             "testResults": [{"assertionResults": [{"status": "passed"}]}]}
        self.assertEqual(gate.vue(r), 1)
        r["numTodoTests"] = 1
        with self.assertRaises(gate.GateError):
            gate.vue(r)

    def test_actual_whatsapp_report_names_use_strict_validators(self):
        self.assertEqual(gate.report_kind("whatsapp-native.json"), "rspec")
        self.assertEqual(gate.report_kind("whatsapp-ui-results.json"), "vue")
        self.assertEqual(gate.report_kind("tmp/ag-rspec.json"), "rspec")
        self.assertEqual(gate.report_kind("tmp/voice-v4-vitest.json"), "vue")
        for name in ("projects-portal-concurrency.json", "projects-portal-sd-concurrency.json",
                     "projects-portal-comments-concurrency.json"):
            self.assertEqual(gate.report_kind("tmp/" + name), "rspec")
        self.assertIsNone(gate.report_kind("unknown.json"))
        bad = copy.deepcopy(self.report)
        bad["summary"]["errors_outside_of_examples_count"] = 1
        with self.assertRaises(gate.GateError):
            gate.rspec(bad)

    def test_migration_catalog_ledger_and_isolation_denials(self):
        versions = [str(i) for i in range(34)] + ["20261111150000", "20261112000000"]
        report = {"source_sha": self.lock["product_sha"], "production_changed": False,
                  "docker_build_executed": False, "catalog_equivalence_passed": True,
                  "schema_paths_passed": ["fresh_migrate_and_reexecute",
                      "populated_main_upgrade_and_reexecute", "empty_schema_reload"],
                  "upgrade": {"required_versions": versions, "historical_versions": versions[:27],
                      "preserved_subjects": 11, "existing_versions_preserved": True,
                      "populated_upgrade": True, "missing_after": [], "pending_after": False},
                  "sha256": {"/tmp/schema.rb": gate.sha(b"synthetic")}}
        for mutation in ("none", "catalog", "pending", "isolation", "missing_migration", "schema_hash"):
            with self.subTest(mutation=mutation):
                r = copy.deepcopy(report)
                if mutation == "catalog":
                    r["catalog_equivalence_passed"] = False
                elif mutation == "pending":
                    r["upgrade"]["pending_after"] = True
                elif mutation == "isolation":
                    r["production_changed"] = True
                elif mutation == "missing_migration":
                    r["upgrade"]["required_versions"][-1] = "unreviewed"
                elif mutation == "schema_hash":
                    r["sha256"]["/tmp/schema.rb"] = "0"*64
                b = io.BytesIO()
                with zipfile.ZipFile(b, "w") as z:
                    z.writestr("ag-migration-audit-result.json", json.dumps(r))
                    z.writestr("schema.rb", b"synthetic")
                z = gate.archive(b.getvalue(), gate.sha(b.getvalue()))
                if mutation == "none":
                    gate.migration(z, self.lock["product_sha"])
                else:
                    with self.assertRaises(gate.GateError):
                        gate.migration(z, self.lock["product_sha"])

    def test_runtime_host_source_versions_and_no_image_claim(self):
        report = {"source_sha": self.lock["product_sha"], "ruby": "3.4.12", "ruby_patchlevel": 148,
                  "node": "v24.22.3", "runner_os": "Ubuntu 24.04", "platform": "x86_64-linux",
                  "alpine_image_tested": False}
        gate.runtime_host(report, self.lock["product_sha"])
        for key, value in [("source_sha", "0"*40), ("ruby", "3.4.4"), ("node", "v24.13.0"),
                           ("alpine_image_tested", True)]:
            with self.subTest(key=key):
                r = copy.deepcopy(report);r[key] = value
                with self.assertRaises(gate.GateError):
                    gate.runtime_host(r, self.lock["product_sha"])

    def test_unfinished_native_evidence_cannot_authorize_release(self):
        draft = {**self.lock, "evidence_state": "awaiting-native-run"}
        with self.assertRaises(gate.GateError):
            gate.execute(draft, "a" * 40, Path("."), Path("must-not-be-written.json"))

    def test_runtime_contract_preserves_dependencies_and_blocks_image_claim(self):
        report = {"passed": True, "base_sha": "cad427d400d824fc1fdc06c1c1079f324e7f3f6c",
                  "ruby": "3.4.12", "patchlevel": 148, "node": "24.22.3", "alpine": "3.24",
                  "gem_versions_unchanged": False, "all_other_gem_versions_unchanged": True,
                  "reviewed_gem_changes": [{"gem": "scout_apm", "from": "5.3.3", "to": "5.7.0",
                      "upstream_fix": "https://github.com/scoutapp/scout_apm_ruby/pull/552"}],
                  "pnpm_lock_unchanged": True,
                  "functional_sources_unchanged": False, "all_other_functional_sources_unchanged": True,
                  "migrations_unchanged": True, "separate_nico_image_unchanged": True,
                  "reviewed_functional_fixes": [{
                      "path": "app/models/jrc_crm/backoffice_request.rb",
                      "sha256": "599bc1fce954fe4bcc58aa98117722628001939b24f77522f178bd0bb90331bd",
                      "regression": "spec/services/jrc_crm/backoffice_request_number_spec.rb",
                      "regression_sha256": "f424461b1008fc5942e421e430a283485e7dd54b8d4551a339ece28abaaa2172"
                  }], "frontend_vite_heap_mib": 6144, "frontend_effective_memory_min_gib": 8,
                  "runtime_image_stage_unchanged_from_d11c879a": True, "docker_build_executed": False}
        gate.runtime_contract(report)
        for key, value in [("docker_build_executed", True), ("gem_versions_unchanged", True),
                           ("all_other_gem_versions_unchanged", False), ("reviewed_gem_changes", []),
                           ("reviewed_gem_changes", [{"gem": "scout_apm", "from": "5.3.3", "to": "5.3.3"}]),
                           ("all_other_functional_sources_unchanged", False), ("ruby", "3.4.4"),
                           ("reviewed_functional_fixes", []), ("functional_sources_unchanged", True),
                           ("frontend_vite_heap_mib", 4096), ("frontend_effective_memory_min_gib", 5),
                           ("runtime_image_stage_unchanged_from_d11c879a", False)]:
            with self.subTest(key=key):
                r = copy.deepcopy(report);r[key] = value
                with self.assertRaises(gate.GateError):
                    gate.runtime_contract(r)

    def test_artifact_identity_positive(self):
        self.assertEqual(len(gate.artifact_identity(self.lock, self.artifacts)), len(self.lock["artifacts"]))

    def test_artifact_expiry_or_wrong_sha_rejected(self):
        for key, value in [("expired", True), ("digest", "sha256:" + "0"*64)]:
            with self.subTest(key=key):
                r = copy.deepcopy(self.artifacts);r["artifacts"][0][key] = value
                with self.assertRaises(gate.GateError):
                    gate.artifact_identity(self.lock, r)

    def test_missing_artifact_rejected(self):
        self.artifacts["artifacts"].pop()
        with self.assertRaises(gate.GateError):
            gate.artifact_identity(self.lock, self.artifacts)

    def test_artifact_from_other_sha_rejected(self):
        self.artifacts["artifacts"][0]["workflow_run"]["head_sha"] = "0"*40
        with self.assertRaises(gate.GateError):
            gate.artifact_identity(self.lock, self.artifacts)

    def test_valid_archive_and_digest_tamper(self):
        b = io.BytesIO()
        with zipfile.ZipFile(b, "w") as z:
            z.writestr("result.json", "{}")
        data = b.getvalue()
        self.assertEqual(gate.member(gate.archive(data, gate.sha(data)), "result.json"), b"{}")
        with self.assertRaises(gate.GateError):
            gate.archive(data + b"x", gate.sha(data))

    def test_unsafe_archive_path_rejected(self):
        b = io.BytesIO()
        with zipfile.ZipFile(b, "w") as z:
            z.writestr("../result.json", "{}")
        data = b.getvalue()
        with self.assertRaises(gate.GateError):
            gate.archive(data, gate.sha(data))

    def test_duplicate_report_suffix_rejected(self):
        b = io.BytesIO()
        with zipfile.ZipFile(b, "w") as z:
            z.writestr("a/result.json", "{}");z.writestr("b/result.json", "{}")
        data = b.getvalue()
        with self.assertRaises(gate.GateError):
            gate.member(gate.archive(data, gate.sha(data)), "result.json")

    def test_signed_https_four_suite_proof_required(self):
        mirror = "https://mirrors.edge.kernel.org/ubuntu"
        lines = ["CI Ubuntu mirror selected: " + mirror + " (APT signature verification follows)"]
        lines += ["CI Ubuntu connectivity OK: " + mirror + "/dists/" + s + "/InRelease HTTP=200"
                  for s in ("noble", "noble-updates", "noble-backports", "noble-security")]
        lines += ["CI Ubuntu APT metadata update passed with signature checks enabled: " + mirror]
        log = "\n".join(lines)
        self.assertEqual(gate.apt(log), mirror)
        with self.assertRaises(gate.GateError):
            gate.apt(log.replace("noble-security", "unreviewed"))
        with self.assertRaises(gate.GateError):
            gate.apt(log.replace("signature checks enabled", "signature checks disabled"))
        with self.assertRaises(gate.GateError):
            gate.apt(log.replace("https://", "http://"))


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(EvidenceGateTest)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = {"tests": result.testsRun, "failures": len(result.failures),
               "errors": len(result.errors), "skipped": len(result.skipped)}
    target = Path(__import__("os").environ["GATE_TEST_REPORT"])
    target.write_text(json.dumps(summary) + "\n")
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun == 32 and not result.skipped else 1)
