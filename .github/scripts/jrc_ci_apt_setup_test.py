"""Isolated helper tests with simulated curl/APT; real networking is tested by native CI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name('jrc_ci_apt_setup.sh')
SUITES = ['noble', 'noble-updates', 'noble-backports', 'noble-security']
PRIMARY = 'archive.ubuntu.com'
AZURE = 'azure.archive.ubuntu.com'
KERNEL = 'mirrors.edge.kernel.org'
PACKAGES = ['libpq-dev', 'libvips', 'libvips-dev']

CURL = r"""#!/usr/bin/env python3
import json, os, sys
from urllib.parse import urlsplit
args = sys.argv[1:]
url = urlsplit(args[-1])
with open(os.environ['MOCK_TRACE'], 'a') as out:
    out.write(json.dumps({'command': 'curl', 'args': args}) + '\n')
value = json.loads(os.environ['MOCK_NETWORK']).get(url.hostname, 'dns')
if isinstance(value, dict):
    value = value.get(url.path.split('/')[-2], 'dns')
if value == 'dns':
    print('000', end='')
    raise SystemExit(6)
print(value, end='')
"""
SUDO = r"""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
value = sys.stdin.read() if args[0] == 'tee' else ''
with open(os.environ['MOCK_TRACE'], 'a') as out:
    out.write(json.dumps({'command': 'sudo', 'args': args, 'stdin': value}) + '\n')
if args[:2] == ['apt-get', 'update'] and os.environ.get('MOCK_APT_FAILURE') == '1':
    raise SystemExit(100)
"""


class MirrorSelectionTests(unittest.TestCase):
    def run_helper(self, network, overrides=None, apt_failure=False):
        # Fixtures and stub executables exist only on the disposable Actions runner.
        self.assertEqual(os.environ.get('GITHUB_ACTIONS'), 'true')
        self.assertEqual(os.environ.get('RUNNER_ENVIRONMENT'), 'github-hosted')
        with tempfile.TemporaryDirectory(prefix='jrc-ci-mirror-test-', dir=os.environ['RUNNER_TEMP']) as folder:
            root = Path(folder)
            for name, source in [('curl', CURL), ('sudo', SUDO)]:
                file = root / name
                file.write_text(source)
                file.chmod(0o700)
            trace = root / 'trace.jsonl'
            env = {**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH'],
                   'MOCK_TRACE': str(trace), 'MOCK_NETWORK': json.dumps(network)}
            if overrides:
                env.update(overrides)
            if apt_failure:
                env['MOCK_APT_FAILURE'] = '1'
            result = subprocess.run(['bash', str(SCRIPT), *PACKAGES], env=env, text=True,
                                    capture_output=True, timeout=10, check=False)
            calls = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
            return result, calls

    def test_refuses_local_execution_before_network_or_privileged_commands(self):
        result, calls = self.run_helper({}, {'GITHUB_ACTIONS': 'false'})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_refuses_shared_runners(self):
        result, calls = self.run_helper({}, {'RUNNER_ENVIRONMENT': 'self-hosted'})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_refuses_other_repositories(self):
        result, calls = self.run_helper({}, {'GITHUB_REPOSITORY': 'unrelated/repository'})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_refuses_windows(self):
        result, calls = self.run_helper({}, {'RUNNER_OS': 'Windows'})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_primary_requires_all_four_suites_and_preserves_packages_and_limits(self):
        result, calls = self.run_helper({PRIMARY: 200})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('mirror selected: https://' + PRIMARY + '/ubuntu', result.stdout)
        probes = [row['args'][-1] for row in calls if row['command'] == 'curl']
        self.assertEqual(probes, ['https://' + PRIMARY + '/ubuntu/dists/' + suite + '/InRelease' for suite in SUITES])
        commands = [row for row in calls if row['command'] == 'sudo']
        self.assertEqual(commands[-1]['args'], ['apt-get', 'install', '-y', '--no-install-recommends', *PACKAGES])
        settings = next(row['stdin'] for row in commands if row['args'][0] == 'tee')
        for value in ['ForceIPv4 "true"', 'Retries "2"', 'http::Timeout "20"', 'https::Timeout "20"', 'Error-Mode "any"']:
            self.assertIn(value, settings)

    def test_falls_back_to_azure_without_mutating_dns(self):
        result, calls = self.run_helper({AZURE: 200})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('mirror selected: https://' + AZURE + '/ubuntu', result.stdout)
        self.assertTrue(all('resolv.conf' not in ' '.join(row['args']) for row in calls))

    def test_falls_back_to_kernel_and_keeps_https_only_ipv4_probes(self):
        result, calls = self.run_helper({KERNEL: 200})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('mirror selected: https://' + KERNEL + '/ubuntu', result.stdout)
        for row in calls:
            if row['command'] != 'curl':
                continue
            args = row['args']
            self.assertIn('--ipv4', args)
            self.assertEqual(args[args.index('--proto') + 1], '=https')
            self.assertEqual(args[args.index('--proto-redir') + 1], '=https')
            self.assertEqual(args[args.index('--max-time') + 1], '10')

    def test_rejects_a_mirror_missing_the_security_suite(self):
        network = {PRIMARY: {**dict.fromkeys(SUITES, 200), 'noble-security': 503}, AZURE: 200}
        result, _calls = self.run_helper(network)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('mirror selected: https://' + AZURE + '/ubuntu', result.stdout)
        self.assertIn('noble-security/InRelease HTTP=503', result.stderr)

    def test_rejects_redirect_status_without_a_successful_final_response(self):
        result, _calls = self.run_helper({PRIMARY: 302, AZURE: 200})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('mirror selected: https://' + AZURE + '/ubuntu', result.stdout)

    def test_no_reachable_mirror_fails_before_any_privileged_change(self):
        result, calls = self.run_helper({})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No approved HTTPS Ubuntu mirror', result.stderr)
        self.assertFalse(any(row['command'] == 'sudo' for row in calls))

    def test_connectivity_success_does_not_bypass_an_apt_verification_failure(self):
        result, calls = self.run_helper({PRIMARY: 200}, apt_failure=True)
        self.assertEqual(result.returncode, 100)
        commands = [row['args'] for row in calls if row['command'] == 'sudo']
        self.assertNotIn(['apt-get', 'install', '-y', '--no-install-recommends', *PACKAGES], commands)
        self.assertTrue(all('--allow-unauthenticated' not in row and 'trusted=yes' not in ' '.join(row) for row in commands))


if __name__ == '__main__':
    unittest.main(verbosity=2)
