"""Single authorized image attempt; resources and owned processes only."""
import hashlib
import ipaddress
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import urllib.request
import urllib.error
import uuid

PRODUCT = "5640793988fbf63ac46b0db3466722fc650f0d01"
APPROVED = "3d1e41db6cd2a085cc7f6b988aa017bbed4d3a46"
BRANCH = "ci/runtime-build-http-fix-20261113"
REPO = "ClaudioHideki/jrc-conversas-lab2"
BUILDKIT = "mirror.gcr.io/moby/buildkit:v0.33.1@sha256:98cc6a3fc46220d00f8224ae483f3274fc874e9be8d7dd1e2e2c5481209228b5"
PG = "pgvector/pgvector:pg16@sha256:7b822b0aac60967beb1ea5e576b8602c94c300a157d187f385ae3e0da199b90a"
REDIS = "redis:7.4.0-alpine@sha256:c35af3bbcef51a62c8bae5a9a563c6f1b60d7ebaea4cb5a3ccbcc157580ae098"
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "product"


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def identity(env):
    require(sys.platform == "linux", "Linux required")
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("RUNNER_ENVIRONMENT") == "github-hosted", "Hosted GitHub required")
    require(env.get("GITHUB_REPOSITORY") == REPO and env.get("GITHUB_REF_NAME") == BRANCH, "Wrong repository or branch")
    require(env.get("GITHUB_EVENT_NAME") == "workflow_dispatch" and env.get("GITHUB_RUN_ATTEMPT") == "1", "First manual attempt only")
    infra = env.get("EXPECTED_EXECUTION_SHA", "")
    require(re.fullmatch("[0-9a-f]{40}", infra) and env.get("GITHUB_SHA") == infra, "Execution SHA differs")
    require(env.get("EXPECTED_PRODUCT_SHA") == PRODUCT and env.get("AUTHORIZED_BUILD_SHA") == PRODUCT, "Product not authorized")
    require(env.get("EXPECTED_APPROVED_SHA") == APPROVED, "Approved gate infrastructure differs")
    run = env.get("GITHUB_RUN_ID", "")
    require(run.isdecimal(), "Run identity required")
    return "jrc-runtime-" + run + "-1"


