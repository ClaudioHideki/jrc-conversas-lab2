"""Controlled publication and independent fresh-pull verification. No product changes."""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = "5640793988fbf63ac46b0db3466722fc650f0d01"
BRANCH = "ci/runtime-ghcr-56407939-20261113"
IMAGE = "ghcr.io/claudiohideki/jrc-conversas-lab2"
TAG = IMAGE + ":sha-" + PRODUCT
LOCAL = "jrc-runtime-candidate:sha-" + PRODUCT
EXECUTION_BASE = "06cadd75e9804f7aa38a8594146650d36d3ad837"
TOKEN_URL = "https://ghcr.io/token?service=ghcr.io&scope=repository%3Aclaudiohideki%2Fjrc-conversas-lab2%3Apull%2Cpush"
ACCEPT = "application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

def require(ok, message):
    if not ok:
        raise RuntimeError(message)

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def execution_identity():
    require(sys.platform == "linux" and os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted", "Hosted Linux required")
    require(os.environ.get("GITHUB_REPOSITORY") == "ClaudioHideki/jrc-conversas-lab2"
            and os.environ.get("GITHUB_REF_NAME") == BRANCH, "Publication repository/branch differs")
    require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and os.environ.get("GITHUB_RUN_ATTEMPT") == "1", "First manual run required")
    sha = os.environ.get("EXPECTED_EXECUTION_SHA", "")
    require(re.fullmatch("[0-9a-f]{40}", sha) and sha == os.environ.get("GITHUB_SHA"), "Infrastructure SHA differs")
    require(os.environ.get("EXPECTED_PRODUCT_SHA") == PRODUCT, "Wrong product authorization")
    require(subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() == sha, "Infrastructure checkout differs")
    require(subprocess.check_output(["git", "-C", str(ROOT/"product"), "rev-parse", "HEAD"], text=True).strip() == PRODUCT,
            "Product checkout differs")
    require(not subprocess.check_output(["git", "-C", str(ROOT/"product"), "status", "--porcelain",
                                        "--untracked-files=all"], text=True).strip(), "Product checkout dirty")
    return sha

def registry_token(write):
    token = os.environ["GH_TOKEN"]
    auth = base64.b64encode((os.environ["GITHUB_ACTOR"] + ":" + token).encode()).decode()
    url = TOKEN_URL if write else TOKEN_URL.replace("%2Cpush", "")
    req = urllib.request.Request(url, headers={"Authorization": "Basic " + auth,
                                              "User-Agent": "jrc-controlled-publication"})
    with urllib.request.urlopen(req, timeout=30) as response:
        value = json.load(response)
    require(isinstance(value.get("token"), str) and value["token"], "Registry token missing")
    return value["token"]

def registry_manifest(reference, token, absent_ok=False):
    req = urllib.request.Request("https://ghcr.io/v2/claudiohideki/jrc-conversas-lab2/manifests/" + reference,
                                 headers={"Authorization": "Bearer " + token, "Accept": ACCEPT})
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            raw = response.read()
            digest = response.headers.get("Docker-Content-Digest", "")
            require(digest == "sha256:" + hashlib.sha256(raw).hexdigest(), "Registry manifest digest/body differ")
            return {"digest": digest, "body": json.loads(raw), "raw": raw.decode()}
    except urllib.error.HTTPError as error:
        if absent_ok and error.code == 404:
            value = json.loads(error.read())
            require(any(e.get("code") == "MANIFEST_UNKNOWN" for e in value.get("errors", [])),
                    "Unexpected registry 404")
            return None
        raise RuntimeError("Registry HTTP " + str(error.code)) from None

def assert_absent(manifest):
    require(manifest is None, "Destination tag already exists; overwrite forbidden")

