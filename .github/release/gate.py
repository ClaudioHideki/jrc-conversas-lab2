"""Read-only, exact-SHA release evidence gate. No image or publication path."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile


class GateError(Exception):
    pass


def require(value, message):
    if not value:
        raise GateError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def logical(name):
    require(name.startswith("rails (") and name.endswith(")"), "Invalid matrix job name")
    parts = [p.strip() for p in name[7:-1].split(",")]
    require(len(parts) in (4, 5), "Invalid matrix parameters")
    require(parts[0] in ("fresh", "upgrade"), "Invalid installation mode")
    require(parts[2].isdigit() and parts[3].isdigit(), "Invalid shard parameters")
    require(int(parts[3]) > 0 and int(parts[2]) < int(parts[3]), "Invalid shard range")
    return "|".join(parts[:4] + [parts[4] if len(parts) == 5 else ""])


def rspec(report, expected=None):
    s = report["summary"]
    for key in ("example_count", "failure_count", "pending_count", "errors_outside_of_examples_count"):
        require(type(s[key]) is int, "Non-integer RSpec count")
    require(s["example_count"] > 0, "Zero RSpec examples")
    require(all(s[k] == 0 for k in ("failure_count", "pending_count", "errors_outside_of_examples_count")),
            "RSpec failures, pending or outside errors")
    require(len(report["examples"]) == s["example_count"], "RSpec example count mismatch")
    require(all(e["status"] == "passed" for e in report["examples"]), "RSpec unpassed example")
    if expected is not None:
        require(s["example_count"] == expected, "Approved RSpec coverage changed")
    return s["example_count"]


def vue(report):
    require(report["success"] is True, "Vue unsuccessful")
    require(type(report["numTotalTests"]) is int and report["numTotalTests"] > 0, "Zero Vue tests")
    require(report["numTotalTests"] == report["numPassedTests"], "Vue count mismatch")
    require(all(type(report[k]) is int and report[k] == 0
                for k in ("numFailedTests", "numPendingTests", "numTodoTests")), "Vue unpassed tests")
    cases = [a for t in report["testResults"] for a in t["assertionResults"]]
    require(len(cases) == report["numTotalTests"], "Vue assertions missing")
    require(all(a["status"] == "passed" for a in cases), "Vue assertion not passed")
    return report["numTotalTests"]


def run_identity(lock, run):
    require(run["id"] == lock["native_run_id"], "Wrong native run")
    require(run["head_sha"] == lock["product_sha"], "Wrong product SHA")
    require(run["head_branch"] == lock["product_branch"], "Wrong product branch")
    require(run["path"] == lock["native_workflow"], "Wrong native workflow")
    require(run["run_attempt"] == lock["native_attempt"], "Native attempt changed")
    require(run["status"] == "completed" and run["conclusion"] == "success", "Native run not approved")
    require(run["head_repository"]["full_name"] == lock["repository"], "Wrong source repository")


def jobs_identity(lock, snapshot):
    jobs = snapshot["jobs"]
    expected = lock["mandatory_jobs"] + [lock["approved_skipped_job"]]
    require(snapshot["total_count"] == len(jobs) == len(expected), "Incomplete jobs response")
    require(len({j["id"] for j in jobs}) == len(jobs), "Duplicate job IDs")
    require(len({j["name"] for j in jobs}) == len(jobs), "Duplicate job identities")
    require({(j["id"], j["name"]) for j in jobs} == {(j["id"], j["name"]) for j in expected},
            "Job identity differs from approved snapshot")
    matrix = {}
    for job in jobs:
        require(job["head_sha"] == lock["product_sha"] and job["run_attempt"] == lock["native_attempt"],
                "Job source or attempt differs")
        require(job["run_id"] == lock["native_run_id"] and job["status"] == "completed", "Job incomplete")
        if job["name"] == lock["approved_skipped_job"]["name"]:
            require(job["conclusion"] == "skipped" and not job["steps"] and not job["runner_id"],
                    "Unauthorized build was executed")
            continue
        require(job["conclusion"] == "success" and job["runner_id"], "Mandatory job not approved")
        require(job["started_at"] and job["completed_at"] and job["steps"], "Missing real job execution")
        require(not any(s["conclusion"] in ("failure", "cancelled", "timed_out") for s in job["steps"]),
                "Job contains failed steps")
        if job["name"].startswith("rails ("):
            key = logical(job["name"])
            require(key not in matrix, "Duplicate logical matrix identity")
            matrix[key] = job
    wanted = {r["identity"]: r for r in lock["matrix"]}
    require(len(wanted) == len(matrix) == 36 and set(matrix) == set(wanted), "Logical matrix mismatch")
    require(all(matrix[k]["id"] == wanted[k]["job_id"] for k in wanted), "Matrix job ID changed")
    return matrix


def artifact_identity(lock, snapshot):
    artifacts = snapshot["artifacts"]
    require(snapshot["total_count"] == len(artifacts) == len(lock["artifacts"]), "Artifacts missing")
    require(len({a["id"] for a in artifacts}) == len(artifacts), "Duplicate artifacts")
    wanted = {a["id"]: a for a in lock["artifacts"]}
    require({a["id"] for a in artifacts} == set(wanted), "Artifact identity changed")
    for a in artifacts:
        e = wanted[a["id"]]
        require(a["name"] == e["name"] and a["digest"] == "sha256:" + e["sha256"], "Artifact digest changed")
        require(not a["expired"] and a["workflow_run"]["id"] == lock["native_run_id"]
                and a["workflow_run"]["head_sha"] == lock["product_sha"], "Artifact source/expiry invalid")
    return artifacts


def archive(raw, expected):
    require(sha(raw) == expected, "Downloaded artifact SHA-256 mismatch")
    z = zipfile.ZipFile(io.BytesIO(raw))
    names = z.namelist()
    require(len(names) == len(set(names)), "Duplicate archive entries")
    require(sum(i.file_size for i in z.infolist()) <= 64_000_000, "Archive exceeds size limit")
    for i in z.infolist():
        p = PurePosixPath(i.filename)
        require(not p.is_absolute() and ".." not in p.parts and "\\" not in i.filename, "Unsafe archive path")
        require((i.external_attr >> 16) & 0o170000 != 0o120000, "Archive symlink refused")
    return z


def member(z, name):
    names = [n for n in z.namelist() if n == name or n.endswith("/" + name)]
    require(len(names) == 1, "Required report missing or duplicated: " + name)
    return z.read(names[0])


def apt(log):
    matches = re.findall(r"CI Ubuntu mirror selected: (https://[A-Za-z0-9./-]+) \(APT signature verification follows\)", log)
    allowed = ("https://archive.ubuntu.com/ubuntu", "https://azure.archive.ubuntu.com/ubuntu",
               "https://mirrors.edge.kernel.org/ubuntu")
    require(len(matches) == 1 and matches[0] in allowed, "Missing approved HTTPS mirror proof")
    mirror = matches[0]
    for suite in ("noble", "noble-updates", "noble-backports", "noble-security"):
        require("CI Ubuntu connectivity OK: " + mirror + "/dists/" + suite + "/InRelease HTTP=200" in log,
                "Missing signed suite connectivity proof")
    require("CI Ubuntu APT metadata update passed with signature checks enabled: " + mirror in log,
            "Missing APT signature validation")
    return mirror


def report_kind(name):
    base = PurePosixPath(name).name
    if base.endswith(".json") and ("rspec" in base or "schema-regression" in base
                                  or base.endswith("-concurrency.json") or base == "whatsapp-native.json"):
        return "rspec"
    if base == "ag-vue-results.json" or base.endswith("vitest.json") or base == "whatsapp-ui-results.json":
        return "vue"
    return None


def runtime_host(report, product_sha):
    require(report["source_sha"] == product_sha, "Runtime host source mismatch")
    require(report["ruby"] == "3.4.12" and report["ruby_patchlevel"] == 148, "Wrong Ruby runtime")
    require(report["node"] == "v24.22.3", "Wrong Node runtime")
    require(report["runner_os"] == "Ubuntu 24.04" and "linux" in report["platform"], "Wrong native host")
    require(report["alpine_image_tested"] is False, "Unproved Alpine image claim")


def runtime_contract(report):
    require(report["passed"] is True and report["base_sha"] == "cad427d400d824fc1fdc06c1c1079f324e7f3f6c",
            "Runtime contract not approved")
    require(report["ruby"] == "3.4.12" and report["patchlevel"] == 148
            and report["node"] == "24.22.3" and report["alpine"] == "3.24", "Runtime contract versions mismatch")
    for key in ("gem_versions_unchanged", "pnpm_lock_unchanged", "all_other_functional_sources_unchanged",
                "migrations_unchanged", "separate_nico_image_unchanged"):
        require(report[key] is True, "Runtime preservation proof missing")
    require(report["functional_sources_unchanged"] is False, "Reviewed fix must be disclosed")
    require(report["reviewed_functional_fixes"] == [{
        "path": "app/models/jrc_crm/backoffice_request.rb",
        "sha256": "599bc1fce954fe4bcc58aa98117722628001939b24f77522f178bd0bb90331bd",
        "regression": "spec/services/jrc_crm/backoffice_request_number_spec.rb",
        "regression_sha256": "f424461b1008fc5942e421e430a283485e7dd54b8d4551a339ece28abaaa2172"
    }], "Unexpected functional change")
    require(report["docker_build_executed"] is False, "Unauthorized image build")


def migration(z, product_sha):
    r = json.loads(member(z, "ag-migration-audit-result.json"))
    require(r["source_sha"] == product_sha and r["production_changed"] is False
            and r["docker_build_executed"] is False, "Migration source or isolation invalid")
    require(set(r["schema_paths_passed"]) == {"fresh_migrate_and_reexecute",
            "populated_main_upgrade_and_reexecute", "empty_schema_reload"}, "Migration paths incomplete")
    require(r["catalog_equivalence_passed"] is True, "Catalog mismatch")
    u = r["upgrade"]
    require(len(u["required_versions"]) == len(set(u["required_versions"])) == 36, "Migration count mismatch")
    require(len(u["historical_versions"]) == 27 and u["preserved_subjects"] == 11, "Historical proof missing")
    require({"20261111150000", "20261112000000"} <= set(u["required_versions"]), "New migration proof missing")
    require(u["existing_versions_preserved"] and u["populated_upgrade"]
            and u["missing_after"] == [] and u["pending_after"] is False, "Upgrade ledger or rows not preserved")
    for path, expected in r["sha256"].items():
        require(sha(member(z, PurePosixPath(path).name)) == expected, "Migration schema/catalog hash mismatch")
    return r


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, hdrs, newurl):
        return None


class GitHub:
    def __init__(self, repo, token):
        self.base = "https://api.github.com/repos/" + repo
        self.headers = {"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28"}

    def api(self, path):
        request = urllib.request.Request(self.base + path, headers=self.headers, method="GET")
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)

    def download(self, url):
        require(url.startswith(self.base + "/actions/"), "Unexpected authenticated download origin")
        request = urllib.request.Request(url, headers=self.headers, method="GET")
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=60) as response:
                raw = response.read(32_000_001)
        except urllib.error.HTTPError as error:
            if error.code != 302:
                raise
            url = error.headers["Location"]
            require(urllib.parse.urlsplit(url).scheme == "https", "Non-HTTPS evidence redirect")
            # Never send the GitHub authorization header to the signed download origin.
            with urllib.request.urlopen(urllib.request.Request(url, method="GET"), timeout=120) as response:
                raw = response.read(32_000_001)
        require(len(raw) <= 32_000_000, "Evidence exceeds bounded memory")
        return raw


def execute(lock, infra, product, output):
    require(re.fullmatch(r"[0-9a-f]{40}", infra), "Full infrastructure SHA required")
    require(os.environ["GITHUB_SHA"] == infra, "Infrastructure SHA differs from authorization")
    require(os.environ["GITHUB_REF_NAME"] == lock["infrastructure_branch"], "Wrong infrastructure branch")
    require(os.environ["GITHUB_REPOSITORY"] == lock["repository"], "Wrong infrastructure repository")
    require(os.environ["RUNNER_ENVIRONMENT"] == "github-hosted", "Runner must be disposable hosted")
    require(subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() == infra,
            "Infrastructure checkout differs")
    require(os.environ["EXPECTED_PRODUCT_SHA"] == lock["product_sha"], "Product input differs")
    head = subprocess.check_output(["git", "-C", str(product), "rev-parse", "HEAD"], text=True).strip()
    require(head == lock["product_sha"], "Product checkout differs")
    require(not subprocess.check_output(["git", "-C", str(product), "status", "--porcelain",
                                        "--untracked-files=all"], text=True).strip(), "Product checkout dirty")
    for path, expected in lock["source_hashes"].items():
        require(sha((product / path).read_bytes()) == expected, "Source file mismatch: " + path)
    gh = GitHub(lock["repository"], os.environ["GH_TOKEN"])
    for ref, expected in lock["protected_refs"].items():
        require(gh.api("/git/ref/heads/" + ref)["object"]["sha"] == expected, "Protected source ref moved")
    run = gh.api("/actions/runs/" + str(lock["native_run_id"]))
    run_identity(lock, run)
    snap = gh.api("/actions/runs/" + str(lock["native_run_id"]) + "/attempts/1/jobs?per_page=100")
    matrix = jobs_identity(lock, snap)
    artifact_snapshot = gh.api("/actions/runs/" + str(lock["native_run_id"]) + "/artifacts?per_page=100")
    artifacts = artifact_identity(lock, artifact_snapshot)
    matrix_by_artifact = {r["artifact_id"]: r for r in lock["matrix"]}
    total = 0
    validations = []
    for a in artifacts:
        expected = next(x for x in lock["artifacts"] if x["id"] == a["id"])
        raw = gh.download(a["archive_download_url"])
        z = archive(raw, expected["sha256"])
        result = {"id": a["id"], "name": a["name"], "sha256": sha(raw), "reports": []}
        if a["id"] in matrix_by_artifact:
            m = matrix_by_artifact[a["id"]]
            report = member(z, "ag-rspec.json")
            require(sha(report) == m["report_sha256"], "Approved RSpec content changed")
            total += rspec(json.loads(report), m["examples"])
            key = m["identity"];installation, database, shard, count, exclusive = key.split("|")
            plan = json.loads(member(z, "ag-test-plan.json"))
            if exclusive:
                group = plan["exclusive_groups"][exclusive]
                require(group["database"] == database and shard == "0" and count == "1", "Exclusive plan mismatch")
                require(bool(group["path"]), "Exclusive path missing")
            else:
                require(bool(plan["groups"][database][int(shard)::int(count)]), "Empty native shard")
            schema = member(z, "ag-schema.rb").decode()
            require('create_table "whatsapp_retry_attempts"' in schema
                    and 'create_table "jrc_service_desk_report_exports"' in schema, "New migrations missing")
            log = gh.download(gh.base + "/actions/jobs/" + str(m["job_id"]) + "/logs").decode(errors="replace")
            result["mirror"] = apt(log)
            result["logical_identity"] = key
            result["examples"] = m["examples"]
        for name in z.namelist():
            if report_kind(name) == "rspec":
                result["reports"].append({"path": name, "examples": rspec(json.loads(z.read(name)))})
            elif report_kind(name) == "vue":
                result["reports"].append({"path": name, "vue_examples": vue(json.loads(z.read(name)))})
            elif name.endswith("/results.json") and "voice-v4-e2e" in name:
                report = json.loads(z.read(name));s = report["stats"]
                require(s["expected"] == 24 and all(s[k] == 0 for k in ("unexpected", "skipped", "flaky")),
                        "Fixture E2E not passed")
                result["reports"].append({"path": name, "fixture_examples": 24})
        if a["name"].startswith("ag-migration-admission-"):
            migration(z, lock["product_sha"]);result["migration_catalogs_verified"] = True
        if a["name"].startswith("runtime-contract-"):
            runtime_contract(json.loads(member(z, "runtime-contract.json")))
            result["runtime_contract_verified"] = True
        if a["name"].startswith("runtime-native-"):
            runtime_host(json.loads(member(z, "runtime-host.json")), lock["product_sha"])
            result["native_host_runtime_verified"] = True
        if not a["name"].startswith(("ag-migration-admission-", "runtime-contract-")):
            require(bool(result["reports"]), "No test report validated in required artifact")
        if a["name"].startswith(("ag-frontend-", "whatsapp-ui-")):
            require(any("vue_examples" in r for r in result["reports"]), "Required Vue JSON missing")
        validations.append(result)
        print("Verified artifact", a["id"], a["name"], flush=True)
    require(total == lock["expected_matrix_examples"] == 5554, "Matrix example coverage differs")
    require(len(validations) == lock["expected_artifact_count"] == len(lock["artifacts"]) and len(matrix) == 36,
            "Evidence coverage incomplete")
    # Re-read after downloads: a concurrent rerun cannot be silently accepted.
    run_identity(lock, gh.api("/actions/runs/" + str(lock["native_run_id"])))
    require(subprocess.check_output(["git", "-C", str(product), "rev-parse", "HEAD"], text=True).strip()
            == lock["product_sha"], "Product changed during verification")
    require(not subprocess.check_output(["git", "-C", str(product), "status", "--porcelain",
                                        "--untracked-files=all"], text=True).strip(), "Product changed during gate")
    report = {"passed": True, "product_sha": lock["product_sha"], "infrastructure_sha": infra,
              "lock_sha256": sha(json.dumps(lock, sort_keys=True).encode()),
              "native_run_id": lock["native_run_id"], "native_attempt": 1,
              "matrix_identities": 36, "matrix_example_executions": total, "mandatory_jobs": len(lock["mandatory_jobs"]),
              "artifacts": validations, "product_checkout_clean": True,
              "image_build_authorized": False, "image_built": False, "published": False,
              "external_homologation_claimed": False, "alpine_image_tested": False}
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--infrastructure-sha", required=True)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        execute(json.loads(args.lock.read_text(encoding="utf8")), args.infrastructure_sha,
                args.product, args.output)
    except Exception as error:
        # Signed download URLs and authentication values must never enter logs.
        print("Release evidence gate FAILED:", type(error).__name__,
              str(error) if isinstance(error, GateError) else "read/format failure; no retry", file=sys.stderr)
        sys.exit(1)
