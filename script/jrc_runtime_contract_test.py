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
REVIEWED_APPROVAL_SOURCES = {
    "app/controllers/api/v1/accounts/approvals/requests_controller.rb": "a537a402cc25da031133ec23416a54eb9894e543fa8ac69f5db3a307890e212c",
    "app/javascript/dashboard/i18n/locale/en/jrcApprovals.json": "36666da071f803394558d74527c7770b4fc5706bb1d4f9329f849db70b844a0d",
    "app/javascript/dashboard/i18n/locale/pt_BR/jrcApprovals.json": "2d507600fd7b528519c71fb2a914570b5a4a459bde5886a591f823616e144e85",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalInbox.vue": "fc6a13b401537a72dc61ffa6a03963bf47db79f4fd9c9a725496ce22d1a90b58",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalStatus.vue": "92d9639f58f2269665856db75cfb8724b6dd3e84f044499ec2ae47d7764419ce",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalSummary.vue": "c26d419ff78e02bae067cb428f1af8937b2f9d43b01f0e7b880c7e0ba5aeaf14",
    "app/javascript/dashboard/routes/dashboard/approvals/ApprovalsPage.vue": "3e8ca63b1c44882b95f783b5744d44017d68246b8fbae1949ed2eb1770b05e22",
    "app/javascript/dashboard/routes/dashboard/approvals/PolicyEditor.vue": "2047349671a7ee490f93a7213bef591a5e0ca52ae5ca48da386d42ae13c354d3",
    "app/javascript/dashboard/routes/dashboard/approvals/RequestDetail.vue": "18c3f8248e39c54424c37f96a71d0c71ca435c63914482c2af388b942be292c4",
    "app/javascript/dashboard/routes/dashboard/approvals/SimulatorView.vue": "8f55e195a8f48d0edf5ceb1af1d87278d4487696ecfea7dc247099fb0b383758",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/authorityLifecycle.spec.js": "81151f55ca2a08f3cb953ef4d17fd47ebfac516a95b32a5e8d5b9bbef8f40353",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/simulatorSelection.spec.js": "3f91f2600a6afc4cce3f9083be79fc39db4c85cdb2b7951ddbf4fef28897322d",
    "app/javascript/dashboard/routes/dashboard/approvals/specs/workspace.spec.js": "d40106b78c9a06e1e5412b6661ef4e05d6990ce408ed6cbc3fbb049e5b80f589",
    "config/routes/jrc_approvals.rb": "184f60925c75386000d2945e1f14e2b8d30c5ebf5177b70b5bc8e2b842eb5326",
    "spec/requests/api/v1/accounts/jrc_approvals/workspace_spec.rb": "3f81940703dd516fd886fc2634d1d1e7dfc3a6980dba66ecb0bc93893044d1e6"
}


REVIEWED_MODULE_MANIFESTS = {
    "config/jrc_flow_ownership_guards.json": "ba18d05301e9501e2e931c194c7b6a133dfee2843b4c0cb17c809cb5f4cdc2ad",
    "deploy/jrc/MODULE-COMPOSITION-MANIFEST.json": "a4ff7863fe33c3b757efbedb558b13adead056d91fcd0449c71eb067c372a3d9",
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
