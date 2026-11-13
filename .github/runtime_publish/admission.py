"""Admission for this user's exact single runtime attempt. Read-only GitHub API."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = "5640793988fbf63ac46b0db3466722fc650f0d01"
APPROVED = "48b8a4f891f5cdd0ea3fcf4a3846c8b10c95015d"
BRANCH = "ci/runtime-ghcr-56407939-20261113"


def require(value, message):
    if not value:
        raise RuntimeError(message)


def filehash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()



def heap_evidence(gate, z, infrastructure):
    xml = ET.fromstring(gate.member(z, "vite-heap-tests.xml"))
    require(len(list(xml.iter("testcase"))) == 13
            and not any(list(xml.iter(k)) for k in ["failure", "error", "skipped"]),
            "Frontend-only heap tests incomplete")
    report = json.loads(gate.member(z, "guard-preflight.json"))
    require(report["passed"] and report["minimum_effective_ram_gib"] == 8
            and report["minimum_disk_gib"] == 3 and report["memory_reserve_mib"] == 750
            and report["disk_reserve_bytes"] == 750000000 and report["image_build_executed"] is False,
            "Effective memory/disk preflight missing")
    require(report["resources"]["ram_available"] >= 8*1024**3
            and report["resources"]["disk_free"] >= 3*1024**3, "Preflight resources inadequate")

    network = json.loads(gate.member(z, "http-network-regression.json"))
    require(network["passed"] and network["product_sha"] == PRODUCT
            and network["infrastructure_sha"] == infrastructure and network["network_is_internal"]
            and network["host_ports_published"] is False and network["login_status"] == 200
            and len(network["verified_assets"]) == 3 and network["inherited_proxies_bypassed"]
            and network["missing_route_rejected"] and network["transport"] == "owned_internal_ipv4"
            and network["application_image_built"] is False, "Real internal-network HTTP regression missing")

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
    require(filehash(approved / "release-evidence-lock.json") == "e0ca903ef12ac36e90395765d30cdb4b4330e6e4452d4809503afad4f4c9c5b0", "Approved lock changed")
    for name in ["gate.py", "test_gate.py", "scout_probe.py", "test_scout_probe.py"]:
        require((current / name).read_bytes() == (approved / name).read_bytes(), "Approved gate or denial tests changed")
    oldlock = json.loads((approved / "release-evidence-lock.json").read_text())
    wanted = {**oldlock, "infrastructure_branch": BRANCH}
    lock = json.loads((current / "release-evidence-lock.json").read_text())
    require(lock == wanted, "Only the execution branch binding may differ in the lock")
    for path, expected in oldlock["probe_hashes"].items():
        require(filehash(ROOT / path) == expected, "Approved probe differs: " + path)
    expected_guard = (ROOT / "approved/.github/runtime_build/guard.py").read_text().replace(
        'APPROVED = "3d1e41db6cd2a085cc7f6b988aa017bbed4d3a46"', 'APPROVED = "' + APPROVED + '"')
    expected_guard = expected_guard.replace('BRANCH = "ci/runtime-build-http-fix-20261113"', 'BRANCH = "' + BRANCH + '"').replace('"authorized_image_attempt": 4, "previous_image_run": 43355070847', '"authorized_image_attempt": 5, "previous_image_run": 43361093613')
    require((ROOT / ".github/runtime_build/guard.py").read_text() == expected_guard, "Approved resource guard template changed")
    require((ROOT / ".github/runtime_build/test_guard.py").read_bytes() ==
            (ROOT / "approved/.github/runtime_build/test_guard.py").read_bytes(), "Guard denial tests changed")
    require((ROOT / ".github/runtime_build/test_http_network.py").read_bytes() ==
            (ROOT / "approved/.github/runtime_build/test_http_network.py").read_bytes(), "Approved HTTP regression changed")
    for path, expected in oldlock["source_hashes"].items():
        require(filehash(ROOT / "product" / path) == expected, "Source hash differs: " + path)
    sys.path.insert(0, str(current))
    spec = importlib.util.spec_from_file_location("approved_gate", current / "gate.py")
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    gh = gate.GitHub("ClaudioHideki/jrc-conversas-lab2", os.environ["GH_TOKEN"])
    runs = gh.api("/actions/workflows/ag-native-candidate.yml/runs?branch=" + BRANCH + "&event=workflow_dispatch&per_page=100")
    require(runs["total_count"] == 1 and len(runs["workflow_runs"]) == 1 and str(runs["workflow_runs"][0]["id"]) == os.environ["GITHUB_RUN_ID"], "Single authorized workflow run required")
    require(gh.api("/git/ref/heads/ci/release-gate-http-fix-20261113")["object"]["sha"] == APPROVED, "Approved ref moved")
    r = gh.api("/actions/runs/43359959371")
    require(r["head_sha"] == APPROVED and r["run_attempt"] == 1 and r["conclusion"] == "success" and r["status"] == "completed", "Approved gate run not successful")
    arts = gh.api("/actions/runs/43359959371/artifacts?per_page=100")
    require(arts["total_count"] == len(arts["artifacts"]) == 1, "Approved gate artifact missing")
    artifact = arts["artifacts"][0]
    require(artifact["digest"] == "sha256:a7e9fe030bbc9dfd054ee46a3a468804946cbaa2dedff5354ce6331d443188ee" and not artifact["expired"], "Approved gate artifact changed")
    z = gate.archive(gh.download(artifact["archive_download_url"]), artifact["digest"][7:])
    raw = gate.member(z, "release-gate-report.json")
    require(hashlib.sha256(raw).hexdigest() == "2e52ab662420193f2098a98c5df9c077a4a484e2c04c4cb085057eea06624f43", "Approved report differs")
    report = json.loads(raw)
    require(report["passed"] and report["product_sha"] == PRODUCT and report["infrastructure_sha"] == APPROVED, "Approved report identity differs")
    require(json.loads(gate.member(z, "gate-tests.json")) == {"tests":32,"failures":0,"errors":0,"skipped":0}, "Approved denial tests differ")
    require(report["scout_probe_evidence"]["passed"] and report["scout_probe_evidence"]["probe_sha"] == "9131d1784a8256fed273b15f6f7b18389223612e", "Focused Scout/probe evidence missing")
    require(json.loads(gate.member(z, "scout-proof-tests.json")) == {"tests":2,"failures":0,"errors":0,"skipped":0}, "Focused denial tests failed")
    require(json.loads(gate.member(z, "guard-tests.json")) == {"tests":19,"failures":0,"errors":0,"skipped":0}, "Resource/initialization denial tests failed")
    receipt_unit = json.loads(gate.member(z, "receipt-unit.json"))
    require(receipt_unit["passed"] is True and receipt_unit["examples"] > 0 and receipt_unit["failures"] == 0 and receipt_unit["pending"] == 0, "Receipt unit checks missing")
    heap_evidence(gate, z, APPROVED)
    gate.run_identity(oldlock, gh.api("/actions/runs/43344850748"))
    if mode == "build":
        rid = os.environ["GITHUB_RUN_ID"]
        run = gh.api("/actions/runs/" + rid)
        require(run["head_sha"] == execution and run["run_attempt"] == 1 and run["status"] in ["queued", "in_progress"] and run["conclusion"] is None, "Wrong active build run")
        jobs = gh.api("/actions/runs/" + rid + "/attempts/1/jobs?per_page=100")
        require(jobs["total_count"] == len(jobs["jobs"]) == 3, "Unexpected jobs")
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
        require(fresh["scout_probe_evidence"]["passed"] and fresh["scout_probe_evidence"]["actual_pid_one"], "Fresh focused evidence missing")
        require(fresh["matrix_identities"] == 36 and fresh["matrix_example_executions"] == 5554 and len(fresh["artifacts"]) == 46, "Fresh evidence incomplete")
        require(json.loads(gate.member(z, "gate-tests.json")) == {"tests":32,"failures":0,"errors":0,"skipped":0}, "Fresh gate denial tests failed")
        require(json.loads(gate.member(z, "guard-tests.json")) == {"tests":19,"failures":0,"errors":0,"skipped":0}, "Fresh resource tests failed")
        heap_evidence(gate, z, execution)
    print(json.dumps({"admitted":True,"mode":mode,"product_sha":PRODUCT,"approved_gate_sha":APPROVED,
                      "execution_sha":execution,"original_gate_unchanged":True,"no_registry_publication":True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["prepare", "build"], required=True)
    main(parser.parse_args().mode)
