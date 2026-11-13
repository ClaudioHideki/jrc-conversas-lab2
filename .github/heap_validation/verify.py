"""Focused configuration checks. No Docker build and no real Vite compilation."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(os.environ["GITHUB_WORKSPACE"]) / "product"
OUT = Path(os.environ["RUNNER_TEMP"]) / "heap-validation"
OUT.mkdir(exist_ok=True)
NODE_IMAGE = "docker.io/library/node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5"
GEM_SHA = "db465451eb180abbdc81f596ba63671d2b2552e2bb7bf3c1f7b79f9d58ca9a86"


def command(args, env=None, cwd=None):
    result = subprocess.run(args, env=env, cwd=cwd, text=True, capture_output=True, timeout=90)
    return result


def fixture():
    root = Path(tempfile.mkdtemp(prefix="jrc-vite-heap-", dir=OUT))
    (root / "script").mkdir()
    wrapper = root / "script/jrc_vite_build.mjs"
    wrapper.write_bytes((ROOT / "script/jrc_vite_build.mjs").read_bytes())
    wrapper.chmod(0o755)
    (root / "package.json").write_text('{"type":"module"}')
    (root / "node_modules/vite/bin").mkdir(parents=True)
    (root / "node_modules/vite/package.json").write_text(json.dumps({
        "name": "vite", "version": "command-fixture-only", "type": "module",
        "exports": {"./package.json": "./package.json"}, "bin": {"vite": "bin/vite.js"}}))
    (root / "node_modules/vite/bin/vite.js").write_text(
        "import v8 from 'node:v8';console.log(JSON.stringify({fixtureOnly:true,"
        "heapLimit:v8.getHeapStatistics().heap_size_limit,execArgv:process.execArgv,"
        "nodeOptions:process.env.NODE_OPTIONS,argv:process.argv.slice(2)}));")
    return root


base = "d11c879a3d6e27499e1aea45736797a6e913b829"
changed = subprocess.check_output(["git", "diff", "--name-only", base, "HEAD"], cwd=ROOT, text=True).splitlines()
assert set(changed) == {
    "docker/Dockerfile", "script/jrc_runtime_contract_test.py", "script/jrc_vite_build.mjs",
    "script/jrc_vite_build.test.mjs", "docs/jrc_consolidation/vite_heap6144_preparation_20261112.json"}
docker = (ROOT / "docker/Dockerfile").read_text()
prior = subprocess.check_output(["git", "show", base + ":docker/Dockerfile"], cwd=ROOT, text=True)
assert docker.split("# final build stage\n")[1] == prior.split("# final build stage\n")[1]
assert 'ARG NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider"' in docker
assert docker.count("VITE_RUBY_VITE_BIN_PATH=") == 1 and "ENV NODE_OPTIONS=6144" not in docker
for p in ["Gemfile", "Gemfile.lock", "pnpm-lock.yaml", "bin/vite", "config/vite.json",
          "script/jrc_ag_guarded_frontend_build.py"]:
    assert (ROOT / p).read_bytes() == subprocess.check_output(["git", "show", base + ":" + p], cwd=ROOT)
assert (ROOT / "script/jrc_vite_build.mjs").stat().st_mode & 0o111
(OUT / "structural.json").write_text(json.dumps({
    "passed": True, "source_sha": os.environ["EXPECTED_PRODUCT_SHA"], "changed_paths": changed,
    "normal_runtime_stage_byte_identical": True, "original_resource_guard_byte_identical": True,
    "dependencies_unchanged": True, "docker_build_executed": False, "real_vite_compilation_executed": False}, indent=2))

with urllib.request.urlopen("https://rubygems.org/downloads/vite_ruby-3.10.2.gem", timeout=45) as response:
    gem = response.read(3_000_000)
assert hashlib.sha256(gem).hexdigest() == GEM_SHA
outer = tarfile.open(fileobj=io.BytesIO(gem), mode="r:")
inner = tarfile.open(fileobj=io.BytesIO(outer.extractfile("data.tar.gz").read()), mode="r:gz")
runner_path = OUT / "official-vite-runner.rb"
runner_path.write_bytes(inner.extractfile("lib/vite_ruby/runner.rb").read())
root = fixture()
ruby = OUT / "ruby-command-scope.rb"
ruby.write_text("""
require 'forwardable'
require 'ostruct'
require 'open3'
require 'json'
class ViteRuby; end
load ARGV.fetch(0)
root = ARGV.fetch(1)
wrapper = File.join(root, 'script/jrc_vite_build.mjs')
config = Object.new
config.define_singleton_method(:vite_bin_path) { wrapper }
config.define_singleton_method(:package_manager) { 'pnpm' }
config.define_singleton_method(:mode) { 'production' }
config.define_singleton_method(:to_env) { |env| env }
env = {'JRC_VITE_BUILD_HEAP_MIB' => '6144', 'NODE_OPTIONS' => '--max-old-space-size=4096 --openssl-legacy-provider'}
parent = ENV['NODE_OPTIONS']
runner = ViteRuby::Runner.new(OpenStruct.new(config: config, env: env))
cmd = runner.send(:command_for, ['build'])
raise 'Wrong hook' unless cmd[1] == wrapper && cmd.drop(2) == ['build', '--mode', 'production']
out, err, status = Open3.capture3(*cmd, chdir: root)
raise out + err unless status.success?
spy = out.lines.map { |line| JSON.parse(line) }.find { |entry| entry['fixtureOnly'] }
raise 'Wrong actual child heap' unless spy['heapLimit'] >= 6144 * 1024**2 && spy['heapLimit'] < 6656 * 1024**2
raise 'Parent heap env changed' unless ENV['NODE_OPTIONS'] == parent && !parent.to_s.include?('6144')
raise 'Other Node options changed' unless spy['nodeOptions'] == env['NODE_OPTIONS']
config.define_singleton_method(:vite_bin_path) { nil }
normal = runner.send(:command_for, ['build'])
raise 'Normal Vite command changed' unless normal.drop(1) == ['pnpm', 'exec', 'vite', 'build', '--mode', 'production']
File.write(ARGV.fetch(2), JSON.pretty_generate({passed: true, vite_ruby: '3.10.2',
 child: spy, parent_node_options: parent, normal_command: normal.drop(1),
 fixture_only: true, real_vite_compilation_executed: false}))
