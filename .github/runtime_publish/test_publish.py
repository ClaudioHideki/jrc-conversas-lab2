"""Denial tests for publication, immutable identities and preserved smoke coverage."""
import ast
import copy
import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("publication", Path(__file__).with_name("publish.py"))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
ID = "sha256:" + "1"*64
DIGEST = "sha256:" + "2"*64

class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {"EXPECTED_EXECUTION_SHA": "a"*40})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.receipt = {"product_sha": p.PRODUCT, "execution_sha": "a"*40,
                        "build_passed": True, "smoke_passed": True,
                        "runtime_heap_environment_unchanged": True, "image_tag": p.LOCAL, "image_id": ID,
                        "frontend_heap": {"passed": True, "heap_mib": 6144},
                        "http": {"login_status": 200, "verified_assets": 3, "same_image_id": True,
                                 "host_ports_published": False}}
        self.manifest = {"digest": DIGEST, "body": {"schemaVersion": 2,
            "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
            "config": {"digest": ID}, "layers": [{"digest": "sha256:"+"3"*64}]}}
        self.info = {"Id": ID, "Os": "linux", "Architecture": "amd64",
                     "Config": {"Labels": {"org.opencontainers.image.revision": p.PRODUCT}}}

    def test_approved_build(self):
        self.assertEqual(p.validate_build(self.receipt), ID)

    def test_failed_or_missing_smoke_denied(self):
        for key in ["build_passed", "smoke_passed", "runtime_heap_environment_unchanged"]:
            with self.subTest(key=key):
                bad = copy.deepcopy(self.receipt);bad[key] = False
                with self.assertRaises(RuntimeError):p.validate_build(bad)

    def test_wrong_sha_denied(self):
        for key in ["product_sha", "execution_sha"]:
            bad = copy.deepcopy(self.receipt);bad[key] = "b"*40
            with self.assertRaises(RuntimeError):p.validate_build(bad)

    def test_failed_phase_or_owned_stop_denied(self):
        for key in ["failure", "owned_stop_errors"]:
            bad = copy.deepcopy(self.receipt);bad[key] = ["error"]
            with self.assertRaises(RuntimeError):p.validate_build(bad)

    def test_heap_receipt_required(self):
        bad = copy.deepcopy(self.receipt);bad["frontend_heap"]["heap_mib"] = 4096
        with self.assertRaises(RuntimeError):p.validate_build(bad)

    def test_http_assets_required(self):
        for key, value in [("verified_assets", 0), ("same_image_id", False), ("host_ports_published", True)]:
            bad = copy.deepcopy(self.receipt);bad["http"][key] = value
            with self.assertRaises(RuntimeError):p.validate_build(bad)

    def test_existing_tag_never_overwritten(self):
        p.assert_absent(None)
        with self.assertRaises(RuntimeError):p.assert_absent(self.manifest)

    def test_remote_manifest_config_matches_tested_image(self):
        self.assertEqual(p.validate_manifest(self.manifest, ID), DIGEST)

    def test_remote_different_image_denied(self):
        with self.assertRaises(RuntimeError):p.validate_manifest(self.manifest, "sha256:"+"4"*64)

    def test_remote_index_or_empty_layers_denied(self):
        for key, value in [("mediaType", "application/vnd.oci.image.index.v1+json"), ("layers", [])]:
            bad = copy.deepcopy(self.manifest);bad["body"][key] = value
            with self.assertRaises(RuntimeError):p.validate_manifest(bad, ID)

    def test_fresh_image_revision_and_platform(self):
        self.assertEqual(p.validate_image(self.info, ID)["Id"], ID)
        for key, value in [("Architecture", "arm64"), ("Os", "windows"), ("Id", "sha256:"+"4"*64)]:
            bad = copy.deepcopy(self.info);bad[key] = value
            with self.assertRaises(RuntimeError):p.validate_image(bad, ID)

    def test_fresh_image_wrong_source_denied(self):
        bad = copy.deepcopy(self.info);bad["Config"]["Labels"]["org.opencontainers.image.revision"] = "b"*40
        with self.assertRaises(RuntimeError):p.validate_image(bad, ID)

    def test_full_original_smoke_ast_preserved(self):
        old = ast.parse((ROOT/".github/runtime_build/guard.py").read_text())
        old_cls = next(n for n in old.body if isinstance(n, ast.ClassDef) and n.name == "Attempt")
        old_ex = next(n for n in old_cls.body if isinstance(n, ast.FunctionDef) and n.name == "execute")
        new = ast.parse(Path(__file__).with_name("publish.py").read_text())
        new_cls = next(n for n in new.body if isinstance(n, ast.ClassDef) and n.name == "PublishedAttempt")
        new_ex = next(n for n in new_cls.body if isinstance(n, ast.FunctionDef) and n.name == "execute")
        marker = 'self.command(["docker", "network", "create", "--internal"'
        def tail(nodes):
            start = next(i for i,n in enumerate(nodes) if ast.unparse(n).replace("'", '"').startswith(marker))
            return ast.dump(ast.Module(body=nodes[start:], type_ignores=[]), include_attributes=False)
        self.assertEqual(tail(old_ex.body), tail(new_ex.body))

    def test_verification_contains_no_build_or_push_command(self):
        new = ast.parse(Path(__file__).with_name("publish.py").read_text())
        cls = next(n for n in new.body if isinstance(n, ast.ClassDef) and n.name == "PublishedAttempt")
        text = ast.unparse(cls)
        self.assertNotIn('"buildx"', text.replace("'", '"'))
        self.assertNotIn('"push"', text.replace("'", '"'))
        self.assertIn("fresh-pull-by-digest", text)
        self.assertIn("already contains candidate image", text)

    def test_only_one_explicit_tag_push_no_latest(self):
        text = Path(__file__).with_name("publish.py").read_text()
        self.assertEqual(text.count('["docker", "push", TAG]'), 1)
        self.assertNotIn("--all-tags", text)
        self.assertNotIn('":latest"', text)
        self.assertIn('["docker", "tag", image_id, TAG]', text)

if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PublicationTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {"tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
              "skipped": len(result.skipped)}
    if os.environ.get("RUNNER_TEMP"):
        (Path(os.environ["RUNNER_TEMP"])/"publication-tests.json").write_text(json.dumps(report, indent=2)+"\n")
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun == 15 and not result.skipped else 1)
