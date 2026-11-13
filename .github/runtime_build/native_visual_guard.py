"""Native Rails + fresh CSS acceptance before any Docker image construction."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'product'
PRODUCT = '98e201efd33e1cf66706c4d51c5383052754cd34'
BRANCH = 'ci/approvals-word-native-visual-20261113'
sys.path.insert(0, str(ROOT / '.github/runtime_build'))
import guard as preserved_guard

def require(value, message):
    if not value:
        raise RuntimeError(message)

def main():
    require(sys.platform == 'linux' and os.environ['GITHUB_ACTIONS'] == 'true' and os.environ['RUNNER_ENVIRONMENT'] == 'github-hosted', 'Hosted Linux required')
    require(os.environ['GITHUB_REF_NAME'] == BRANCH and os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch'
            and os.environ['GITHUB_RUN_ATTEMPT'] == '1', 'Exact first manual execution required')
    require(os.environ['GITHUB_SHA'] == os.environ['EXPECTED_EXECUTION_SHA'], 'Wrong infrastructure')
    require(subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD'], text=True).strip() == PRODUCT, 'Wrong product')
    require(os.environ['POSTGRES_DATABASE'] == 'jrc_runtime_image_test' and os.environ['POSTGRES_HOST'] == '127.0.0.1', 'Wrong database')
    output = Path(os.environ['RUNNER_TEMP']) / ('approvals-native-visual-' + os.environ['GITHUB_RUN_ID'])
    output.mkdir()
    limits = preserved_guard.limits()
    result = {'passed': False, 'product_sha': PRODUCT, 'infrastructure_sha': os.environ['GITHUB_SHA'],
              'image_built': False, 'mocked_application': False, 'phases': [], 'resources': {}}
    owned = []
    def sample(start=False):
        values = preserved_guard.effective_sample(limits)
        require(not start or values['ram_available'] >= 8 * 1024**3, 'Minimum effective RAM is 8 GiB')
        reason = limits.resource_reason(values['disk_free'], values['ram_available'], starting=start)
        require(reason is None, reason)
        stats = result['resources']
        if 'initial' not in stats: stats['initial'] = values
        stats['ram_min'] = min(stats.get('ram_min', values['ram_available']), values['ram_available'])
        stats['disk_min'] = min(stats.get('disk_min', values['disk_free']), values['disk_free'])
        stats['final'] = values
    def stop(process):
        if process.poll() is None:
            require(os.getpgid(process.pid) == process.pid, 'Owned process identity changed')
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
    def command(args, name, env=None, timeout=600):
        sample()
        start = time.monotonic()
        phase = {'name': name}
        result['phases'].append(phase)
        with (output / (name + '.log')).open('x') as stream:
            process = subprocess.Popen(args, cwd=SOURCE, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            owned.append(process)
            try:
                while process.poll() is None:
                    sample()
                    require(time.monotonic() - start < timeout, 'Owned phase timed out: ' + name)
                    time.sleep(0.5)
                phase['exit_code'] = process.wait()
                require(phase['exit_code'] == 0, 'Native phase failed: ' + name)
            finally:
                stop(process)
                phase['seconds'] = round(time.monotonic() - start, 3)
    server = None
    env = os.environ.copy()
    credentials = output / 'browser-synthetic-credentials.private'
    env.update(JRC_BROWSER_PRODUCT_SHA=PRODUCT, JRC_BROWSER_CREDENTIALS=str(credentials),
               RUNTIME_SMOKE_NONCE=uuid.uuid4().hex, JRC_BROWSER_OUTPUT=str(output / 'browser'),
               JRC_BROWSER_ORIGIN='http://127.0.0.1:3000', JRC_PLAYWRIGHT_MODULE=str(SOURCE / 'tests/playwright/node_modules/@playwright/test'),
               JRC_BROWSER_LOCALE_FILE=str(SOURCE / 'app/javascript/dashboard/i18n/locale/pt_BR/jrcApprovals.json'))
    try:
        sample(start=True)
        limits.no_other_vite_build()
        for key, expected in [('JRC_VISUAL_POSTGRES_ID', preserved_guard.PG), ('JRC_VISUAL_REDIS_ID', preserved_guard.REDIS)]:
            info = json.loads(subprocess.check_output(['docker', 'inspect', os.environ[key]], text=True))[0]
            require(info['Id'] == os.environ[key] and info['Config']['Image'] == expected and info['State']['Running'], 'Wrong disposable service')
            require(not info['HostConfig'].get('Binds'), 'Existing volume mount refused')
        db = subprocess.check_output(['docker', 'exec', env['JRC_VISUAL_POSTGRES_ID'], 'psql', '-U', 'postgres', '-tAc',
                                     "SELECT count(*) FROM pg_database WHERE datname='jrc_runtime_image_test'"], text=True).strip()
        require(db == '0', 'Visual database already exists')
        with socket.socket() as probe:
            require(probe.connect_ex(('127.0.0.1', 3000)) != 0, 'Native visual port already occupied')
        command(['bundle', 'exec', 'rails', 'db:create', 'db:migrate'], 'isolated-schema', env, 600)
        build = {**env, 'JRC_VITE_BUILD_HEAP_MIB': '6144', 'VITE_RUBY_VITE_BIN_PATH': str(SOURCE / 'script/jrc_vite_build.mjs')}
        manifest_candidates = [SOURCE / 'public/vite/.vite/manifest.json', SOURCE / 'public/vite/manifest.json']
        require(not any(p.exists() for p in manifest_candidates), 'Previously built assets refused')
        command(['bundle', 'exec', 'rake', 'assets:precompile'], 'fresh-frontend-assets', build, 1800)
        compile_log = (output / 'fresh-frontend-assets.log').read_text()
        result['frontend_heap'] = preserved_guard.frontend_receipt(compile_log)
        command(['bundle', 'exec', 'rails', 'runner', str(ROOT / '.github/runtime_build/approval_native_seed.rb')], 'synthetic-fixture', env, 600)
        (output / 'browser').mkdir()
        stream = (output / 'rails-http.log').open('x')
        server = subprocess.Popen(['bundle', 'exec', 'rails', 'server', '-b', '127.0.0.1', '-p', '3000'], cwd=SOURCE,
                                  env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        owned.append(server)
        start = time.monotonic()
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        html = None
        while time.monotonic() - start < 120:
            sample()
            require(server.poll() is None, 'Native Rails HTTP process exited')
            try:
                with opener.open('http://127.0.0.1:3000/app/login', timeout=3) as response:
                    if response.status == 200:
                        html = response.read().decode()
                        break
            except OSError: pass
            time.sleep(1)
        require(html is not None and '/vite/' in html, 'Fresh native login/assets unavailable')
        assets = []
        for url in dict.fromkeys(re.findall(r'(?:src|href)="([^"]+)"', html)):
            if not url.startswith('/vite/') or not re.search(r'\.(js|css)(?:\?|$)', url): continue
            path = url.split('?', 1)[0]
            local = SOURCE / 'public' / path.lstrip('/')
            with opener.open('http://127.0.0.1:3000' + url, timeout=10) as response: body = response.read()
            digest = hashlib.sha256(body).hexdigest()
            require(digest == hashlib.sha256(local.read_bytes()).hexdigest(), 'HTTP asset differs from fresh build')
            assets.append({'path': path, 'sha256': digest, 'bytes': len(body)})
        require(any(v['path'].endswith('.css') for v in assets) and any(v['path'].endswith('.js') for v in assets), 'Actual JS/CSS missing')
        result['assets'] = assets
        command(['node', str(SOURCE / 'tests/playwright/node_modules/playwright/cli.js'), 'test', '--config',
                 str(ROOT / '.github/runtime_build/approval_browser.config.cjs')], 'native-chrome', env, 1800)
        report = json.loads((output / 'browser/playwright-results.json').read_text())
        stats = report['stats']
        require(stats['expected'] > 0 and all(stats[k] == 0 for k in ['unexpected', 'skipped', 'flaky']), 'Native browser acceptance failed or incomplete')
        result['browser_stats'] = stats
        result['passed'] = True
    except Exception as error:
        result['failure'] = {'type': type(error).__name__, 'message': str(error) if isinstance(error, RuntimeError) else 'Native phase or format failed'}
    finally:
        for process in reversed(owned): stop(process)
        if credentials.exists():
            secret = json.loads(credentials.read_text())['password']
            for path in [*output.rglob('*.log'), *output.rglob('*.json'), *output.rglob('*.txt')]:
                if path.is_file(): path.write_text(path.read_text(errors='replace').replace(secret, '[SYNTHETIC_CREDENTIAL_REDACTED]'))
        (output / 'native-visual-result.json').write_text(json.dumps(result, indent=2) + '\n')
        hashes = [{'path': str(p.relative_to(output)), 'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                  for p in output.rglob('*') if p.is_file() and p.suffix != '.private']
        (output / 'hashes.json').write_text(json.dumps(hashes, indent=2))
    print(json.dumps(result))
    return 0 if result['passed'] else 1

if __name__ == '__main__':
    sys.exit(main())