""")
env = {**os.environ, "NODE_OPTIONS": "--max-old-space-size=4096 --openssl-legacy-provider"}
result = command(["ruby", str(ruby), str(runner_path), str(root), str(OUT / "ruby-runner-scope.json")], env)
(OUT / "ruby-runner.log").write_text(result.stdout + result.stderr)
assert result.returncode == 0, "Official Vite Ruby routing check failed"

probe = """const fs=require('node:fs'),v8=require('node:v8');
console.log(JSON.stringify({probeOnly:true,node:process.version,available:process.availableMemory(),
 constrained:process.constrainedMemory(),heapLimit:v8.getHeapStatistics().heap_size_limit}));"""
normal = command(["docker", "run", "--rm", "--network", "none", "--entrypoint", "node",
                  NODE_IMAGE, "--max-old-space-size=6144", "-e", probe])
(OUT / "node-alpine.log").write_text(normal.stdout + normal.stderr)
assert normal.returncode == 0
node = json.loads(normal.stdout)
assert node["node"] == "v24.22.3" and node["heapLimit"] >= 6144 * 1024**2
(OUT / "node-alpine.json").write_text(json.dumps({"passed": True, "probe": node, "application_image_built": False}, indent=2))

small = command(["docker", "run", "--rm", "--network", "none", "--memory", "2g", "--memory-swap", "2g",
                 "--entrypoint", "sh", "-e", "JRC_VITE_BUILD_HEAP_MIB=6144",
                 "-e", "NODE_OPTIONS=--max-old-space-size=4096 --openssl-legacy-provider",
                 "--mount", "type=bind,src=" + str(root) + ",dst=/app,readonly",
                 NODE_IMAGE, "-c", 'node -e "$1"; node /app/script/jrc_vite_build.mjs build --mode production', "probe", probe])
(OUT / "cgroup-denial.log").write_text(small.stdout + small.stderr)
assert small.returncode == 1 and "effective_memory_below_8_GiB" in small.stderr
assert '"fixtureOnly":true' not in small.stdout
cap = json.loads(small.stdout.splitlines()[0])
assert 0 < cap["constrained"] <= 2 * 1024**3 and cap["available"] <= 2 * 1024**3
(OUT / "cgroup-denial.json").write_text(json.dumps({
    "passed": True, "probe": cap, "exit_code": small.returncode, "vite_child_launched": False,
    "third_image_build_executed": False}, indent=2))
print(json.dumps({"passed": True, "configuration_checks_only": True, "real_vite_compilation_executed": False,
                  "application_image_build_executed": False, "output": str(OUT)}))
