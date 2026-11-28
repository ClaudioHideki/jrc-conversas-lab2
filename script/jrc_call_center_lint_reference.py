"""Prove the new lint transport on the exact old inputs in a disposable CI worktree."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

REFERENCE = '63d27d5af43af45090c3d5fdb82e7ec3a82af6d9'
MARKER = 'docs/jrc_contact_center/native_ending_rule_list_summary_candidate_20261128.json'


def require_runner(environment):
    required = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
                'GITHUB_REPOSITORY': 'ClaudioHideki/jrc-conversas-lab2', 'RAILS_ENV': 'test',
                'GITHUB_REF_NAME': 'codex/call-center-control-desk-20261116'}
    if any(environment.get(key) != value for key, value in required.items()):
        raise RuntimeError('Exclusive disposable Call Center runner required')
    if not re.fullmatch('[a-f0-9]{40}', environment.get('GITHUB_SHA', '')):
        raise RuntimeError('Exact candidate identity required')
    if environment.get('GIT_DIR') or environment.get('GIT_WORK_TREE'):
        raise RuntimeError('Unexpected Git directory override')


def main():
    require_runner(os.environ)
    workspace = Path(os.environ['GITHUB_WORKSPACE']).resolve(strict=True)
    runner_temp = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    reference = json.loads((workspace / MARKER).read_bytes())['native_lint_reference']
    assert reference['sha'] == REFERENCE and reference['run'] == 46160117363
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=workspace, text=True).strip() == os.environ['GITHUB_SHA']
    subprocess.run(['git', 'cat-file', '-e', REFERENCE + '^{commit}'], cwd=workspace, check=True)
    suffix = os.environ['GITHUB_RUN_ID'] + '-' + os.environ['GITHUB_RUN_ATTEMPT']
    assert re.fullmatch('[0-9]+-[0-9]+', suffix)
    destination = runner_temp / ('jrc-cc-native-lint-reference-' + suffix)
    assert destination.parent == runner_temp and not destination.exists()
    report = Path('/tmp/call-center-rubocop.json')
    archived = Path('/tmp/call-center-rubocop-reference.json')
    identity = Path('/tmp/call-center-rubocop-reference-identity.json')
    assert not any(path.exists() for path in [report, archived, identity])
    subprocess.run(['git', 'worktree', 'add', '--detach', str(destination), REFERENCE], cwd=workspace, check=True)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=destination, text=True).strip()
    assert actual == REFERENCE
    dependencies = {}
    for name in ['Gemfile', 'Gemfile.lock']:
        before, after = (destination / name).read_bytes(), (workspace / name).read_bytes()
        assert before == after, 'Reference lint dependency identity changed'
        dependencies[name] = hashlib.sha256(after).hexdigest()
    tool = workspace / 'script/jrc_call_center_lint.py'
    # Reuse the installed exact locked bundle, never install another one. Cops,
    # config, Ruby source and the old BASE..HEAD selection come from REFERENCE.
    environment = {**os.environ, 'BUNDLE_GEMFILE': str(workspace / 'Gemfile')}
    subprocess.run([sys.executable, '-B', str(tool)], cwd=destination, env=environment, check=True)
    rows = json.loads(report.read_bytes())
    assert len(rows) == reference['files'] > 0
    assert len({row['path'] for row in rows}) == len(rows)
    assert all(row['new_offenses'] == [] for row in rows)
    report.rename(archived)
    proof = {'product_sha': os.environ['GITHUB_SHA'], 'reference_sha': actual,
             'reference_run': reference['run'], 'files': len(rows), 'dependency_sha256': dependencies,
             'lint_tool_sha256': hashlib.sha256(tool.read_bytes()).hexdigest(),
             'report_sha256': hashlib.file_digest(archived.open('rb'), 'sha256').hexdigest(),
             'no_installs_or_application_or_database_execution': True,
             'main_candidate_checkout_not_modified': True, 'independent_comparison_still_required': True}
    identity.write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps(proof))


if __name__ == '__main__':
    main()
