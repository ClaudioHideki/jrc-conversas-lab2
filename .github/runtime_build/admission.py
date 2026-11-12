"""Admission for this user's exact single runtime attempt. Read-only GitHub API."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = "dce805894696416ed5397c268efb4acecb8ecfc7"
APPROVED = "716647d67e96b77e8a56125ab0033c173bd68485"
BRANCH = "ci/runtime-build-dce80589-20261112"


def require(value, message):
    if not value:
        raise RuntimeError(message)


def filehash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(mode):
    execution = os.environ["EXPECTED_EXECUTION_SHA"]
    require(os.environ["GITHUB_SHA"] == execution and os.environ["GITHUB_REF_NAME"] == BRANCH, "Wrong execution")
    require(os.environ["EXPECTED_PRODUCT_SHA"] == PRODUCT and os.environ["EXPECTED_APPROVED_SHA"] == APPROVED, "Authorization differs")
    require(os.environ["RUNNER_ENVIRONMENT"] == "github-hosted" and os.environ["GITHUB_EVENT_NAME"] == "workflow_dispatch"
            and os.environ["GITHUB_RUN_ATTEMPT"] == "1", "First hosted manual run required")
    for folder, sha in [(ROOT, execution), (ROOT / "product", PRODUCT), (ROOT / "approved", APPROVED)]:
        require(subprocess.check_output(["git", "-C", str(folder), "rev-parse", "HEAD"], text=True).strip() == sha, "Checkout differs")
        require(not subprocess.check_output(["git", "-C", str(folder), "status", "--porcelain", "--untracked-files=no"], text=True).strip(), "Tracked checkout dirty")
        extras = subprocess.check_output(["git", "-C", str(folder), "ls-files", "--others", "--exclude-standard", "--directory"], text=True).splitlines()
        require(set(extras) <= {"product/", "approved/"} if folder == ROOT else not extras, "Unexpected untracked source")
    approved = ROOT / "approved/.github/release"
    current = ROOT / ".github/release"
    require(filehash(approved / "release-evidence-lock.json") == "3785e9512116e1e20cc9a60e65e96236a0466910859cbd93cec4a3439546d42a", "Approved lock changed")
    for name in ["gate.py", "test_gate.py"]:
        require((current / name).read_bytes() == (approved / name).read_bytes(), "Approved gate or denial tests changed")
    oldlock = json.loads((approved / "release-evidence-lock.json").read_text())
    wanted = {**oldlock, "infrastructure_branch": BRANCH}
    lock = json.loads((current / "release-evidence-lock.json").read_text())
    require(lock == wanted, "Only the execution branch binding may differ in the lock")
    for path, expected in oldlock["source_hashes"].items():
        require(filehash(ROOT / "product" / path) == expected, "Source hash differs: " + path)
    spec = importlib.util.spec_from_file_location("approved_gate", current / "gate.py")
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    gh = gate.GitHub("ClaudioHideki/jrc-conversas-lab2", os.environ["GH_TOKEN"])
    runs = gh.api("/actions/workflows/ag-native-candidate.yml/runs?branch=" + BRANCH + "&event=workflow_dispatch&per_page=100")
    require(runs["total_count"] == 1 and len(runs["workflow_runs"]) == 1 and str(runs["workflow_runs"][0]["id"]) == os.environ["GITHUB_RUN_ID"], "Single authorized workflow run required")
    require(gh.api("/git/ref/heads/ci/release-gate-runtime-dce80589-20261112")["object"]["sha"] == APPROVED, "Approved ref moved")
    r = gh.api("/actions/runs/43310498138")
    require(r["head_sha"] == APPROVED and r["run_attempt"] == 1 and r["conclusion"] == "success" and r["status"] == "completed", "Approved gate run not successful")
    arts = gh.api("/actions/runs/43310498138/artifacts?per_page=100")
    require(arts["total_count"] == len(arts["artifacts"]) == 1, "Approved gate artifact missing")
    artifact = arts["artifacts"][0]
    require(artifact["digest"] == "sha256:502adb1692718e8b34362d81d9057512758db3ff35cc0a5a8f425821d4e5fa76" and not artifact["expired"], "Approved gate artifact changed")
    z = gate.archive(gh.download(artifact["archive_download_url"]), artifact["digest"][7:])
    raw = gate.member(z, "release-gate-report.json")
    require(hashlib.sha256(raw).hexdigest() == "4b8bcc8d1a7970eca505bef169d259f6bd08583309365e5363bbce5fab7c42ea", "Approved report differs")
    report = json.loads(raw)
    require(report["passed"] and report["product_sha"] == PRODUCT and report["infrastructure_sha"] == APPROVED, "Approved report identity differs")
    require(json.loads(gate.member(z, "gate-tests.json")) == {"tests":31,"failures":0,"errors":0,"skipped":0}, "Approved denial tests differ")
    gate.run_identity(oldlock, gh.api("/actions/runs/43296936629"))
    if mode == "build":
        rid = os.environ["GITHUB_RUN_ID"]
        run = gh.api("/actions/runs/" + rid)
        require(run["head_sha"] == execution and run["run_attempt"] == 1 and run["status"] in ["queued", "in_progress"] and run["conclusion"] is None, "Wrong active build run")
        jobs = gh.api("/actions/runs/" + rid + "/attempts/1/jobs?per_page=100")
        require(jobs["total_count"] == len(jobs["jobs"]) == 2, "Unexpected jobs")
        g = next(j for j in jobs["jobs"] if j["name"] == "evidence-gate")
        b = next(j for j in jobs["jobs"] if j["name"] == "image-build")
        require(g["conclusion"] == "success" and g["status"] == "completed" and b["status"] == "in_progress" and b["runner_id"] and b["head_sha"] == execution and b["run_attempt"] == 1, "Fresh gate not completed")
        arts = gh.api("/actions/runs/" + rid + "/artifacts?per_page=100")
        matches = [a for a in arts["artifacts"] if a["name"] == "release-evidence-gate-" + execution]
        require(len(matches) == 1 and not matches[0]["expired"], "Fresh gate artifact missing")
        a = matches[0]
        z = gate.archive(gh.download(a["archive_download_url"]), a["digest"][7:])
        fresh = json.loads(gate.member(z, "release-gate-report.json"))
        require(fresh["passed"] and fresh["product_sha"] == PRODUCT and fresh["infrastructure_sha"] == execution, "Fresh report identity differs")
        require(fresh["matrix_identities"] == 36 and fresh["matrix_example_executions"] == 5554 and len(fresh["artifacts"]) == 46, "Fresh evidence incomplete")
        require(json.loads(gate.member(z, "gate-tests.json")) == {"tests":31,"failures":0,"errors":0,"skipped":0}, "Fresh gate denial tests failed")
    print(json.dumps({"admitted":True,"mode":mode,"product_sha":PRODUCT,"approved_gate_sha":APPROVED,
                      "execution_sha":execution,"original_gate_unchanged":True,"no_registry_publication":True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["prepare", "build"], required=True)
    main(parser.parse_args().mode)
