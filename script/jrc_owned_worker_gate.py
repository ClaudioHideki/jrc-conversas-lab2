"""Explicit local-only real queue gate. No build, cleanup, migration or deployment.

Creates a new empty PostgreSQL database from schema plus migration metadata only.
Requires Redis index15 to be completely empty; never flushes or deletes its data.
All generated records and artifacts are preserved for inspection after the run.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import time
import uuid

root = Path(__file__).resolve().parent.parent
assert Path.cwd().resolve() == root
assert shutil.disk_usage(root).free > 3_000_000_000
assert subprocess.check_output(["git", "branch", "--show-current"]).decode().strip() == "codex/relacionamento-v2-20261101"
source = json.loads((root / ".codex/d9-notifications-20261104/snapshot.json").read_text())["root"]
assert source.startswith("/consolidation-approval-notifications-tests-20261104-")
container = "jrc-rel-v2-run-20261101"
postgres = "jrc-rel-v2-pg-20261101"
redis = "jrc-rel-v2-redis-20261101"
nonce = uuid.uuid4().hex[:12]
database = "jrc_g_worker_20261106_" + nonce
queue = "jrc_g_worker_" + nonce
directory = "/tmp/" + queue
assert re.fullmatch(r"jrc_g_worker_20261106_[0-9a-f]{12}", database)
artifact = root / ".codex/g-worker-20261106" / nonce
artifact.mkdir(parents=True, exist_ok=False)
result = {"nonce": nonce, "database": database, "redis_index": 15, "queue": queue,
          "source": source, "head": subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip(),
          "free_start": shutil.disk_usage(root).free, "minimum_free": shutil.disk_usage(root).free,
          "original_containers_changed": False, "application_build": False, "cleanup": False}


def command(args, data=None):
    assert shutil.disk_usage(root).free > 2_000_000_000
    completed = subprocess.run(args, input=data, capture_output=True)
    if completed.returncode:
        (artifact / "command-failure.txt").write_bytes(completed.stderr[-12000:])
        raise RuntimeError("Owned command failed; retained scoped diagnostic in artifact directory")
    return completed.stdout


try:
    result["phase"] = "syntax_and_empty_scope"
    files = ["spec/integration/jrc_relationship/owned_worker_boot.rb", "spec/integration/jrc_relationship/owned_worker_gate.rb",
             "spec/integration/jrc_relationship/owned_worker_fixtures.rb"]
    result["code_sha256"] = {}
    for relative in files:
        raw = (root / relative).read_bytes()
        remote = source + "/" + relative
        digest = hashlib.sha256(raw).hexdigest()
        remote_digest = command(["docker", "exec", container, "ruby", "-rdigest", "-e",
                                 "puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest", remote]).decode().strip()
        assert digest == remote_digest, "Sync the owned source snapshot before running the gate"
        result["code_sha256"][relative] = digest
        command(["docker", "exec", container, "ruby", "-c", remote])
    assert command(["docker", "exec", redis, "redis-cli", "-n", "15", "DBSIZE"]).decode().strip() == "0", "Redis15 is not empty; no cleanup authorized"
    exists = command(["docker", "exec", postgres, "psql", "-U", "postgres", "-d", "postgres", "-At", "-c",
                      "SELECT count(*) FROM pg_database WHERE datname='" + database + "'"]).decode().strip()
    assert exists == "0", "Never replace an existing test database"
    result["phase"] = "new_schema_only_database"
    schema = command(["docker", "exec", postgres, "pg_dump", "-U", "postgres", "--schema-only", "--no-owner", "--no-privileges",
                      "--dbname=jrc_rel_v2_candidate_test"])
    metadata = command(["docker", "exec", postgres, "pg_dump", "-U", "postgres", "--data-only", "--no-owner", "--no-privileges",
                        "--table=schema_migrations", "--table=ar_internal_metadata", "--dbname=jrc_rel_v2_candidate_test"])
    result["schema_sha256"] = hashlib.sha256(schema).hexdigest()
    result["schema_bytes"] = len(schema)
    result["migration_metadata_bytes"] = len(metadata)
    command(["docker", "exec", postgres, "createdb", "-U", "postgres", "--template=template0", database])
    command(["docker", "exec", "-i", postgres, "psql", "-X", "-U", "postgres", "--set=ON_ERROR_STOP=1", "--dbname=" + database], schema + b"\n" + metadata)
    empty = command(["docker", "exec", postgres, "psql", "-U", "postgres", "-d", database, "-At", "-c",
                     "SELECT (SELECT count(*) FROM accounts),(SELECT count(*) FROM users),(SELECT count(*) FROM jrc_relationship_assignments);"]).decode().strip()
    assert empty == "0|0|0", "No business data may be cloned"
    result["business_data_copied"] = False
    assert command(["docker", "exec", redis, "redis-cli", "-n", "15", "DBSIZE"]).decode().strip() == "0"
    claim = command(["docker", "exec", redis, "redis-cli", "-n", "15", "SET", "jrc_g_worker_claim", nonce, "NX", "EX", "3600"]).decode().strip()
    assert claim == "OK"
    command(["docker", "exec", container, "ruby", "-rfileutils", "-e",
             "p=ARGV.fetch(0);raise unless p.match?(/\\A\\/tmp\\/jrc_g_worker_[0-9a-f]{12}\\z/) && !File.exist?(p);FileUtils.mkdir_p(p)", directory])
    env = {"RAILS_ENV": "test", "POSTGRES_DATABASE": database, "POSTGRES_HOST": postgres,
           "POSTGRES_USERNAME": "postgres", "POSTGRES_PASSWORD": "rel-v2-disposable-only",
           "DATABASE_URL": "postgresql://postgres:rel-v2-disposable-only@" + postgres + "/" + database,
           "REDIS_URL": "redis://" + redis + ":6379/15", "REDIS_SENTINELS": "", "REDIS_PASSWORD": "",
           "BUNDLE_PATH": "/gems", "BUNDLE_WITHOUT": "development", "BUNDLE_GEMFILE": source + "/Gemfile",
           "SECRET_KEY_BASE": "g-owned-worker-synthetic-only", "TZ": "UTC", "LOG_LEVEL": "warn",
           "JRC_G_NONCE": nonce, "JRC_G_DATABASE": database, "JRC_G_QUEUE": queue,
           "JRC_G_DIRECTORY": directory, "JRC_G_READY_FILE": directory + "/ready",
           "JRC_G_WORKER_NETWORK_FILE": directory + "/network.json",
           "JRC_G_RECEIPT_KEY": "jrc_g_worker:" + nonce + ":ack"}
    args = ["docker", "exec", "-w", source]
    for key, value in env.items():
        args += ["-e", key + "=" + value]
    # Parent wrapper has a unique argument and only forwards TERM to its owned
    # child; the Ruby gate gracefully stops its own Sidekiq child in ensure.
    pidfile = directory + "/wrapper.pid"
    wrapper = "file,nonce,gate=ARGV;child=Process.spawn('bundle','exec','ruby','-rwebmock','-e',\"WebMock.enable!;WebMock.disable_net_connect!;load 'bin/rails'\",'runner',gate,nonce);File.write(file,Process.pid.to_s);Signal.trap('USR1'){Process.kill('TERM',child) rescue nil};_,status=Process.wait2(child);exit(status.exitstatus || 1)"
    args += [container, "ruby", "-e", wrapper, pidfile, nonce, "spec/integration/jrc_relationship/owned_worker_gate.rb"]
    result["phase"] = "real_worker"
    with (artifact / "runtime.log").open("xb") as output:
        process = subprocess.Popen(args, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 360
        stopped = False
        while process.poll() is None:
            free = shutil.disk_usage(root).free
            result["minimum_free"] = min(result["minimum_free"], free)
            if (free <= 2_000_000_000 or time.monotonic() > deadline) and not stopped:
                stopper = "file,nonce=ARGV;pid=Integer(File.read(file));raise unless File.read('/proc/'+pid.to_s+'/cmdline').include?(nonce);Process.kill('USR1',pid)"
                subprocess.run(["docker", "exec", container, "ruby", "-e", stopper, pidfile, nonce], check=True)
                result["stopped_owned_test"] = True
                stopped = True
            time.sleep(1)
        result["exit_code"] = process.returncode
    raw = command(["docker", "exec", container, "cat", directory + "/result.json"])
    (artifact / "native-result.json").write_bytes(raw)
    native = json.loads(raw)
    result["passed"] = process.returncode == 0 and native["status"] == "passed" and not stopped
    assert result["passed"], "Real worker integration gate failed; inspect retained synthetic-only logs"
    print(json.dumps(native))
finally:
    result["free_end"] = shutil.disk_usage(root).free
    result["artifacts_preserved"] = True
    (artifact / "resource.json").write_text(json.dumps(result, indent=2))
    print(json.dumps({"artifact": str(artifact), **result}))
