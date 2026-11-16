import copy
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import guard


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.env = {"GITHUB_ACTIONS":"true","RUNNER_ENVIRONMENT":"github-hosted",
                    "GITHUB_REPOSITORY":guard.REPO,"GITHUB_REF_NAME":guard.BRANCH,
                    "GITHUB_EVENT_NAME":"workflow_dispatch","GITHUB_RUN_ATTEMPT":"1","GITHUB_RUN_ID":"123",
                    "GITHUB_SHA":"a"*40,"EXPECTED_EXECUTION_SHA":"a"*40,"EXPECTED_PRODUCT_SHA":guard.PRODUCT,
                    "AUTHORIZED_BUILD_SHA":guard.PRODUCT,"EXPECTED_APPROVED_SHA":guard.APPROVED}

    def test_exact_authorized_identity(self):
        with patch("guard.sys.platform","linux"):
            self.assertEqual(guard.identity(self.env),"jrc-runtime-123-1")

    def test_denies_wrong_product(self):
        for key in ["EXPECTED_PRODUCT_SHA","AUTHORIZED_BUILD_SHA"]:
            with self.subTest(key=key), patch("guard.sys.platform","linux"):
                env = {**self.env,key:"b"*40}
                with self.assertRaises(RuntimeError):
                    guard.identity(env)

    def test_denies_wrong_infrastructure(self):
        for key in ["GITHUB_SHA","EXPECTED_EXECUTION_SHA","EXPECTED_APPROVED_SHA"]:
            with self.subTest(key=key), patch("guard.sys.platform","linux"):
                env = {**self.env,key:"b"*40}
                with self.assertRaises(RuntimeError):
                    guard.identity(env)

    def test_denies_other_environment(self):
        for key, value in [("GITHUB_REPOSITORY","other/repo"),("GITHUB_REF_NAME","main"),
                           ("GITHUB_RUN_ATTEMPT","2"),("GITHUB_EVENT_NAME","push"),("RUNNER_ENVIRONMENT","self-hosted"),
                           ("GITHUB_ACTIONS","false"),("GITHUB_RUN_ID","")]:
            with self.subTest(key=key), patch("guard.sys.platform","linux"):
                with self.assertRaises(RuntimeError):
                    guard.identity({**self.env,key:value})

    def test_denies_windows(self):
        with patch("guard.sys.platform","win32"), self.assertRaises(RuntimeError):
            guard.identity(self.env)

    def test_preserved_resource_thresholds(self):
        limits = guard.limits()
        self.assertIsNone(limits.resource_reason(3*1024**3,5*1024**3,starting=True))
        self.assertIsNotNone(limits.resource_reason(3*1024**3-1,5*1024**3,starting=True))
        self.assertIsNotNone(limits.resource_reason(3*1024**3,5*1024**3-1,starting=True))
        self.assertIsNotNone(limits.resource_reason(750_000_000,5*1024**3))
        self.assertIsNotNone(limits.resource_reason(3*1024**3,750*1024**2))
        self.assertIsNone(limits.resource_reason(750_000_001,750*1024**2+1))

    def test_image_schema_is_brought_to_current_migrations(self):
        self.assertEqual(guard.schema_command(), ["bundle", "exec", "ruby", "/smoke/migrate_without_export.rb"])

    def test_local_amd64_build_only(self):
        cmd = guard.build_command("owned-builder", Path("/tmp/output"))
        self.assertEqual(cmd[:3],["docker","buildx","build"])
        self.assertIn("--load",cmd)
        self.assertEqual(cmd[cmd.index("--platform")+1],"linux/amd64")
        self.assertNotIn("--push",cmd)
        self.assertNotIn("--cache-to",cmd)
        self.assertNotIn("ghcr.io"," ".join(cmd))
        self.assertEqual(cmd[cmd.index("--build-arg")+1],"GIT_SHA="+guard.PRODUCT)

    def test_foreign_container_not_owned(self):
        attempt = object.__new__(guard.Attempt)
        attempt.name = "owned"; attempt.containers = {}
        with patch.object(attempt,"inspect",return_value={"Config":{"Labels":{"jrc.runtime.run":"other"}}}):
            with self.assertRaises(RuntimeError):
                attempt.own("foreign")
        self.assertEqual(attempt.containers,{})

    def test_resource_failure_stops_owned_process(self):
        import tempfile
        attempt = object.__new__(guard.Attempt)
        attempt.output = Path(tempfile.mkdtemp())
        attempt.start = 0
        attempt.result = {"phases":[]}
        fake = unittest.mock.Mock()
        fake.pid = 999
        fake.poll.return_value = None
        with patch.object(attempt,"sample",side_effect=[{},RuntimeError("ram reserve")]), \
             patch("guard.subprocess.Popen",return_value=fake), patch("guard.os.getpgid",return_value=999), \
             patch("guard.os.killpg") as kill, patch("guard.time.monotonic",return_value=1), \
             patch("guard.check_preserved_refs") as check_refs:
            with self.assertRaises(RuntimeError):
                attempt.command(["owned"],"resource-test")
            kill.assert_called_once_with(999,guard.signal.SIGTERM)
            fake.wait.assert_called_once_with(timeout=10)
            check_refs.assert_called_once_with()

    def test_foreign_process_group_never_killed(self):
        import tempfile
        attempt = object.__new__(guard.Attempt)
        attempt.output = Path(tempfile.mkdtemp())
        attempt.start = 0
        attempt.result = {"phases":[]}
        fake = unittest.mock.Mock()
        fake.pid = 999; fake.poll.return_value = None
        with patch.object(attempt,"sample",side_effect=[{},RuntimeError("disk reserve")]), \
             patch("guard.subprocess.Popen",return_value=fake), patch("guard.os.getpgid",return_value=123), \
             patch("guard.os.killpg") as kill, patch("guard.time.monotonic",return_value=1), \
             patch("guard.check_preserved_refs") as check_refs:
            with self.assertRaises(RuntimeError):
                attempt.command(["owned"],"foreign-test")
            kill.assert_not_called()
            check_refs.assert_called_once_with()

    def reference_responder(self, changed=None):
        import io
        expected={"main":guard.BASE_MAIN,
                  "codex/quick-release-image-5c3fb7f7-20261115":guard.PRODUCT,
                  "codex/respostas-rapidas-aprovacoes-20261115":"2be22e86baecbe75c302bb03208e78e67301c743"}
        seen=[]
        def response(request,timeout):
            prefix="https://api.github.com/repos/"+guard.REPO+"/git/ref/heads/"
            self.assertTrue(request.full_url.startswith(prefix))
            branch=request.full_url.removeprefix(prefix)
            self.assertIn(branch,expected)
            self.assertEqual(request.get_header("Authorization"),"Bearer synthetic-unit-token")
            self.assertEqual(timeout,30)
            seen.append(branch)
            value="0"*40 if branch==changed else expected[branch]
            return io.BytesIO(json.dumps({"object":{"sha":value}}).encode())
        return response,seen

    def test_reference_checks_bind_all_three_authenticated_refs(self):
        response,seen=self.reference_responder()
        with patch("guard.REF_TOKEN","synthetic-unit-token"), patch("guard.urllib.request.urlopen",side_effect=response):
            guard.check_preserved_refs()
        self.assertEqual(len(seen),3)
        self.assertEqual(len(set(seen)),3)

    def test_changed_live_main_is_rejected(self):
        response,_=self.reference_responder("main")
        with patch("guard.REF_TOKEN","synthetic-unit-token"), patch("guard.urllib.request.urlopen",side_effect=response):
            with self.assertRaisesRegex(RuntimeError,"Protected reference advanced: main"):
                guard.check_preserved_refs()

    def test_changed_product_alias_is_rejected(self):
        response,_=self.reference_responder("codex/quick-release-image-5c3fb7f7-20261115")
        with patch("guard.REF_TOKEN","synthetic-unit-token"), patch("guard.urllib.request.urlopen",side_effect=response):
            with self.assertRaisesRegex(RuntimeError,"Protected reference advanced"):
                guard.check_preserved_refs()

    def test_changed_original_checkpoint_alias_is_rejected(self):
        response,_=self.reference_responder("codex/respostas-rapidas-aprovacoes-20261115")
        with patch("guard.REF_TOKEN","synthetic-unit-token"), patch("guard.urllib.request.urlopen",side_effect=response):
            with self.assertRaisesRegex(RuntimeError,"Protected reference advanced"):
                guard.check_preserved_refs()

    def test_reference_failure_blocks_process_start(self):
        attempt=object.__new__(guard.Attempt)
        with patch("guard.check_preserved_refs",side_effect=RuntimeError("Protected reference advanced")), \
             patch("guard.subprocess.Popen") as spawn:
            with self.assertRaisesRegex(RuntimeError,"Protected reference advanced"):
                attempt.command(["owned"],"ref-denial")
            spawn.assert_not_called()


    def test_effective_start_requires_eight_gib(self):
        self.assertIsNone(guard.starting_memory_reason(8*1024**3, True))
        self.assertEqual(guard.starting_memory_reason(8*1024**3-1, True), "effective_ram_start_below_8_GiB")
        self.assertEqual(guard.starting_memory_reason(5*1024**3, True), "effective_ram_start_below_8_GiB")
        self.assertIsNone(guard.starting_memory_reason(7*1024**3, False))

    def test_effective_memory_respects_all_actual_cgroup_constraints(self):
        self.assertEqual(guard.effective_memory(14*1024**3, []), 14*1024**3)
        self.assertEqual(guard.effective_memory(14*1024**3, [(10*1024**3, 3*1024**3)]), 7*1024**3)
        self.assertEqual(guard.effective_memory(6*1024**3, [(10*1024**3, 3*1024**3)]), 6*1024**3)
        self.assertEqual(guard.effective_memory(14*1024**3, [(10*1024**3, 3*1024**3), (8*1024**3, 4*1024**3)]), 4*1024**3)
        self.assertEqual(guard.effective_memory(100, [(1, 2)]), 0)
        for capacities in [[(0, 1)], [(1, -1)], [("max", 1)]]:
            with self.assertRaises(RuntimeError):
                guard.effective_memory(100, capacities)

    def test_effective_sample_keeps_physical_and_process_budgets_separate(self):
        module = unittest.mock.Mock()
        module.sample.return_value = {"ram_available": 14*1024**3, "disk_free": 4*1024**3}
        with patch("guard.cgroup_capacities", return_value=[(10*1024**3, 3*1024**3)]):
            result = guard.effective_sample(module)
        self.assertEqual(result["physical_ram_available"], 14*1024**3)
        self.assertEqual(result["ram_available"], 7*1024**3)
        self.assertEqual(result["disk_free"], 4*1024**3)



    def test_actual_frontend_receipt_requires_guarded_six_gib_child_and_budget(self):
        first = {"component":"jrc_vite_heap","heapMiB":6144,"initial":{"availableMemory":8*1024**3,"diskFree":3*1024**3}}
        last = {"component":"jrc_vite_heap","passed":True,"code":0,"reason":None,
                "minimumMemory":750*1024**2+1,"minimumDisk":750000001}
        log = "#1 0.1 " + json.dumps(first,separators=(",",":")) + "\n#1 2.0 " + json.dumps(last,separators=(",",":"))
        self.assertTrue(guard.frontend_receipt(log)["passed"])
        for invalid in ["", log+"\n"+json.dumps(last,separators=(",",":")),
                        log.replace('"heapMiB":6144','"heapMiB":4096'),
                        log.replace('"passed":true','"passed":false')]:
            with self.assertRaises(RuntimeError):
                guard.frontend_receipt(invalid)

    def test_normal_runtime_must_not_inherit_frontend_heap_hook(self):
        guard.runtime_environment(["RAILS_ENV=production","NODE_OPTIONS=--max-old-space-size=4096"])
        for env in [["NODE_OPTIONS=--max-old-space-size=6144"],
                    ["JRC_VITE_BUILD_HEAP_MIB=6144"],
                    ["VITE_RUBY_VITE_BIN_PATH=/app/script/jrc_vite_build.mjs"]]:
            with self.assertRaises(RuntimeError):
                guard.runtime_environment(env)



    def test_http_origin_uses_owned_internal_ip_without_published_port(self):
        info = {"Config":{"Labels":{"jrc.runtime.run":"owned"}},"State":{"Running":True},
                "NetworkSettings":{"Ports":{},"Networks":{"owned":{"IPAddress":"172.20.0.2"}}}}
        self.assertEqual(guard.internal_origin(info,"owned"),"http://172.20.0.2:3000")

    def test_http_origin_rejects_foreign_stopped_or_extra_network(self):
        info = {"Config":{"Labels":{"jrc.runtime.run":"owned"}},"State":{"Running":True},
                "NetworkSettings":{"Ports":{},"Networks":{"owned":{"IPAddress":"172.20.0.2"}}}}
        variants = [copy.deepcopy(info) for _ in range(4)]
        variants[0]["Config"]["Labels"]["jrc.runtime.run"] = "other"
        variants[1]["State"]["Running"] = False
        variants[2]["NetworkSettings"]["Networks"] = {}
        variants[3]["NetworkSettings"]["Networks"]["foreign"] = {"IPAddress":"172.21.0.2"}
        for variant in variants:
            with self.assertRaises(RuntimeError):
                guard.internal_origin(variant,"owned")

    def test_http_origin_rejects_public_loopback_missing_or_invalid_ip(self):
        for address in ["8.8.8.8","127.0.0.1","0.0.0.0","224.0.0.1","::1","", "invalid"]:
            info = {"Config":{"Labels":{"jrc.runtime.run":"owned"}},"State":{"Running":True},
                    "NetworkSettings":{"Networks":{"owned":{"IPAddress":address}}}}
            with self.assertRaises(RuntimeError):
                guard.internal_origin(info,"owned")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(GuardTest)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {"tests":result.testsRun,"failures":len(result.failures),"errors":len(result.errors),"skipped":len(result.skipped)}
    Path(os.environ["GUARD_TEST_REPORT"]).write_text(json.dumps(report)+"\n")
    sys.exit(0 if result.wasSuccessful() and result.testsRun==24 and not result.skipped else 1)
