"""One additive migration in the exact owned synthetic candidate; no dump/cleanup/server changes."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import time
import uuid

root = Path(__file__).resolve().parent.parent
assert Path.cwd().resolve() == root
assert shutil.disk_usage(root).free > 3_000_000_000
assert subprocess.check_output(["git", "branch", "--show-current"]).decode().strip() == "codex/relacionamento-v2-20261101"
subprocess.run(["git", "merge-base", "--is-ancestor", "b0c1ae37b01554f6faa0c9525b3e10377a082484", "HEAD"], check=True)
source = json.loads((root / ".codex/d9-notifications-20261104/snapshot.json").read_text())["root"]
assert source.startswith("/consolidation-approval-notifications-tests-20261104-")
nonce = uuid.uuid4().hex[:12]
artifact = root / ".codex/master-subject-schema-20261107" / nonce
artifact.mkdir(parents=True, exist_ok=False)
directory = "/tmp/jrc_master_subject_schema_" + nonce
container = "jrc-rel-v2-run-20261101"
postgres = "jrc-rel-v2-pg-20261101"
database = "jrc_rel_v2_candidate_test"
state = {"database": database, "source": source, "nonce": nonce, "head": subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip(),
         "free_start": shutil.disk_usage(root).free, "minimum_free": shutil.disk_usage(root).free,
         "build": False, "cleanup": False, "production": False, "application_servers_changed": False}


def command(args):
    assert shutil.disk_usage(root).free > 2_000_000_000
    return subprocess.check_output(args)


try:
    clients = command(["docker", "exec", postgres, "psql", "-U", "postgres", "-d", "postgres", "-At", "-c",
                       "SELECT count(*) FROM pg_stat_activity WHERE datname='jrc_rel_v2_candidate_test'"]).decode().strip()
    assert clients == "0", "Do not migrate while an owned candidate test is using the database"
    state["sha256"] = {}
    for relative in ["db/migrate/20261107010000_add_master_subjects_to_reviewed_relationship_batches.rb",
                     "spec/integration/jrc_relationship/master_subject_schema_gate.rb"]:
        digest = hashlib.sha256((root / relative).read_bytes()).hexdigest()
        actual = command(["docker", "exec", container, "ruby", "-rdigest", "-e", "puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest", source + "/" + relative]).decode().strip()
        assert actual == digest, "Sync the guarded source snapshot first"
        state["sha256"][relative] = digest
        command(["docker", "exec", container, "ruby", "-c", source + "/" + relative])
    command(["docker", "exec", container, "ruby", "-e", "Dir.mkdir(ARGV.fetch(0))", directory])
    env = {"RAILS_ENV": "test", "POSTGRES_DATABASE": database, "POSTGRES_HOST": postgres, "POSTGRES_USERNAME": "postgres",
           "POSTGRES_PASSWORD": "rel-v2-disposable-only", "DATABASE_URL": "postgresql://postgres:rel-v2-disposable-only@" + postgres + "/" + database,
           "REDIS_URL": "redis://jrc-rel-v2-redis-20261101:6379/13", "REDIS_SENTINELS": "", "REDIS_PASSWORD": "",
           "BUNDLE_PATH": "/gems", "BUNDLE_WITHOUT": "development", "BUNDLE_GEMFILE": source + "/Gemfile",
           "SECRET_KEY_BASE": "synthetic-master-subject-schema-only", "JRC_SCHEMA_DIRECTORY": directory}
    args = ["docker", "exec", "-w", source]
    for key, value in env.items():
        args += ["-e", key + "=" + value]
    pidfile = directory + "/wrapper.pid"
    wrapper = "file,nonce,gate=ARGV;child=Process.spawn('bundle','exec','ruby','-rwebmock','-e',\"WebMock.enable!;WebMock.disable_net_connect!;load 'bin/rails'\",'runner',gate);File.write(file,Process.pid.to_s);Signal.trap('USR1'){Process.kill('TERM',child) rescue nil};_,status=Process.wait2(child);exit(status.exitstatus || 1)"
    args += [container, "ruby", "-e", wrapper, pidfile, nonce, "spec/integration/jrc_relationship/master_subject_schema_gate.rb"]
    with (artifact / "runtime.log").open("xb") as output:
        process = subprocess.Popen(args, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 120
        stopped = False
        while process.poll() is None:
            free = shutil.disk_usage(root).free
            state["minimum_free"] = min(state["minimum_free"], free)
            if (free <= 2_000_000_000 or time.monotonic() > deadline) and not stopped:
                stopper = "file,nonce=ARGV;pid=Integer(File.read(file));raise unless File.read('/proc/'+pid.to_s+'/cmdline').include?(nonce);Process.kill('USR1',pid)"
                subprocess.run(["docker", "exec", container, "ruby", "-e", stopper, pidfile, nonce], check=True)
                stopped = True
                state["stopped_owned_operation"] = True
            time.sleep(1)
        state["exit_code"] = process.returncode
    raw = command(["docker", "exec", container, "cat", directory + "/result.json"])
    (artifact / "native-result.json").write_bytes(raw)
    native = json.loads(raw)
    state["passed"] = process.returncode == 0 and native["status"] == "passed" and not stopped
    print(json.dumps({"status": native["status"], "database": native["database"],
                      "preserved_tables": native["after"], "prior_migration_versions": len(native["versions_before"])}))
    assert state["passed"], "Schema gate failed; preserve logs and diagnose before any retry"
finally:
    state["free_end"] = shutil.disk_usage(root).free
    (artifact / "resource.json").write_text(json.dumps(state, indent=2))
    print(json.dumps({"artifact": str(artifact), **state}))
