"""One explicitly authorized frontend build on an exclusive GitHub-hosted runner.

Without --execute this only prints resource availability. It never builds on
Windows, contacts a database, publishes an image or touches a preserved server.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

GIB = 1024 ** 3
START_DISK = 3 * GIB
START_RAM = 5 * GIB
STOP_DISK = 750_000_000
STOP_RAM = 750 * 1024 ** 2
BRANCH = 'refs/heads/codex/lab2-ag-consolidada-20261110'
APPROVED_BRANCHES = {BRANCH, 'refs/heads/codex/whatsapp-history-order-20261111'}
ROOT = Path(__file__).resolve().parent.parent


def resource_reason(disk, ram, starting=False):
    if starting:
        if disk < START_DISK:
            return 'disk_start_below_3_GiB'
        if ram < START_RAM:
            return 'physical_ram_start_below_5_GiB'
    if disk <= STOP_DISK:
        return 'disk_reserve_reached'
    if ram <= STOP_RAM:
        return 'physical_ram_reserve_reached'
    return None


def authorize(env, expected):
    allowed = (sys.platform == 'linux' and env.get('GITHUB_ACTIONS') == 'true' and
               env.get('RUNNER_ENVIRONMENT') == 'github-hosted' and env.get('GITHUB_REF') in APPROVED_BRANCHES and
               env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch' and env.get('GITHUB_RUN_ATTEMPT') == '1')
    if not allowed:
        raise RuntimeError('Exclusive hosted first-attempt manual workflow required')
    if not re.fullmatch(r'[a-f0-9]{40}', expected or '') or expected != env.get('GITHUB_SHA'):
        raise RuntimeError('Exact authorized consolidated SHA required')
    if env.get('JRC_AG_AUTHORIZED_BUILD_SHA') != expected:
        raise RuntimeError('No explicit build authorization for this SHA')


def sample():
    values = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    ram = int(values['MemAvailable'].split()[0]) * 1024
    source_free = shutil.disk_usage(ROOT).free
    output_free = shutil.disk_usage(os.environ.get('RUNNER_TEMP', ROOT)).free
    return {'at_monotonic': time.monotonic(), 'disk_free': min(source_free, output_free),
            'source_disk_free': source_free, 'output_disk_free': output_free, 'ram_available': ram}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def no_other_vite_build():
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            args = (entry / 'cmdline').read_bytes().split(b'\0')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        vite = any(Path(os.fsdecode(arg)).name in {'vite', 'vite.js', 'vite.mjs'} for arg in args if arg)
        if vite and b'build' in args:
            raise RuntimeError('Another Vite build is active; no process was stopped')


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(65536), b''):
            digest.update(chunk)
    return digest.hexdigest()


def execute(expected):
    authorize(os.environ, expected)
    if Path(os.environ['GITHUB_WORKSPACE']).resolve() != ROOT or git('rev-parse', 'HEAD') != expected:
        raise RuntimeError('Fresh exact-source workflow checkout required')
    subprocess.run(['git', 'diff', '--exit-code'], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    no_other_vite_build()
    initial = sample()
    reason = resource_reason(initial['disk_free'], initial['ram_available'], starting=True)
    if reason:
        print(json.dumps({'started': False, 'reason': reason, 'resources': initial}))
        return 1
    base = Path(os.environ['RUNNER_TEMP']).resolve()
    if not base.is_dir() or base == ROOT or ROOT in base.parents:
        raise RuntimeError('Exclusive runner temporary output outside the source is required')
    attempt = base / ('jrc-ag-build-' + expected)
    attempt.mkdir()  # Existing attempt/output must never be overwritten or cleaned.
    output = attempt / 'frontend'
    env = os.environ.copy()
    env.update(RAILS_ENV='production', VITE_RUBY_MODE='production', NODE_OPTIONS='--max-old-space-size=4096')
    result = {'sha': expected, 'started': False, 'build_passed': False, 'publication': False,
              'initial': initial, 'disk_min': initial['disk_free'], 'ram_min': initial['ram_available']}
    proc = None
    started = time.monotonic()
    try:
        # The second sample occurs immediately before spawning the only owned build.
        current = sample()
        reason = resource_reason(current['disk_free'], current['ram_available'], starting=True)
        if reason:
            raise RuntimeError(reason)
        no_other_vite_build()
        with (attempt / 'build.log').open('x', encoding='utf-8') as log:
            proc = subprocess.Popen(['pnpm', 'exec', 'vite', 'build', '--outDir', str(output)], cwd=ROOT,
                                    env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            result['started'] = True
            while proc.poll() is None:
                current = sample()
                result['disk_min'] = min(result['disk_min'], current['disk_free'])
                result['ram_min'] = min(result['ram_min'], current['ram_available'])
                reason = resource_reason(current['disk_free'], current['ram_available'])
                if reason or time.monotonic() - started > 1800:
                    raise RuntimeError(reason or 'owned_build_timeout')
                time.sleep(0.5)
            result['exit_code'] = proc.wait()
        if result['exit_code'] != 0:
            raise RuntimeError('Vite failed; retained output is not an accepted candidate')
        current = sample()
        result['disk_min'] = min(result['disk_min'], current['disk_free'])
        result['ram_min'] = min(result['ram_min'], current['ram_available'])
        reason = resource_reason(current['disk_free'], current['ram_available'])
        if reason:
            raise RuntimeError(reason)
        manifests = [output / '.vite/manifest.json', output / 'manifest.json']
        manifest = next((path for path in manifests if path.is_file()), None)
        if not manifest or not list(output.rglob('*.css')):
            raise RuntimeError('New manifest and actual CSS are required')
        entries = json.loads(manifest.read_text())
        for key in ['entrypoints/dashboard.js', 'entrypoints/v3app.js']:
            item = entries.get(key, {})
            if item.get('isEntry') is not True or not isinstance(item.get('file'), str):
                raise RuntimeError('Both actual dashboard entrypoints must be compiled')
            file = (output / item['file']).resolve()
            if output.resolve() not in file.parents or not file.is_file():
                raise RuntimeError('Manifest entry must reference a newly generated contained file')
        if git('rev-parse', 'HEAD') != expected:
            raise RuntimeError('Source revision changed during build')
        subprocess.run(['git', 'diff', '--exit-code'], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        result['files'] = [{'path': path.relative_to(output).as_posix(), 'bytes': path.stat().st_size, 'sha256': sha256(path)}
                           for path in sorted(output.rglob('*')) if path.is_file()]
        result['manifest_sha256'] = sha256(manifest)
        result['build_passed'] = True
    except BaseException as error:
        result['failure'] = str(error)
        if proc is not None and proc.poll() is None:
            # Only the process group created by this invocation; never pkill/node/WSL/Docker.
            if os.getpgid(proc.pid) != proc.pid:
                raise RuntimeError('Owned process group verification failed') from error
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=10)
            result['stopped_owned_build'] = True
    finally:
        result['final'] = sample()
        result['seconds'] = round(time.monotonic() - started, 2)
        (attempt / 'build-result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({key: value for key, value in result.items() if key != 'files'}))
    return 0 if result['build_passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--expected-sha')
    args = parser.parse_args()
    if not args.execute:
        print(json.dumps({'started': False, 'read_only': True, 'resources': sample() if sys.platform == 'linux' else None}))
    else:
        sys.exit(execute(args.expected_sha))
