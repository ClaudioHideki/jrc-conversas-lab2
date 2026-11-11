"""One bounded network diagnostic on an owned disposable runner; no product execution."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

BRANCH = 'refs/heads/codex/diag-ubuntu-connectivity-20261111-6195'
CANDIDATE = '6195f7d21a0781cd5c5cf4d13bd73a497bb5a452'
REFERENCE = 'ed1323faaa67f46c5e0e0385dae455dee69f85aa'
MIRRORS = ['https://archive.ubuntu.com/ubuntu',
           'https://azure.archive.ubuntu.com/ubuntu',
           'https://mirrors.edge.kernel.org/ubuntu']
SUITES = ['noble', 'noble-updates', 'noble-backports', 'noble-security']
PROFILES = [
    ('current_5_10', ['--ipv4', '--location', '--connect-timeout', '5', '--max-time', '10']),
    ('controlled_10_10', ['--ipv4', '--location', '--connect-timeout', '10', '--max-time', '10']),
    ('reference_total_10', ['--max-time', '10']),
]
KEYRING = Path('/usr/share/keyrings/ubuntu-archive-keyring.gpg')


def utc():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_snapshot():
    paths = [Path('/etc/resolv.conf'), Path('/etc/hosts'), Path('/etc/apt/sources.list')]
    paths += list(Path('/etc/apt/sources.list.d').glob('*.list'))
    paths += list(Path('/etc/apt/sources.list.d').glob('*.sources'))
    paths += list(Path('/etc/apt').glob('apt-mirrors*.txt'))
    return {str(p): digest(p) for p in paths if p.is_file()}


def safe(text):
    return re.sub(r'(https?://)[^/\s@]+@', r'\1[redacted]@', text)[-3000:]


def command(args, timeout, env=None):
    started = time.monotonic()
    try:
        r = subprocess.run(args, text=True, capture_output=True, timeout=timeout,
                           env=env, check=False)
        return {'returncode': r.returncode, 'stdout': r.stdout,
                'stderr': r.stderr, 'wall_seconds': round(time.monotonic() - started, 4)}
    except subprocess.TimeoutExpired as error:
        def text(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        return {'returncode': 124, 'stdout': text(error.stdout), 'stderr': text(error.stderr),
                'wall_seconds': round(time.monotonic() - started, 4), 'outer_timeout': True}


def phase(record):
    if record['ok']:
        return 'ok'
    message = record['stderr'].lower()
    if record['curl_exit'] == 6 or 'resolv' in message:
        return 'dns'
    if record['http_code'] >= 400:
        return 'http'
    if not record.get('remote_ip'):
        return 'dns_or_connect'
    if not record.get('time_connect'):
        return 'tcp'
    if not record.get('time_appconnect'):
        return 'tls'
    return 'http_or_transfer'


def probe(root, mirror_index, suite, profile):
    name, options = profile
    mirror = MIRRORS[mirror_index]
    url = mirror + '/dists/' + suite + '/InRelease'
    target = root / 'metadata' / (str(mirror_index) + '-' + suite + '-' + name + '.InRelease')
    args = ['curl', '--disable', '--proto', '=https', '--proto-redir', '=https',
            '--fail', '--silent', '--show-error', *options,
            '--output', str(target), '--write-out', '%{json}', '--', url]
    raw = command(args, 14)
    try:
        metrics = json.loads(raw['stdout'])
    except (ValueError, TypeError):
        metrics = {}
    record = {'at_utc': utc(), 'mirror': mirror, 'suite': suite, 'profile': name,
              'url': url, 'curl_exit': raw['returncode'], 'wall_seconds': raw['wall_seconds'],
              'stderr': safe(raw['stderr'])}
    for key in ['http_code', 'remote_ip', 'remote_port', 'time_namelookup', 'time_connect',
                'time_appconnect', 'time_starttransfer', 'time_total', 'ssl_verify_result',
                'num_redirects', 'url_effective']:
        record[key] = metrics.get(key, 0 if key not in ['remote_ip', 'url_effective'] else '')
    record['ok'] = (record['curl_exit'] == 0 and record['http_code'] == 200
                    and record['ssl_verify_result'] == 0 and target.is_file())
    if record['ok']:
        verification = command(['gpgv', '--homedir', str(root / 'gnupg'),
                                '--keyring', str(KEYRING), '--status-fd', '1', str(target)], 10)
        record['signature_verified'] = verification['returncode'] == 0
        record['gpgv_exit'] = verification['returncode']
        record['signature_status'] = safe(verification['stdout'])
        record['signature_message'] = safe(verification['stderr'])
        record['metadata_sha256'] = digest(target)
        fields = {}
        for line in target.read_text(errors='replace').splitlines():
            for field in ['Suite', 'Codename', 'Date', 'Valid-Until']:
                if line.startswith(field + ':'):
                    fields[field] = line.split(':', 1)[1].strip()
        record['release'] = fields
    else:
        record['signature_verified'] = False
    record['failure_phase'] = phase(record)
    if record['ok'] and not record['signature_verified']:
        record['failure_phase'] = 'signature'
    return record


def isolated_apt(root, mirror_index):
    # No /etc changes, sudo, installs, resolver modifications or system APT hooks.
    folder = root / ('apt-' + str(mirror_index))
    folder.mkdir()
    for sub in ['lists/partial', 'cache/archives/partial', 'logs', 'empty-parts']:
        (folder / sub).mkdir(parents=True, exist_ok=True)
    source = folder / 'sources.list'
    source.write_text(''.join(
        'deb [arch=amd64 signed-by=' + str(KEYRING) + '] ' + MIRRORS[mirror_index] +
        ' ' + suite + ' main restricted universe multiverse\n' for suite in SUITES))
    main_config = folder / 'empty.conf'
    main_config.write_text('')
    config = {
        'Dir::Etc::parts': str(folder / 'empty-parts'),
        'Dir::Etc::main': str(main_config),
        'Dir::Etc::sourcelist': str(source),
        'Dir::Etc::sourceparts': str(folder / 'empty-parts'),
        'Dir::State::lists': str(folder / 'lists'),
        'Dir::State::status': '/var/lib/dpkg/status',
        'Dir::Cache': str(folder / 'cache'),
        'Dir::Log': str(folder / 'logs'),
        'Acquire::ForceIPv4': 'true',
        'Acquire::Retries': '0',
        'Acquire::http::Timeout': '20',
        'Acquire::https::Timeout': '20',
        'APT::Update::Error-Mode': 'any',
        'Acquire::AllowInsecureRepositories': 'false',
        'Acquire::AllowDowngradeToInsecureRepositories': 'false',
        'Acquire::Check-Date': 'true',
        'Acquire::Check-Valid-Until': 'true',
    }
    cfg = folder / 'diagnostic.conf'
    cfg.write_text(''.join(k + ' ' + json.dumps(v) + ';\n' for k, v in config.items()))
    result = command(['apt-get', 'update'], 120, {**os.environ, 'APT_CONFIG': str(cfg), 'LC_ALL': 'C'})
    (folder / 'apt-update.log').write_text(safe(result['stdout']) + '\n' + safe(result['stderr']))
    return {'mirror': MIRRORS[mirror_index], 'returncode': result['returncode'],
            'wall_seconds': result['wall_seconds'], 'ok': result['returncode'] == 0,
            'outer_timeout': result.get('outer_timeout', False),
            'tail': safe(result['stdout'] + '\n' + result['stderr']),
            'packages_installed': False, 'isolated_state_and_sources': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    assert os.environ.get('GITHUB_ACTIONS') == 'true'
    assert os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
    assert os.environ.get('GITHUB_REPOSITORY') == 'ClaudioHideki/jrc-conversas-lab2'
    assert os.environ.get('GITHUB_REF') == BRANCH
    assert os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'Only one authorized diagnostic attempt'
    release = Path('/etc/os-release').read_text()
    assert '\nID=ubuntu\n' in '\n' + release and 'VERSION_CODENAME=noble' in release
    assert all(shutil.which(tool) for tool in ['curl', 'getent', 'gpgv', 'apt-get'])
    assert KEYRING.is_file()
    root = Path(args.output).resolve()
    parent = Path(os.environ['RUNNER_TEMP']).resolve()
    assert root.parent == parent and root.name.startswith('jrc-connectivity-') and not root.exists()
    root.mkdir()
    (root / 'metadata').mkdir()
    (root / 'gnupg').mkdir(mode=0o700)
    before = protected_snapshot()
    report = {'started_utc': utc(), 'diagnostic_sha': os.environ['GITHUB_SHA'],
              'candidate_sha': CANDIDATE, 'approved_reference_sha': REFERENCE,
              'single_runner': True, 'automatic_retries': 0,
              'profiles': {name: flags for name, flags in PROFILES},
              'method': 'Profile order rotates per URL; the matched IPv4 control isolates connect timeout. One VM cannot prove fleet-wide stability.',
              'keyring_sha256': digest(KEYRING), 'dns': [], 'attempts': [], 'apt': [],
              'proxy_configured': any(os.environ.get(k) for k in ['http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY']),
              'curl_version': command(['curl', '--version'], 5)['stdout'].splitlines()[0],
              'packages_installed': False}
    started = time.monotonic()
    try:
        for mirror_index, mirror in enumerate(MIRRORS):
            host = mirror.split('/')[2]
            for family in ['ahostsv4', 'ahostsv6']:
                result = command(['getent', family, host], 10)
                row = {'host': host, 'family': family, 'returncode': result['returncode'],
                       'wall_seconds': result['wall_seconds'],
                       'addresses': sorted({line.split()[0] for line in result['stdout'].splitlines() if line.split()})[:8]}
                report['dns'].append(row)
                print(json.dumps({'dns': row}), flush=True)
            for suite_index, suite in enumerate(SUITES):
                offset = (mirror_index + suite_index) % len(PROFILES)
                profiles = PROFILES[offset:] + PROFILES[:offset]
                for profile in profiles:
                    assert time.monotonic() - started < 850, 'Diagnostic wall-time budget reached'
                    row = probe(root, mirror_index, suite, profile)
                    report['attempts'].append(row)
                    with (root / 'attempts.jsonl').open('a') as stream:
                        stream.write(json.dumps(row) + '\n')
                    print(json.dumps({'probe': {k: row[k] for k in ['mirror', 'suite', 'profile', 'curl_exit',
                        'http_code', 'wall_seconds', 'failure_phase', 'signature_verified']}}), flush=True)
        for mirror_index, mirror in enumerate(MIRRORS):
            complete = all(any(row['mirror'] == mirror and row['suite'] == suite
                               and row['ok'] and row['signature_verified'] for row in report['attempts'])
                           for suite in SUITES)
            if complete:
                row = isolated_apt(root, mirror_index)
                report['apt'].append(row)
                print(json.dumps({'apt': row}), flush=True)
        report['completed'] = True
    except Exception as error:
        report['completed'] = False
        report['error'] = safe(str(error))
    finally:
        after = protected_snapshot()
        report['protected_files_unchanged'] = before == after
        report['protected_file_hashes_before'] = before
        report['protected_file_hashes_after'] = after
        report['finished_utc'] = utc()
        report['seconds'] = round(time.monotonic() - started, 2)
        report['outcomes'] = dict(Counter(row['failure_phase'] for row in report['attempts']))
        report['full_suite_mirrors'] = [mirror for mirror in MIRRORS if all(
            any(row['mirror'] == mirror and row['suite'] == suite and row['ok'] and row['signature_verified']
                for row in report['attempts']) for suite in SUITES)]
        report['apt_verified_mirrors'] = [row['mirror'] for row in report['apt'] if row['ok']]
        (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        with (root / 'attempts.tsv').open('w') as output:
            output.write('mirror\tsuite\tprofile\texit\thttp\tdns_s\tconnect_s\ttls_s\ttotal_s\tphase\tsignature\n')
            for row in report['attempts']:
                values = [row['mirror'], row['suite'], row['profile'], row['curl_exit'], row['http_code'],
                          row['time_namelookup'], row['time_connect'], row['time_appconnect'],
                          row['time_total'], row['failure_phase'], row['signature_verified']]
                output.write('\t'.join(map(str, values)) + '\n')
        summary = ('Diagnostic ' + report['diagnostic_sha'] + '\nCandidate preserved: ' + CANDIDATE +
                   '\nAttempts: ' + str(len(report['attempts'])) +
                   '\nAPT verified mirrors: ' + ', '.join(report['apt_verified_mirrors']) +
                   '\nResolver and system sources unchanged: ' + str(report['protected_files_unchanged']) + '\n')
        (root / 'summary.txt').write_text(summary)
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
            output.write('~~~\n' + summary + '~~~\n')
        print(summary, flush=True)
    return 0 if report.get('completed') and report['protected_files_unchanged'] and report['apt_verified_mirrors'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
