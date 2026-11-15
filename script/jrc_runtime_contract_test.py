"""Read-only consistency proof for the isolated runtime candidate."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
# Reviewed merge of A-G and the retained WhatsApp history increment. The
# runtime delta remains restricted to reviewed fixes and the exact schema
# reconciliation of tables already defined by unchanged migrations.
BASE = "c6eb87661bfd2dd5f50e3868f30706770b562655"
RUBY_DIGEST = "a28982cf8ed78eb0d222e51bc6788335d33ef191bfc6fc39da138577e611741d"
NODE_DIGEST = "116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5"
REVIEWED_RETRY_SOURCES = {
    "app/javascript/dashboard/components-next/message/MessageError.vue":
        "c09c8373e8fdc40ecefa7610edad4d335853fa715c8d760c22062d202280d568",
    "app/javascript/dashboard/components-next/message/specs/MessageError.spec.js":
        "bf73b6435280320edcec71b8dd9a816f081c6f480cc4a4ca1350adf9f099f361",
    "app/javascript/dashboard/i18n/locale/en/chatlist.json":
        "45bcaa5fb6743dc22d912db7cd71137d34f669f4d8d33a9aa4ed177be90873ec",
    "app/services/whatsapp/retry_policy.rb":
        "ec633e354766baff4881f73dc27ffc3dbe9d37579ccb6ac0fc61e1661e36598f",
}

# Reviewed approvals increment 56bacc36 plus the stale-summary regression.
# Explicit quick-reply review: 2be22e86 and eight independently fingerprinted
# release fixes. No path discovery, wildcard admission or relaxed assertions.
REVIEWED_APPROVAL_SOURCES = {
    "app/controllers/api/v1/accounts/approvals/policies_controller.rb": "750f974b5c632702795954077575c389887c9dd11ffae3fc0df7258021813967",
    "app/controllers/api/v1/accounts/approvals/requests_controller.rb": "a537a402cc25da031133ec23416a54eb9894e543fa8ac69f5db3a307890e212c",
    "app/controllers/api/v1/accounts/canned_responses_controller.rb": "53c52dfa08d321809ad02be486477a2ce2faf36fb3358510fd3d13ce8f50c970",
    "app/javascript/dashboard/api/cannedResponse.js": "fdf786cde7e366aa952b899494d8c19588600347cdec5fd27d8f6a29e3bbff15",
    "app/javascript/dashboard/api/specs/cannedResponseRevision.spec.js": "0fb389fa3b5c8a325eecd77820b2765a6f7e9b3a5107c6065c6b349210cd76af",
    "app/javascript/dashboard/components/widgets/WootWriter/Editor.vue": "6318e88a065c806f4ae5e16d1bd92a3b33b5ae5d145382347b77d886806fb154",
    "app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue": "f01761ccc4c83aa3b396cd1e34a9d1a1fe8b54aac540e2772591b31850a904a0",
    "app/javascript/dashboard/components/widgets/conversation/CannedResponse.vue": "113a5a49778c1dfd49d2e901b83ba80ca31de3ae6583360c9dada94d7cfd5f1f",
    "app/javascript/dashboard/components/widgets/conversation/QuickReplyPicker.vue": "8ca89389991b3f32c83b5a4301a9306931da561bb21aeecdaee07969361c93d4",
    "app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue": "80a54f1814e425a0d0893dbcf77b9c75cdb066ed9d0900b7057feaae0d1c0c82",
    "app/javascript/dashboard/components/widgets/conversation/specs/CannedResponseReview.spec.js": "a2589977c9c9798f073559b57bbc81a1945d3f6fe1c62946563d81c927e29471",
    "app/javascript/dashboard/components/widgets/conversation/specs/QuickReplyPicker.spec.js": "f7ba120464df8699fbf32aa04e0931bafb0c5154e2e93e3e2709e5a9b2262af2",
    "app/javascript/dashboard/i18n/locale/en/cannedMgmt.json": "3da939cdd4efaca4046c2697a77e565eed6ad43076f2b8be60fa005410bc6fa6",
    "app/javascript/dashboard/i18n/locale/en/jrcApprovals.json": "6445f258bd366911252678fdfbb1b1ff2884d798beaebd04b6083d198459d13a",
    "app/javascript/dashboard/i18n/locale/pt_BR/cannedMgmt.json": "ae18052084e0913c8cbe4470510202c0d23908534fb48b9c5dd8ebd0ae8fbd51",
    "app/javascript/dashboard/i18n/locale/pt_BR/jrcApprovals.json": "0ddf3ff17c5bf9613a132def1914ff7b9a519458daae08eb615224ae5791711d",
    "app/javascript/dashboard/mixins/fileUploadMixin.js": "66b16ab042c84c682b52e6a75f2fecdb28d14bf1f9c1edcf8cae5b117883af8e",
    "app/javascript/dashboard/routes/dashboard/approvals/AdjustmentDialog.vue": "ca159d7699d5f699a9d343c16007f1e304db1288d0487dfd253be194b022a6a1",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalInbox.vue": "fc6a13b401537a72dc61ffa6a03963bf47db79f4fd9c9a725496ce22d1a90b58",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalStatus.vue": "92d9639f58f2269665856db75cfb8724b6dd3e84f044499ec2ae47d7764419ce",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalSummary.vue": "c26d419ff78e02bae067cb428f1af8937b2f9d43b01f0e7b880c7e0ba5aeaf14",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalsPage.vue": "23425102a6b867dd417b210d39af4403817912f9871d2bd87df51a87f4d4df15",
    "app/javascript/dashboard/routes/dashboard/approvals/CatalogImport.vue": "66550cc863a215f673b94e0435816c3fdedddb7ac57a5bf647c13dc59b858c63",
    "app/javascript/dashboard/routes/dashboard/approvals/PolicyEditor.vue": "e8778b0b7dec3ba05c2d91745e7ed680cdc990006926520810f28911d92ad961",
    "app/javascript/dashboard/routes/dashboard/approvals/RequestDetail.vue": "18c3f8248e39c54424c37f96a71d0c71ca435c63914482c2af388b942be292c4",
    "app/javascript/dashboard/routes/dashboard/approvals/SimulatorView.vue": "8f55e195a8f48d0edf5ceb1af1d87278d4487696ecfea7dc247099fb0b383758",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/approvals.spec.js": "63355d656c416369bdbfb0b21bd7900c3cb1e63b2d86f82fc6d44ba9af23504b",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/authorityLifecycle.spec.js": "4bd8315e69e7bbe1fbfbb204dfa79968aab1bb21a9c11134680fed5012aff2b8",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/catalogImport.spec.js": "01019f001c0f08ed1932fc6f4b4562c827dd586e0878067c707ea2496da39de4",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/portugueseCatalog.spec.js": "78688a3ed3612227e2d4642a30c488110638194dd5715eacb2bcb97d68b9b133",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/simulatorSelection.spec.js": "3f91f2600a6afc4cce3f9083be79fc39db4c85cdb2b7951ddbf4fef28897322d",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/workspace.spec.js": "d40106b78c9a06e1e5412b6661ef4e05d6990ce408ed6cbc3fbb049e5b80f589",
    "app/javascript/dashboard/routes/dashboard/inbox/HoyaInboxWorkspace.vue": "b4b3a026e7a09e3ef56b51d327109cfd69e7d6bf3340264c2ea07e14e2c8fa29",
    "app/javascript/dashboard/routes/dashboard/settings/canned/AddCanned.vue": "f221cbb952890219b4572317141437319d04e6fe8e6a7f6973003ffe8fd91238",
    "app/javascript/dashboard/routes/dashboard/settings/canned/CannedFileInput.vue": "086e8156b28cace5b94a01c79d79ea48901ac3dea4e15ba3a6f9cf9f132ac7e8",
    "app/javascript/dashboard/routes/dashboard/settings/canned/EditCanned.vue": "863409ba8f4122e3ec48919a74c243d4ccf6c8ffdc107a29c1f3c8ab479d9bea",
    "app/javascript/dashboard/routes/dashboard/settings/canned/Index.vue": "2ce9c27576c4e8375632f0edde0e53551288d5b81a08f09f4dd6f018d9507cda",
    "app/models/canned_response.rb": "35ef1967c148dabebdef870f2adeb83e6e0e08bed5ab3a9e1fdd6724944c801e",
    "app/services/canned_responses/delivery.rb": "b59679f6ae5e348843b6e6d565810f13275ec66cd0ee331b3c8da0adb5d20c32",
    "app/services/canned_responses/preview.rb": "99e03d5a70de498f4ab37f9d9b3cbc1922e27e76cfb5bf0c52d48371435027b1",
    "app/services/jrc_approvals/catalog_import.rb": "aa9d81af11915a189e407f517d921880885e57076aafb6615b18bd1c6f87ff01",
    "app/services/jrc_approvals/policies.rb": "abd58f8875250c41bab31ea0d3fe954cb8beb2795f692fbbc45b2002e8a5d0c6",
    "config/initializers/filter_parameter_logging.rb": "364b0cb66b93313ddd965faa1742190f7ea031c6b1e585e5e5c499bdfb33f1aa",
    "config/routes.rb": "ef44c34897d052579395f94795f1e5ae724c3af93e551f30896b4e727403d97c",
    "config/routes/jrc_approvals.rb": "7823d2773c93ede1b3d7877deb77fa5cce005068a56fc27bd0e5b8ff8bf6b5f3",
    "spec/requests/api/v1/accounts/jrc_approvals/workspace_spec.rb": "3f81940703dd516fd886fc2634d1d1e7dfc3a6980dba66ecb0bc93893044d1e6",
}


REVIEWED_MODULE_MANIFESTS = {
    "config/jrc_flow_ownership_guards.json": "f468a2d820e4bf42f32c32e80a9591d23cda72c7cd7144e547ed4ef8d8625cb5",
    "deploy/jrc/MODULE-COMPOSITION-MANIFEST.json": "fee2a9a7985c4345a11256fb8dd326e62b0893b676a436098d3fd473175cc9d5",
}


def original(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT).decode()


def verify_reviewed_lock(lock, baseline):
    expected = baseline.replace("ruby 3.4.4p34", "ruby 3.4.12p148")
    assert expected.count("    scout_apm (5.3.3)\n") == 1
    assert expected.count("\n  scout_apm\n") == 1
    expected = expected.replace("    scout_apm (5.3.3)\n", "    scout_apm (5.7.0)\n")
    expected = expected.replace("\n  scout_apm\n", "\n  scout_apm (= 5.7.0)\n")
    assert lock == expected, "Only the reviewed Scout 5.7.0 update and Ruby runtime change are permitted"


def verify_reviewed_retry_sources(root):
    for name, expected in REVIEWED_RETRY_SOURCES.items():
        actual = hashlib.sha256((root / name).read_text(encoding="utf-8").encode()).hexdigest()
        assert actual == expected, "Unreviewed retry source: " + name


def verify_reviewed_approval_sources(root):
    for name, expected in REVIEWED_APPROVAL_SOURCES.items():
        actual = hashlib.sha256((root / name).read_text(encoding="utf-8").encode()).hexdigest()
        assert actual == expected, "Unreviewed approval source: " + name


def verify_reviewed_module_manifests(root):
    for name, expected in REVIEWED_MODULE_MANIFESTS.items():
        actual = hashlib.sha256((root / name).read_text(encoding="utf-8").encode()).hexdigest()
        assert actual == expected, "Unreviewed module manifest: " + name


def verify():
    assert (ROOT / ".ruby-version").read_text().strip() == "3.4.12"
    assert (ROOT / ".nvmrc").read_text().strip() == "24.22.3"
    assert "ruby '3.4.12'" in (ROOT / "Gemfile").read_text()
    lock = (ROOT / "Gemfile.lock").read_text()
    assert "\n   ruby 3.4.12p148\n" in lock
    verify_reviewed_lock(lock, original("Gemfile.lock"))
    expected_gemfile = original("Gemfile").replace("ruby '3.4.4'", "ruby '3.4.12'").replace(
        "gem 'scout_apm', require: false", "gem 'scout_apm', '5.7.0', require: false")
    assert (ROOT / "Gemfile").read_text() == expected_gemfile
    assert (ROOT / "pnpm-lock.yaml").read_text() == original("pnpm-lock.yaml")
    docker = (ROOT / "docker/Dockerfile").read_text()
    baseline_docker = subprocess.check_output(
        ["git", "show", "d11c879a3d6e27499e1aea45736797a6e913b829:docker/Dockerfile"], cwd=ROOT, text=True)
    old_assets = "  SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile " + chr(92)
    scoped_assets = "\n".join([
        "  SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled " + chr(92),
        '  JRC_VITE_BUILD_HEAP_MIB="$JRC_VITE_BUILD_HEAP_MIB" ' + chr(92),
        "  VITE_RUBY_VITE_BIN_PATH=/app/script/jrc_vite_build.mjs " + chr(92),
        "  bundle exec rake assets:precompile " + chr(92)])
    expected_docker = baseline_docker.replace(
        "# generate production assets if production environment\n",
        "# This larger heap is used only by the Vite child in the assets RUN.\n"
        "ARG JRC_VITE_BUILD_HEAP_MIB=6144\n# generate production assets if production environment\n").replace(old_assets, scoped_assets)
    assert docker == expected_docker, "Only the reviewed frontend heap scope may change"
    assert docker.split("# final build stage\n", 1)[1] == baseline_docker.split("# final build stage\n", 1)[1]
    ruby_base = "docker.io/library/ruby:3.4.12-alpine3.24@sha256:" + RUBY_DIGEST
    node_base = "docker.io/library/node:24.22.3-alpine3.24@sha256:" + NODE_DIGEST
    assert docker.count(ruby_base) == 2 and docker.count(node_base) == 1
    assert docker.count('ARG NODE_VERSION="24.22.3"') == 2
    assert "ruby-full" not in docker and "ruby-dev" not in docker
    assert docker.count("libstdc++") == 2 and docker.count("libgcc") == 2
    assert "ttf-dejavu" in docker and "tesseract-ocr-data-por" in docker and "poppler-utils" in docker
    for workflow in (ROOT / ".github/workflows").glob("*.yml"):
        pins = re.findall(r"ruby-version:\s*['\"]([0-9.]+)['\"]", workflow.read_text())
        assert all(pin == "3.4.12" for pin in pins), workflow
    protected = ["db", "app", "config", "lib", "enterprise", "services",
                 "docker/nico-runtime.Dockerfile", "docker/nico-test.Dockerfile",
                 ".github/scripts/jrc_ci_apt_setup.sh", "script/jrc_ag_native_plan.py"]
    changed = subprocess.check_output(["git", "diff", "--name-only", BASE, "--", *protected],
                                      cwd=ROOT, text=True).splitlines()
    reviewed_path = "app/models/jrc_crm/backoffice_request.rb"
    reviewed_sha = "599bc1fce954fe4bcc58aa98117722628001939b24f77522f178bd0bb90331bd"
    regression = "spec/services/jrc_crm/backoffice_request_number_spec.rb"
    regression_sha = "f424461b1008fc5942e421e430a283485e7dd54b8d4551a339ece28abaaa2172"
    pagination_fixture = "app/javascript/dashboard/routes/dashboard/inbox/specs/InboxList.spec.js"
    pagination_sha = "0dd4f4ed7960eb673cadf1c388073ff2af99c90de2f2dd6119321dff05c630a7"
    reviewed_schema = "db/schema.rb"
    schema_sha = "ca110aa5f83259333a4399a3d88d34b17c77a70fcabe6ae542110f0ee813322e"
    # The old pagination fixture omitted the backend membership proof. Admit
    # only this reviewed test update; the product authorization is unchanged.
    approval_paths = [name for name in REVIEWED_APPROVAL_SOURCES if name.startswith(("app/", "config/"))]
    module_paths = [name for name in REVIEWED_MODULE_MANIFESTS if name.startswith(("app/", "config/"))]
    assert changed == sorted([reviewed_path, pagination_fixture, reviewed_schema, *REVIEWED_RETRY_SOURCES, *approval_paths, *module_paths]), changed
    verify_reviewed_approval_sources(ROOT)
    verify_reviewed_module_manifests(ROOT)
    verify_reviewed_retry_sources(ROOT)
    assert hashlib.sha256((ROOT / reviewed_path).read_bytes()).hexdigest() == reviewed_sha
    assert hashlib.sha256((ROOT / regression).read_bytes()).hexdigest() == regression_sha
    assert hashlib.sha256((ROOT / pagination_fixture).read_bytes()).hexdigest() == pagination_sha
    # Git's text checkout uses CRLF on Windows and LF in the hosted runner.
    # Check the exact canonical text, without admitting any content changes.
    assert hashlib.sha256((ROOT / reviewed_schema).read_text().encode()).hexdigest() == schema_sha
    fixes = [{"path": reviewed_path, "sha256": reviewed_sha,
              "regression": regression, "regression_sha256": regression_sha}]
    assert (ROOT / ".dockerignore").read_text() == original(".dockerignore")
    assert "test\n" in (ROOT / ".dockerignore").read_text()
    return {"passed": True, "base_sha": BASE, "ruby": "3.4.12", "patchlevel": 148,
            "node": "24.22.3", "alpine": "3.24", "gem_versions_unchanged": False,
            "all_other_gem_versions_unchanged": True,
            "reviewed_gem_changes": [{"gem": "scout_apm", "from": "5.3.3", "to": "5.7.0",
                "upstream_fix": "https://github.com/scoutapp/scout_apm_ruby/pull/552"}],
            "frontend_vite_heap_mib": 6144, "frontend_effective_memory_min_gib": 8,
            "runtime_image_stage_unchanged_from_d11c879a": True,
            "pnpm_lock_unchanged": True, "functional_sources_unchanged": False,
            "all_other_functional_sources_unchanged": True, "migrations_unchanged": True,
            "reviewed_functional_fixes": fixes,
            "reviewed_approval_commit": "56bacc36cf6bf65f18a5f637eeb5a4bff1f42acb",
            "reviewed_quick_reply_base_commit": "2be22e86baecbe75c302bb03208e78e67301c743",
            "reviewed_release_regressions": ["attachment_revision", "catalog_file_replacement", "native_channel_length"],
            "reviewed_approval_files": [{"path": path, "sha256_canonical_utf8": sha}
                                        for path, sha in REVIEWED_APPROVAL_SOURCES.items()],
            "reviewed_module_manifests": [{"path": path, "sha256_canonical_utf8": sha}
                                          for path, sha in REVIEWED_MODULE_MANIFESTS.items()],
            "reviewed_retry_commit": "549102e44a0141d088e88551cb552d1157c17076",
            "reviewed_retry_overlay": "Preserve backend retry denial in the existing tooltip, with null metadata regression",
            "reviewed_retry_files": [{"path": path, "sha256_canonical_utf8": sha}
                                     for path, sha in REVIEWED_RETRY_SOURCES.items()],
            "reviewed_test_fixtures": [{"path": pagination_fixture, "sha256": pagination_sha}],
            "reviewed_schema_reconciliation": {"path": reviewed_schema, "sha256": schema_sha,
                "tables": ["whatsapp_retry_attempts", "whatsapp_retry_receipts", "jrc_service_desk_report_exports"],
                "migration_sources_unchanged": True},
            "separate_nico_image_unchanged": True, "docker_build_executed": False}


if __name__ == "__main__":
    result = verify()
    if len(sys.argv) == 2:
        Path(sys.argv[1]).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