def limits():
    path = SOURCE / "script/jrc_ag_guarded_frontend_build.py"
    require(hashlib.sha256(path.read_bytes()).hexdigest() == "18fa3a0e7af674e78e59cda0815805f65c88072dbfb80e6a327c87cf5f84e2c4", "Original resource guard changed")
    spec = importlib.util.spec_from_file_location("preserved_resource_limits", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


START_EFFECTIVE_RAM = 8 * 1024 ** 3


def effective_memory(host_available, capacities):
    require(type(host_available) is int and host_available >= 0, "Invalid physical memory sample")
    free = host_available
    for limit, current in capacities:
        require(type(limit) is int and type(current) is int and limit > 0 and current >= 0,
                "Invalid cgroup memory sample")
        free = min(free, max(0, limit - current))
    return free


def cgroup_capacities():
    root = Path("/sys/fs/cgroup")
    unified = [line.split(":", 2)[2] for line in Path("/proc/self/cgroup").read_text().splitlines()
               if line.startswith("0::")]
    require(len(unified) == 1, "Unified cgroup hierarchy required on Ubuntu 24.04")
    relative = Path(unified[0].lstrip("/"))
    require(".." not in relative.parts, "Unexpected cgroup namespace")
    current = root / relative
    require(current.is_dir(), "Process cgroup directory unavailable")
    values = []
    while True:
        limit_path = current / "memory.max"
        if limit_path.is_file():
            raw = limit_path.read_text().strip()
            if raw != "max":
                values.append((int(raw), int((current / "memory.current").read_text().strip())))
        if current == root:
            break
        current = current.parent
    return values


def effective_sample(limits_module):
    sample = limits_module.sample()
    sample["physical_ram_available"] = sample["ram_available"]
    sample["cgroup_capacities"] = cgroup_capacities()
    sample["ram_available"] = effective_memory(sample["ram_available"], sample["cgroup_capacities"])
    return sample


def starting_memory_reason(available, starting):
    return "effective_ram_start_below_8_GiB" if starting and available < START_EFFECTIVE_RAM else None


def frontend_receipt(log):
    events = []
    marker = '{"component":"jrc_vite_heap"'
    for line in log.splitlines():
        if marker in line:
            events.append(json.loads(line[line.index(marker):]))
    starts = [e for e in events if "initial" in e]
    ends = [e for e in events if "passed" in e]
    require(len(starts) == len(ends) == 1, "Actual guarded Vite execution receipt missing or duplicated")
    require(starts[0]["heapMiB"] == 6144 and starts[0]["initial"]["availableMemory"] >= START_EFFECTIVE_RAM
            and starts[0]["initial"]["diskFree"] >= 3*1024**3, "Actual Vite start budget differs")
    require(ends[0]["passed"] is True and ends[0]["code"] == 0 and ends[0]["reason"] is None
            and ends[0]["minimumMemory"] > 750*1024**2 and ends[0]["minimumDisk"] > 750000000,
            "Actual Vite resource/exit receipt failed")
    return {"passed": True, "events": events, "heap_mib": 6144, "build_only": True}


def runtime_environment(env):
    require(not any(item.startswith(("JRC_VITE_BUILD_HEAP_MIB=", "VITE_RUBY_VITE_BIN_PATH="))
                    or (item.startswith("NODE_OPTIONS=") and "6144" in item) for item in env),
            "Frontend build heap leaked into normal runtime environment")


def internal_origin(info, network):
    require(info.get("Config", {}).get("Labels", {}).get("jrc.runtime.run") == network,
            "Foreign web container refused")
    require(info.get("State", {}).get("Running") is True, "Owned web container is not running")
    networks = info.get("NetworkSettings", {}).get("Networks", {})
    require(set(networks) == {network}, "Web must use only the owned internal network")
    try:
        address = ipaddress.ip_address(networks[network].get("IPAddress", ""))
    except ValueError:
        raise RuntimeError("Owned web private IPv4 address missing") from None
    require(isinstance(address, ipaddress.IPv4Address) and address.is_private
            and not address.is_loopback and not address.is_multicast and not address.is_unspecified,
            "Owned web private IPv4 required")
    return "http://" + str(address) + ":3000"


def http_open(url, timeout):
    # The target is the owned container IP; inherited host proxies must not reroute it.
    return urllib.request.build_opener(urllib.request.ProxyHandler({})).open(url, timeout=timeout)


def build_command(builder, output):
    return ["docker", "buildx", "build", "--builder", builder, "--load", "--platform", "linux/amd64",
            "--file", "docker/Dockerfile", "--build-arg", "GIT_SHA=" + PRODUCT,
            "--tag", "jrc-runtime-candidate:sha-" + PRODUCT, "--provenance=false",
            "--label", "org.opencontainers.image.revision=" + PRODUCT,
            "--metadata-file", str(output / "metadata.json"), "--progress=plain", "."]


def schema_command():
    return ["bundle", "exec", "rails", "db:schema:load", "db:migrate"]


class Attempt:
    def __init__(self):
        self.name = identity(os.environ)
        self.output = Path(os.environ["RUNNER_TEMP"]) / self.name
        self.output.mkdir()
        self.limits = limits()
        self.start = time.monotonic()
        self.containers = {}
        self.builder_id = None
        self.builder_created = False
        self.builder_stopped = False
        self.result = {"authorized_image_attempt": 4, "previous_image_run": 43355070847,
                       "product_sha": PRODUCT, "approved_gate_sha": APPROVED,
                       "execution_sha": os.environ["GITHUB_SHA"], "run_id": os.environ["GITHUB_RUN_ID"],
                       "build_started": False, "build_passed": False, "smoke_passed": False,
                       "published": False, "phases": [], "initial": None, "disk_min": None, "ram_min": None}

    def sample(self, starting=False):
        s = effective_sample(self.limits)
        if self.result["initial"] is None:
            self.result["initial"] = s
            self.result["disk_min"] = s["disk_free"]
            self.result["ram_min"] = s["ram_available"]
        self.result["disk_min"] = min(self.result["disk_min"], s["disk_free"])
        self.result["ram_min"] = min(self.result["ram_min"], s["ram_available"])
        self.result["final"] = s
        reason = starting_memory_reason(s["ram_available"], starting) or self.limits.resource_reason(s["disk_free"], s["ram_available"], starting=starting)
        require(not reason, reason or "resources")
        return s

    def command(self, args, label, timeout=120, cwd=None):
        self.sample()
        phase = {"name": label, "started_seconds": round(time.monotonic() - self.start, 3)}
        self.result["phases"].append(phase)
        logpath = self.output / (label + ".log")
        process = None
        try:
            with logpath.open("x") as log:
                process = subprocess.Popen(args, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                started = time.monotonic()
                while process.poll() is None:
                    self.sample()
                    require(time.monotonic() - started < timeout, "Owned phase timeout: " + label)
                    time.sleep(0.5)
                phase["exit_code"] = process.wait()
            self.sample()
            require(phase["exit_code"] == 0, "Owned phase failed: " + label)
            return logpath.read_text()
        finally:
            if process is not None and process.poll() is None:
                require(os.getpgid(process.pid) == process.pid, "Owned process identity changed")
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
                phase["stopped_owned_process"] = True
            phase["seconds"] = round(time.monotonic() - self.start - phase["started_seconds"], 3)

    def no_foreign_vite(self):
        for entry in Path("/proc").iterdir():
            if not entry.name.isdecimal():
                continue
            try:
                args = (entry / "cmdline").read_bytes().split(bytes([0]))
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
            is_vite = any(Path(os.fsdecode(a)).name in {"vite", "vite.js", "vite.mjs"} for a in args if a)
            require(not (is_vite and b"build" in args), "Other Vite build active; no foreign process stopped")

    def inspect(self, name):
        self.sample()
        return json.loads(subprocess.check_output(["docker", "inspect", name], text=True, timeout=20))[0]

    def own(self, name):
        info = self.inspect(name)
        require(info["Config"].get("Labels", {}).get("jrc.runtime.run") == self.name, "Foreign container refused")
        require(not info["HostConfig"].get("Privileged"), "Privileged container refused")
        self.containers[name] = info["Id"]
        return info

    def run_container(self, name, image, command, envfile=None, mounts=None, ports=None):
        args = ["docker", "run", "-d", "--name", name, "--label", "jrc.runtime.run=" + self.name,
                "--network", self.name]
        if envfile:
            args += ["--env-file", str(envfile)]
        for mount in mounts or []:
            args += ["--mount", mount]
        for port in ports or []:
            args += ["-p", port]
        self.command(args + [image] + command, "start-" + name)
        return self.own(name)

    def wait(self, check, label, seconds=90):
        start = time.monotonic()
        while time.monotonic() - start < seconds:
            self.sample()
            if check():
                return
            time.sleep(0.5)
        raise RuntimeError("Readiness timeout: " + label)

    def execute(self):
        require(subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() == os.environ["EXPECTED_EXECUTION_SHA"], "Execution checkout differs")
        require(subprocess.check_output(["git", "-C", str(SOURCE), "rev-parse", "HEAD"], text=True).strip() == PRODUCT, "Product checkout differs")
        require(not subprocess.check_output(["git", "-C", str(SOURCE), "status", "--porcelain", "--untracked-files=all"], text=True).strip(), "Product dirty")
        self.sample(starting=True)
        self.limits.no_other_vite_build()
        self.no_foreign_vite()
        existing = subprocess.run(["docker", "inspect", "buildx_buildkit_" + self.name + "0"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        require(existing.returncode != 0, "Builder container already exists")
        active = subprocess.check_output(["docker", "ps", "--format", "{{.Names}}"], text=True).splitlines()
        require(not any(n.startswith("buildx_buildkit_") for n in active), "Other builder active")
        self.command(["docker", "buildx", "create", "--name", self.name, "--driver", "docker-container",
                      "--driver-opt", "image=" + BUILDKIT], "create-builder")
        self.builder_created = True
        self.command(["docker", "buildx", "inspect", "--builder", self.name, "--bootstrap"], "bootstrap-builder", 300)
        builder = self.inspect("buildx_buildkit_" + self.name + "0")
        require(builder["Config"]["Image"] == BUILDKIT and builder["State"]["Running"], "Pinned owned builder required")
        require(builder["HostConfig"].get("Memory", 0) == 0, "Unexpected builder memory cap; separate validation required")
        self.builder_id = builder["Id"]
        self.sample(starting=True)
        self.limits.no_other_vite_build()
        self.no_foreign_vite()
        marker = self.output / "single-build-attempt.json"
        with marker.open("x") as stream:
            json.dump({"product_sha": PRODUCT, "execution_sha": os.environ["GITHUB_SHA"], "builder_id": self.builder_id}, stream)
        self.result["build_started"] = True
        build_log = self.command(build_command(self.name, self.output), "image-build", 3600, SOURCE)
        self.result["frontend_heap"] = frontend_receipt(build_log)
        (self.output / "frontend-heap-receipt.json").write_text(json.dumps(self.result["frontend_heap"], indent=2) + "\n")
        image = "jrc-runtime-candidate:sha-" + PRODUCT
        info = json.loads(self.command(["docker", "image", "inspect", image], "image-inspect"))[0]
        metadata = json.loads((self.output / "metadata.json").read_text())
        require(info["Os"] == "linux" and info["Architecture"] == "amd64", "Wrong image platform")
        runtime_environment(info["Config"].get("Env", []))
        self.result["runtime_heap_environment_unchanged"] = True
        require(info["Config"]["Labels"]["org.opencontainers.image.revision"] == PRODUCT, "Wrong image revision")
        digest = metadata.get("containerimage.digest", "")
        require(re.fullmatch("sha256:[0-9a-f]{64}", digest), "Image manifest digest missing")
        require(info["Id"] == metadata["containerimage.config.digest"], "Loaded image config differs")
        self.result.update(build_passed=True, image_id=info["Id"], manifest_digest=digest,
                           image_tag=image, image_size=info["Size"], repo_digests=info.get("RepoDigests", []))
        self.command(["docker", "stop", "--time", "10", self.builder_id], "stop-owned-builder", 30)
        self.builder_stopped = True
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

    def finish(self):
        try:
            owned = subprocess.check_output(["docker", "ps", "-a", "--filter", "label=jrc.runtime.run=" + self.name, "--format", "{{.Names}}"], text=True, timeout=10)
            for name in owned.splitlines():
                current = json.loads(subprocess.check_output(["docker", "inspect", name], text=True, timeout=10))[0]
                require(current["Config"]["Labels"].get("jrc.runtime.run") == self.name, "Foreign container discovered")
                self.containers.setdefault(name, current["Id"])
            for name, expected in self.containers.items():
                current = json.loads(subprocess.check_output(["docker", "inspect", name], text=True, timeout=10))[0]
                require(current["Id"] == expected and current["Config"]["Labels"].get("jrc.runtime.run") == self.name, "Container identity changed")
                with (self.output / (name + ".log")).open("w") as log:
                    subprocess.run(["docker", "logs", name], stdout=log, stderr=subprocess.STDOUT, timeout=10, check=True)
                if current["State"]["Running"]:
                    subprocess.run(["docker", "stop", "--time", "10", name], check=True, stdout=subprocess.DEVNULL, timeout=20)
        except Exception as error:
            self.result.setdefault("owned_stop_errors", []).append(type(error).__name__)
        if self.builder_created and not self.builder_stopped:
            try:
                current = json.loads(subprocess.check_output(["docker", "inspect", "buildx_buildkit_" + self.name + "0"], text=True, timeout=10))[0]
                require((not self.builder_id or current["Id"] == self.builder_id) and current["Config"]["Image"] == BUILDKIT and current["Name"] == "/buildx_buildkit_" + self.name + "0", "Builder identity changed")
                with (self.output / "owned-builder.log").open("w") as log:
                    subprocess.run(["docker", "logs", current["Id"]], stdout=log, stderr=subprocess.STDOUT, timeout=10, check=True)
                subprocess.run(["docker", "stop", "--time", "10", current["Id"]], check=True, stdout=subprocess.DEVNULL, timeout=20)
            except Exception as error:
                self.result.setdefault("owned_stop_errors", []).append(type(error).__name__)
        self.result["final"] = effective_sample(self.limits)
        self.result["seconds"] = round(time.monotonic() - self.start, 3)
        (self.output / "result.json").write_text(json.dumps(self.result, indent=2) + "\n")
        files = [{"path": p.name, "bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                 for p in self.output.iterdir() if p.is_file() and p.name != "synthetic.env"]
        (self.output / "hashes.json").write_text(json.dumps(files, indent=2) + "\n")


def main():
    attempt = Attempt()
    try:
        attempt.execute()
    except BaseException as error:
        attempt.result["failure"] = {"type": type(error).__name__, "message": str(error) if isinstance(error, RuntimeError) else "command or format failure"}
    finally:
        attempt.finish()
    print(json.dumps(attempt.result))
    return 0 if attempt.result["build_passed"] and attempt.result["smoke_passed"] and not attempt.result.get("owned_stop_errors") else 1


if __name__ == "__main__":
    require(sys.argv[1:] == ["--execute"], "Explicit single execution required")
    sys.exit(main())