def validate_build(receipt):
    require(receipt.get("product_sha") == PRODUCT and receipt.get("execution_sha") == os.environ["EXPECTED_EXECUTION_SHA"],
            "Build receipt identity differs")
    require(receipt.get("build_passed") is True and receipt.get("smoke_passed") is True
            and receipt.get("runtime_heap_environment_unchanged") is True
            and not receipt.get("failure") and not receipt.get("owned_stop_errors"), "Build/smoke incomplete")
    require(receipt.get("image_tag") == LOCAL and re.fullmatch("sha256:[0-9a-f]{64}", receipt.get("image_id", "")),
            "Tested image identity missing")
    require(receipt.get("frontend_heap", {}).get("passed") is True
            and receipt["frontend_heap"]["heap_mib"] == 6144, "Vite heap receipt missing")
    require(receipt.get("http", {}).get("login_status") == 200
            and receipt["http"]["verified_assets"] == 3 and receipt["http"]["same_image_id"]
            and receipt["http"]["host_ports_published"] is False, "HTTP/assets identity incomplete")
    return receipt["image_id"]

def validate_manifest(manifest, image_id):
    require(re.fullmatch("sha256:[0-9a-f]{64}", manifest.get("digest", "")), "Remote digest invalid")
    body = manifest["body"]
    require(body.get("schemaVersion") == 2 and body.get("config", {}).get("digest") == image_id,
            "Published config differs from tested image")
    require(body.get("mediaType") in ACCEPT.split(", ") and body.get("layers"), "Single-platform manifest required")
    return manifest["digest"]

def validate_image(info, image_id):
    require(info["Id"] == image_id and info["Os"] == "linux" and info["Architecture"] == "amd64",
            "Image ID/platform differs")
    require(info["Config"]["Labels"]["org.opencontainers.image.revision"] == PRODUCT, "Image revision differs")
    return info

def login():
    result = subprocess.run(["docker", "login", "ghcr.io", "-u", os.environ["GITHUB_ACTOR"], "--password-stdin"],
                            input=os.environ["GH_TOKEN"] + "\n", text=True, capture_output=True, timeout=45)
    require(result.returncode == 0, "GHCR login failed; credentials omitted")
    print("GHCR login successful; credentials omitted")

def directory():
    return Path(os.environ["RUNNER_TEMP"]) / ("jrc-runtime-" + os.environ["GITHUB_RUN_ID"] + "-1")

