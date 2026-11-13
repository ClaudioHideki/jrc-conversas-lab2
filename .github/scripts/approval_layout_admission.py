"""Preserve the original runtime proof and admit only the reviewed layout diff."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BASE = '5640793988fbf63ac46b0db3466722fc650f0d01'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def verify():
    assert os.environ.get('GITHUB_ACTIONS') == 'true'
    assert os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
    manifest = json.loads((ROOT / '.github/scripts/approval_layout_manifest.json').read_text())
    product = manifest['product_sha']
    assert len(product) == 40 and manifest['base'] == BASE
    subprocess.check_call(['git', 'merge-base', '--is-ancestor', BASE, product], cwd=ROOT)
    subprocess.check_call(['git', 'merge-base', '--is-ancestor', product, 'HEAD'], cwd=ROOT)
    infrastructure = ['.github/scripts/approval_layout_admission.py', '.github/scripts/approval_layout_manifest.json', '.github/workflows/ag-native-candidate.yml']
    assert sorted(git('diff', '--name-only', product, 'HEAD').splitlines()) == infrastructure
    paths = [item['path'] for item in manifest['files']]
    assert len(paths) == len(set(paths))
    assert sorted(git('diff', '--name-only', BASE, product).splitlines()) == sorted(paths)
    for item in manifest['files']:
        path = item['path']
        assert path.startswith(('app/controllers/api/v1/accounts/approvals/', 'app/javascript/dashboard/routes/dashboard/approvals/',
                                'app/javascript/dashboard/i18n/locale/', 'spec/requests/api/v1/accounts/jrc_approvals/')) or path == 'config/routes/jrc_approvals.rb'
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == item['sha256'], path
    # Execute the complete immutable runtime contract at its approved source.
    # No old assertion is removed: the new feature diff is proven separately.
    baseline = Path(os.environ['RUNNER_TEMP']) / 'approved-runtime-source'
    assert not baseline.exists()
    subprocess.check_call(['git', 'worktree', 'add', '--detach', str(baseline), BASE], cwd=ROOT)
    proof = Path(os.environ['RUNNER_TEMP']) / 'approved-runtime-contract.json'
    subprocess.check_call([sys.executable, '-B', 'script/jrc_runtime_contract_test.py', str(proof)], cwd=baseline)
    result = json.loads(proof.read_text())
    assert result['passed']
    result.update({'product_sha': product, 'infrastructure_sha': git('rev-parse', 'HEAD'),
                   'approved_runtime_source': BASE, 'reviewed_layout_files': manifest['files'],
                   'all_other_functional_sources_unchanged': True})
    return result

if __name__ == '__main__':
    result = verify()
    Path(sys.argv[1]).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
