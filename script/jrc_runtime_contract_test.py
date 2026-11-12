"""Read-only consistency proof for the isolated runtime candidate."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
BASE = "cad427d400d824fc1fdc06c1c1079f324e7f3f6c"
RUBY_DIGEST = "a28982cf8ed78eb0d222e51bc6788335d33ef191bfc6fc39da138577e611741d"
NODE_DIGEST = "116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5"


def original(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT).decode()


def verify():
    assert (ROOT / ".ruby-version").read_text().strip() == "3.4.12"
    assert (ROOT / ".nvmrc").read_text().strip() == "24.22.3"
    assert "ruby '3.4.12'" in (ROOT / "Gemfile").read_text()
    lock = (ROOT / "Gemfile.lock").read_text()
    assert "\n   ruby 3.4.12p148\n" in lock
    assert lock.replace("ruby 3.4.12p148", "ruby 3.4.4p34") == original("Gemfile.lock")
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
    for path in ["db", "app", "config", "lib", "enterprise", "services",
                 ".github/scripts/jrc_ci_apt_setup.sh", "script/jrc_ag_native_plan.py"]:
        subprocess.run(["git", "diff", "--exit-code", BASE, "--", path], cwd=ROOT, check=True,
                       stdout=subprocess.DEVNULL)
    assert (ROOT / ".dockerignore").read_text() == original(".dockerignore")
    assert "test\n" in (ROOT / ".dockerignore").read_text()
    return {"passed": True, "base_sha": BASE, "ruby": "3.4.12", "patchlevel": 148,
            "node": "24.22.3", "alpine": "3.24", "gem_versions_unchanged": True,
            "pnpm_lock_unchanged": True, "functional_sources_and_migrations_unchanged": True,
            "separate_nico_image_unchanged": True, "docker_build_executed": False}


if __name__ == "__main__":
    result = verify()
    if len(sys.argv) == 2:
        Path(sys.argv[1]).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