def hashes():
    out = directory()
    values = [{"path": p.name, "bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
              for p in out.iterdir() if p.is_file() and p.name not in {"synthetic.env", "hashes.json"}]
    (out/"hashes.json").write_text(json.dumps(values, indent=2) + "\n")

def preflight():
    execution_identity()
    assert_absent(registry_manifest("sha-" + PRODUCT, registry_token(True), absent_ok=True))
    print(json.dumps({"preflight_passed": True, "product_sha": PRODUCT, "destination": TAG,
                      "existing_tag_overwritten": False}))

def publish():
    sha = execution_identity()
    out = directory()
    receipt = json.loads((out/"result.json").read_text())
    image_id = validate_build(receipt)
    require(receipt["execution_sha"] == sha and receipt["run_id"] == os.environ["GITHUB_RUN_ID"], "Build run differs")
    metadata = json.loads((out/"metadata.json").read_text())
    require(metadata["containerimage.config.digest"] == image_id, "Build metadata config differs")
    guard = module("publication_guard", ROOT/".github/runtime_build/guard.py")
    # The original smoke attempt has ended; reuse its exact resource limits for tag/push.
    attempt = object.__new__(guard.Attempt)
    attempt.name = "jrc-runtime-" + os.environ["GITHUB_RUN_ID"] + "-1"
    attempt.output, attempt.result, attempt.start, attempt.limits = out, receipt, time.monotonic(), guard.limits()
    attempt.sample()
    before = json.loads(attempt.command(["docker", "image", "inspect", image_id], "publication-image-inspect"))[0]
    validate_image(before, image_id)
    guard.runtime_environment(before["Config"].get("Env", []))
    assert_absent(registry_manifest("sha-" + PRODUCT, registry_token(True), absent_ok=True))
    login()
    attempt.command(["docker", "tag", image_id, TAG], "tag-only-tested-image")
    attempt.command(["docker", "push", TAG], "push-only-approved-sha-tag", 900)
    remote = registry_manifest("sha-" + PRODUCT, registry_token(True))
    digest = validate_manifest(remote, image_id)
    (out/"registry-manifest.json").write_text(remote["raw"])
    result = {"published": True, "product_sha": PRODUCT, "execution_sha": sha,
              "execution_base": EXECUTION_BASE, "run_id": os.environ["GITHUB_RUN_ID"],
              "image": IMAGE, "tag": TAG, "digest": digest, "image_id": image_id,
              "tested_local_image_id": image_id, "build_manifest_digest": receipt["manifest_digest"],
              "same_tested_image": True, "no_rebuild_after_smoke": True,
              "latest_modified": False, "existing_tag_overwritten": False,
              "fresh_pull_verification_pending": True,
              "publication_resources": {k: receipt[k] for k in ["disk_min", "ram_min", "final"]}}
    (out/"publication.json").write_text(json.dumps(result, indent=2) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.write("digest=" + digest + "\nimage_id=" + image_id + "\n")
    hashes()
    print(json.dumps(result))

def build_artifact():
    gate = module("publication_gate", ROOT/".github/release/gate.py")
    gh = gate.GitHub("ClaudioHideki/jrc-conversas-lab2", os.environ["GH_TOKEN"])
    rid = os.environ["GITHUB_RUN_ID"]
    run = gh.api("/actions/runs/" + rid)
    require(run["head_sha"] == os.environ["EXPECTED_EXECUTION_SHA"] and run["run_attempt"] == 1
            and run["status"] == "in_progress" and run["conclusion"] is None, "Wrong verification run")
    jobs = gh.api("/actions/runs/" + rid + "/attempts/1/jobs?per_page=100")
    require(jobs["total_count"] == len(jobs["jobs"]) == 3, "Unexpected verification jobs")
    for name in ["evidence-gate", "image-build"]:
        rows = [j for j in jobs["jobs"] if j["name"] == name]
        require(len(rows) == 1 and rows[0]["status"] == "completed" and rows[0]["conclusion"] == "success"
                and rows[0]["head_sha"] == os.environ["EXPECTED_EXECUTION_SHA"] and rows[0]["run_attempt"] == 1,
                "Source gate/build not approved")
    arts = gh.api("/actions/runs/" + rid + "/artifacts?per_page=100")
    wanted = "runtime-image-attempt-" + os.environ["EXPECTED_EXECUTION_SHA"] + "-" + rid
    matches = [a for a in arts["artifacts"] if a["name"] == wanted and not a["expired"]]
    require(len(matches) == 1, "Build publication artifact missing/duplicated")
    a = matches[0]
    z = gate.archive(gh.download(a["archive_download_url"]), a["digest"][7:])
    values = json.loads(gate.member(z, "hashes.json"))
    for row in values:
        b = gate.member(z, row["path"])
        require(len(b) == row["bytes"] and hashlib.sha256(b).hexdigest() == row["sha256"],
                "Build artifact member hash differs")
    receipt = json.loads(gate.member(z, "result.json"))
    image_id = validate_build(receipt)
    p = json.loads(gate.member(z, "publication.json"))
    require(p["published"] and p["product_sha"] == PRODUCT
            and p["execution_sha"] == os.environ["EXPECTED_EXECUTION_SHA"] and p["run_id"] == rid
            and p["image"] == IMAGE and p["tag"] == TAG and p["image_id"] == image_id
            and p["same_tested_image"] and p["no_rebuild_after_smoke"]
            and not p["latest_modified"] and not p["existing_tag_overwritten"], "Publication receipt invalid")
    require(p["digest"] == os.environ["EXPECTED_PUBLISHED_DIGEST"]
            and image_id == os.environ["EXPECTED_PUBLISHED_IMAGE_ID"], "Workflow output/receipt differs")
    return p, {"id": a["id"], "digest": a["digest"], "verified_files": len(values)}

# PublishedAttempt's smoke body below is copied byte-for-byte from the approved guard;
# test_publish.py compares its AST with the original network-through-smoke section.
def verify():
    execution_identity()
    receipt, artifact = build_artifact()
    digest, image_id = receipt["digest"], receipt["image_id"]
    remote = registry_manifest(digest, registry_token(False))
    require(validate_manifest(remote, image_id) == digest, "Remote immutable manifest differs")
    current = registry_manifest("sha-" + PRODUCT, registry_token(False))
    require(current["digest"] == digest, "Tag moved after publication")
    login()
    guard = module("published_pull_guard", ROOT/".github/runtime_build/guard.py")
    guard.require = require
    attempt = PublishedAttempt(guard, receipt, artifact)
    try:
        attempt.execute()
    except BaseException as error:
        attempt.result["failure"] = {"type": type(error).__name__,
                                    "message": str(error) if isinstance(error, RuntimeError) else "verification command failed"}
    finally:
        attempt.finish()
    require(attempt.result.get("pull_passed") and attempt.result.get("smoke_passed")
            and not attempt.result.get("failure") and not attempt.result.get("owned_stop_errors"),
            "Fresh pull verification failed")
    attempt.result["published_verification_passed"] = True
    (attempt.output/"published-verification.json").write_text(json.dumps(attempt.result, indent=2) + "\n")
    hashes()
    print(json.dumps({"published_verification_passed": True, "reference": IMAGE + "@" + digest,
                      "product_sha": PRODUCT, "execution_sha": os.environ["EXPECTED_EXECUTION_SHA"],
                      "image_id": image_id}))

class PublishedAttempt:
    def __new__(cls, guard, receipt, artifact):
        # Inherit the original owned-container methods; no rebuilding path is invoked.
        dynamic = type("PublishedAttempt", (cls, guard.Attempt), {})
        self = object.__new__(dynamic)
        guard.Attempt.__init__(self)
        self.guard, self.receipt = guard, receipt
        self.result.update(phase="fresh_runner_pull_verification", authorized_image_attempt=None,
                           build_started=False, build_passed=False, published=True,
                           manifest_digest=receipt["digest"], image_id=receipt["image_id"],
                           publication_artifact=artifact, image_tag=IMAGE + "@" + receipt["digest"])
        return self

    def __init__(self, guard, receipt, artifact):
        pass

    def execute(self):
        self.sample(starting=True)
        self.limits.no_other_vite_build()
        self.no_foreign_vite()
        guard, receipt = self.guard, self.receipt
        # This runner must not already have the tested image in its Docker store.
        old = subprocess.run(["docker", "image", "inspect", receipt["image_id"]],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        require(old.returncode != 0, "Verification runner already contains candidate image")
        image = IMAGE + "@" + receipt["digest"]
        self.command(["docker", "pull", "--platform", "linux/amd64", image], "fresh-pull-by-digest", 600)
        info = json.loads(self.command(["docker", "image", "inspect", image], "fresh-image-inspect"))[0]
        validate_image(info, receipt["image_id"])
        require(image in info.get("RepoDigests", []), "Pulled RepoDigest differs")
        guard.runtime_environment(info["Config"].get("Env", []))
        self.result["runtime_heap_environment_unchanged"] = True
        self.result["pull_passed"] = True
        PG, REDIS, PRODUCT, ROOT = guard.PG, guard.REDIS, guard.PRODUCT, guard.ROOT
        schema_command, internal_origin, http_open = guard.schema_command, guard.internal_origin, guard.http_open
        uuid = __import__("uuid")
        self.command(["docker", "network", "create", "--internal", "--label", "jrc.runtime.run=" + self.name, self.name], "create-internal-network")
        postgres = self.name + "-pg"
        redis = self.name + "-redis"
        self.command(["docker", "run", "-d", "--name", postgres, "--label", "jrc.runtime.run=" + self.name,
                      "--network", self.name, "-e", "POSTGRES_USER=postgres", "-e", "POSTGRES_PASSWORD=synthetic-runtime-only",
                      "-e", "POSTGRES_DB=jrc_runtime_image_test", PG], "start-postgres")
        self.own(postgres)
        self.run_container(redis, REDIS, ["redis-server", "--save", "", "--appendonly", "no"])
        def pgready():
            return subprocess.run(["docker", "exec", postgres, "pg_isready", "-U", "postgres", "-d", "jrc_runtime_image_test"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode == 0
        self.wait(pgready, "postgres")
        envfile = self.output / "synthetic.env"
        nonce = uuid.uuid4().hex
        env = {"RAILS_ENV": "production", "NODE_ENV": "production", "RAILS_LOG_TO_STDOUT": "true",
               "RAILS_SERVE_STATIC_FILES": "true", "SECRET_KEY_BASE": "synthetic-runtime-only-" + "1"*64,
               "POSTGRES_HOST": postgres, "POSTGRES_PORT": "5432", "POSTGRES_USERNAME": "postgres",
               "POSTGRES_PASSWORD": "synthetic-runtime-only", "POSTGRES_DATABASE": "jrc_runtime_image_test",
               "REDIS_URL": "redis://" + redis + ":6379/15", "FRONTEND_URL": "http://127.0.0.1:3000",
               "INSTALLATION_ENV": "docker", "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY": "1"*32,
               "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY": "2"*32, "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT": "3"*32,
               "RUNTIME_SMOKE_NONCE": nonce, "RUNTIME_SMOKE_QUEUE": "runtime_probe_" + nonce,
               "RUNTIME_PRODUCT_SHA": PRODUCT, "RUNTIME_SMOKE_OUTPUT": "/evidence"}
        envfile.write_text("".join(k + "=" + v + "\n" for k, v in env.items()))
        envfile.chmod(0o600)
        fixtures = ROOT / ".github/runtime_build"
        mount = ["type=bind,src=" + str(fixtures) + ",dst=/smoke,readonly",
                 "type=bind,src=" + str(self.output) + ",dst=/evidence"]
        base = ["docker", "create", "--name", self.name + "-schema", "--label", "jrc.runtime.run=" + self.name,
                "--network", self.name, "--env-file", str(envfile)]
        self.command(base + [image] + schema_command(), "create-schema-and-migrate")
        self.own(self.name + "-schema")
        self.command(["docker", "start", "-a", self.name + "-schema"], "schema-load-and-migrate", 600)
        def probe(mode, script='probe.rb'):
            name = self.name + "-probe-" + mode
            args = ["docker", "create", "--name", name, "--label", "jrc.runtime.run=" + self.name,
                    "--network", self.name, "--env-file", str(envfile)]
            for m in mount:
                args += ["--mount", m]
            self.command(args + [image, "bundle", "exec", "rails", "runner", "/smoke/" + script, mode], "create-probe-" + mode)
            self.own(name)
            self.command(["docker", "start", "-a", name], "probe-" + mode, 300)
        probe("native")
        probe("scout", "extra.rb")
        probe("enqueue")
        worker = self.name + "-worker"
        self.run_container(worker, image, ["bundle", "exec", "sidekiq", "-r", "/smoke/worker.rb",
                                           "-q", env["RUNTIME_SMOKE_QUEUE"], "-c", "1"], envfile, mount)
        probe("verify_worker")
        probe("worker_pid_one", "extra.rb")
        web = self.name + "-web"
        self.run_container(web, image, ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"],
                           envfile, mount)
        info = self.own(web)
        origin = internal_origin(info, self.name)
        def webready():
            try:
                with http_open(origin + "/app/login", timeout=3) as response:
                    return response.status == 200
            except (OSError, urllib.error.HTTPError):
                return False
        self.wait(webready, "Rails HTTP", 90)
        with http_open(origin + "/app/login", timeout=10) as response:
            html = response.read()
        require(b"<html" in html.lower() and b"/vite/" in html, "Actual Rails login/assets missing")
        assets = json.loads((self.output / "assets.json").read_text())
        for item in assets["required_http"]:
            self.sample()
            with http_open(origin + "/vite/" + item["file"], timeout=15) as response:
                body = response.read()
                require(response.status == 200 and hashlib.sha256(body).hexdigest() == item["sha256"], "Served asset differs")
        self.result["http"] = {"login_status": 200, "verified_assets": len(assets["required_http"]), "same_image_id": info["Image"] == self.result["image_id"],
                               "transport": "owned_internal_ipv4", "origin": origin, "network": self.name,
                               "host_ports_published": False}
        require(self.result["http"]["same_image_id"] and self.inspect(worker)["Image"] == self.result["image_id"], "Rails/Sidekiq image mismatch")
        self.result["smoke_passed"] = True

def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--preflight", action="store_true")
    group.add_argument("--publish", action="store_true")
    group.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.preflight:
        preflight()
    elif args.publish:
        publish()
    else:
        verify()

if __name__ == "__main__":
    main()
