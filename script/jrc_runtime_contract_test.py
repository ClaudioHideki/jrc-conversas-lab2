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


def original(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT).decode()


def verify_reviewed_lock(lock, baseline):
    expected = baseline.replace("ruby 3.4.4p34", "ruby 3.4.12p148")
    assert expected.count("    scout_apm (5.3.3)\n") == 1
    assert expected.count("\n  scout_apm\n") == 1
    expected = expected.replace("    scout_apm (5.3.3)\n", "    scout_apm (5.7.0)\n")
    expected = expected.replace("\n  scout_apm\n", "\n  scout_apm (= 5.7.0)\n")
    assert lock == expected, "Only the reviewed Scout 5.7.0 update and Ruby runtime change are permitted"


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
    schema_sha = "96d4d91e522dd61be81edb5f4e19d840241693702a910ecea4e2d48c4e1db78c"
    # The old pagination fixture omitted the backend membership proof. Admit
    # only this reviewed test update; the product authorization is unchanged.
    assert changed == sorted([reviewed_path, pagination_fixture, reviewed_schema]), changed
    assert hashlib.sha256((ROOT / reviewed_path).read_bytes()).hexdigest() == reviewed_sha
    assert hashlib.sha256((ROOT / regression).read_bytes()).hexdigest() == regression_sha
    assert hashlib.sha256((ROOT / pagination_fixture).read_bytes()).hexdigest() == pagination_sha
    assert hashlib.sha256((ROOT / reviewed_schema).read_bytes()).hexdigest() == schema_sha
    fixes = [{"path": reviewed_path, "sha256": reviewed_sha,
              "regression": regression, "regression_sha256": regression_sha}]
    assert (ROOT / ".dockerignore").read_text() == original(".dockerignore")
    assert "test\n" in (ROOT / ".dockerignore").read_text()
    return {"passed": True, "base_sha": BASE, "ruby": "3.4.12", "patchlevel": 148,
            "node": "24.22.3", "alpine": "3.24", "gem_versions_unchanged": False,
            "all_other_gem_versions_unchanged": True,
            "reviewed_gem_changes": [{"gem": "scout_apm", "from": "5.3.3", "to": "5.7.0",
                "upstream_fix": "https://github.com/scoutapp/scout_apm_ruby/pull/552"}],
            "pnpm_lock_unchanged": True, "functional_sources_unchanged": False,
            "all_other_functional_sources_unchanged": True, "migrations_unchanged": True,
            "reviewed_functional_fixes": fixes,
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
