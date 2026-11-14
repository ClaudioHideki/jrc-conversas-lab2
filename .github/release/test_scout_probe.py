"""Focused denial checks; no HTTP requests or application image build."""
import copy
import json
import os
from pathlib import Path
import unittest
import scout_probe

class ScoutProofTest(unittest.TestCase):
    def setUp(self):
        self.a = {"passed": True, "ruby": "3.4.12", "patchlevel": 148, "alpine": "3.24.4",
                  "platform": "x86_64-linux-musl", "scout": "5.7.0", "allocations_enabled": True,
                  "allocations_delta": 4008, "application_image_built": False}
        self.p = {"passed": True, "pid": 1, "examples": 15, "failures": 0, "pending": 0,
                  "cases": ["actual_container_pid_one"]}
        self.n = {"passed": True, "product_sha": scout_probe.PRODUCT, "scout_version": "5.7.0",
                  "allocation_monitoring": True, "postgres_redis_receipts_equal": True,
                  "actual_sidekiq_pid": 2, "verifier_pid": 3}
    @staticmethod
    def require(value, message):
        if not value:
            raise ValueError(message)
    def test_positive_exact_evidence(self):
        scout_probe.payloads(self.a, self.p, self.n, self.require)
    def test_denial_variants(self):
        variants = [
            ("a", "scout", "5.3.3"), ("a", "allocations_enabled", False),
            ("a", "allocations_delta", 0), ("a", "ruby", "3.4.4"),
            ("a", "application_image_built", True), ("p", "pid", 0),
            ("p", "failures", 1), ("p", "cases", []),
            ("n", "product_sha", "0"*40), ("n", "postgres_redis_receipts_equal", False),
            ("n", "actual_sidekiq_pid", 3), ("n", "actual_sidekiq_pid", "2"),
            ("n", "allocation_monitoring", False),
        ]
        for target, key, value in variants:
            with self.subTest(target=target, key=key):
                values = {k: copy.deepcopy(getattr(self, k)) for k in ("a", "p", "n")}
                values[target][key] = value
                with self.assertRaises(ValueError):
                    scout_probe.payloads(values["a"], values["p"], values["n"], self.require)

if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ScoutProofTest))
    report = {"tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors), "skipped": len(result.skipped)}
    Path(os.environ["SCOUT_PROOF_TEST_REPORT"]).write_text(json.dumps(report) + "\n")
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun == 2 and not result.skipped else 1)
