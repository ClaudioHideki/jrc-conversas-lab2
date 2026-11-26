"""Prove official RuboCop server parity before reusing its loaded runtime."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

BASE = 'a24adc6dd8bb660f955b76cce0172ae1638deee2'
FILE = 'app/models/account_user.rb'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def report_signature(report, returncode, *, filename=FILE):
    assert type(returncode) is int and returncode in (0, 1), 'Inspection did not complete'
    assert report['metadata']['rubocop_version'] == '1.75.6'
    assert report['summary']['inspected_file_count'] == 1
    assert report['summary']['target_file_count'] == 1 and len(report['files']) == 1
    assert report['files'][0]['path'] == filename
    offenses = report['files'][0]['offenses']
    assert len(offenses) == report['summary']['offense_count']
    assert all(isinstance(row, dict) and row['cop_name'] and row['location'] for row in offenses)
    content = json.dumps(offenses, sort_keys=True, separators=(',', ':')).encode()
    return {'returncode': returncode, 'offenses': len(offenses), 'offenses_sha256': digest(content),
            'cop_names': sorted({row['cop_name'] for row in offenses}),
            'summary': report['summary'], 'rubocop_version': report['metadata']['rubocop_version']}


def require_parity(standalone, server):
    assert standalone == server, 'RuboCop server changed inspected files, offenses, locations or status'


def command(arguments, *, source=None):
    result = subprocess.run(arguments, input=source, capture_output=True, timeout=180)
    if result.returncode not in (0, 1):
        raise RuntimeError('Bounded native linter command failed; inspect the runner diagnostics')
    return result


def representative_sources():
    paths = subprocess.check_output(['git', 'diff', '--name-only', '--diff-filter=M', BASE, 'HEAD', '--', 'app'], text=True).splitlines()
    for name in paths:
        if not name.startswith('app/') or not name.endswith('.rb') or '..' in Path(name).parts:
            continue
        before = subprocess.check_output(['git', 'show', BASE + ':' + name])
        after = Path(name).read_bytes()
        if before != after and 0 < len(before) < 400_000 and 0 < len(after) < 400_000:
            return name, {'baseline': before, 'candidate': after}
    raise AssertionError('A real changed native Ruby source with both revisions is required for parity')


def main():
    owned = os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
    assert owned and os.name == 'posix', 'Official server probe is exclusive to the disposable Linux runner'
    assert os.environ.get('RUBOCOP_SERVER_HOST', '127.0.0.1') == '127.0.0.1', 'Do not expose the linter server remotely'
    assert 'RUBOCOP_SERVER_PORT' not in os.environ, 'Use an ephemeral project-local linter port'
    workspace = Path(os.environ['GITHUB_WORKSPACE']).resolve()
    assert Path.cwd().resolve() == workspace
    sha = os.environ['GITHUB_SHA']
    assert re.fullmatch('[a-f0-9]{40}', sha)
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == sha
    config_names = ['.rubocop.yml', '.rubocop_todo.yml', 'Gemfile', 'Gemfile.lock']
    configuration = {n: digest(Path(n).read_bytes()) for n in config_names if Path(n).exists()}
    lock = Path('Gemfile.lock').read_text()
    assert re.search(r'^    rubocop \(1\.75\.6\)$', lock, re.M), 'Use the project locked linter'
    filename, sources = representative_sources()
    assert all(sources.values()) and sources['baseline'] != sources['candidate'], 'Compare two different real source revisions'
    # A deliberate syntax-negative stdin fixture proves that neither mode can
    # silently turn an invalid input into success. Never written into the app.
    sources['synthetic_parser_rejection'] = b'def broken(\n'
    modes = {}
    for name, source in sources.items():
        result = command(['bundle', 'exec', 'rubocop', '--no-server', '--stdin', filename, '--format', 'json'], source=source)
        modes[name] = {'source_sha256': digest(source), 'standalone': report_signature(json.loads(result.stdout), result.returncode, filename=filename)}
    negative = modes['synthetic_parser_rejection']['standalone']
    assert negative['returncode'] == 1 and negative['offenses'] > 0 and 'Lint/Syntax' in negative['cop_names']
    start = command(['bundle', 'exec', 'rubocop', '--start-server'])
    assert start.returncode == 0, 'Official project-local server did not start'
    for name, source in sources.items():
        result = command(['bundle', 'exec', 'rubocop', '--server', '--stdin', filename, '--format', 'json'], source=source)
        signature = report_signature(json.loads(result.stdout), result.returncode, filename=filename)
        require_parity(modes[name]['standalone'], signature)
        modes[name]['server'] = signature
    assert configuration == {n: digest(Path(n).read_bytes()) for n in configuration}
    subprocess.run(['git', 'diff', '--exit-code'], check=True, capture_output=True)
    report = {'status': 'passed', 'source_sha': sha, 'baseline_sha': BASE, 'inspected_file': filename,
              'configuration_sha256': configuration, 'modes': modes,
              'server_host': '127.0.0.1', 'ephemeral_project_local_port': True,
              'ordinary_and_server_results_identical': True, 'rules_or_file_coverage_reduced': False,
              'no_product_source_modified': True, 'only_disposable_runner_runtime_started': True}
    raw = (json.dumps(report, indent=2) + '\n').encode()
    Path('/tmp/call-center-rubocop-server-parity.json').write_bytes(raw)
    print(json.dumps({'status': 'passed', 'source_sha': sha, 'parity_cases': len(modes), 'report_sha256': digest(raw)}))


if __name__ == '__main__':
    main()
