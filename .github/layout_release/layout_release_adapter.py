"""Bind the fully tested infrastructure tree to the clean product image source."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = 'd68885508f36a8fda2725a3c03d78470e9f9ff70'
VALIDATION = '77bef89d84eb523a1fab8a725a70a5a700a80dd9'
BASE = '5640793988fbf63ac46b0db3466722fc650f0d01'
BRANCH = 'ci/approvals-word-release-gate-20261113'

def require(value, message):
    if not value:
        raise RuntimeError(message)

def git(folder, *args):
    return subprocess.check_output(['git', '-C', str(folder), *args], text=True).strip()

def layout_binding(manifest, contract, changed_paths, hashes):
    require(manifest['product_sha'] == PRODUCT and manifest['base'] == BASE, 'Wrong reviewed layout source')
    files = manifest['files']
    require(len(files) == 13 and len({item['path'] for item in files}) == 13, 'Incomplete or duplicated layout review')
    require(set(changed_paths) == {item['path'] for item in files}, 'Unreviewed functional path changed')
    for item in files:
        require(hashes.get(item['path']) == item['sha256'], 'Reviewed source hash differs: ' + item['path'])
    require(contract['passed'] is True and contract['approved_runtime_source'] == BASE, 'Runtime contract missing')
    require(contract['product_sha'] == PRODUCT and contract['infrastructure_sha'] == VALIDATION, 'Native equivalence identity differs')
    require(contract['reviewed_layout_files'] == files, 'Native reviewed feature differs')
    require(contract['migrations_unchanged'] is True and contract['pnpm_lock_unchanged'] is True, 'Preservation contract failed')
    return {'passed': True, 'product_sha': PRODUCT, 'native_validation_sha': VALIDATION,
            'reviewed_files': files, 'runtime_base': BASE, 'product_code_changed_by_gate': False}

def main():
    execution = os.environ['EXPECTED_EXECUTION_SHA']
    require(os.environ['GITHUB_SHA'] == execution and git(ROOT, 'rev-parse', 'HEAD') == execution, 'Wrong infrastructure')
    require(os.environ['GITHUB_REF_NAME'] == BRANCH and os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch', 'Wrong dispatch')
    require(os.environ['GITHUB_RUN_ATTEMPT'] == '1' and os.environ['RUNNER_ENVIRONMENT'] == 'github-hosted', 'Owned first hosted run required')
    require(os.environ['EXPECTED_SOURCE_PRODUCT_SHA'] == PRODUCT and os.environ['EXPECTED_VALIDATION_SHA'] == VALIDATION, 'Authorization differs')
    product, validation = ROOT / 'image_source', ROOT / 'product'
    require(git(product, 'rev-parse', 'HEAD') == PRODUCT and git(validation, 'rev-parse', 'HEAD') == VALIDATION, 'Wrong checkout')
    for folder in [product, validation]:
        require(not git(folder, 'status', '--porcelain', '--untracked-files=all'), 'Dirty source checkout')
    infra_paths = ['.github/scripts/approval_layout_admission.py', '.github/scripts/approval_layout_manifest.json', '.github/workflows/ag-native-candidate.yml']
    require(git(validation, 'diff', '--name-only', PRODUCT, VALIDATION).splitlines() == infra_paths, 'Native source differs from actual product')
    manifest = json.loads((validation / '.github/scripts/approval_layout_manifest.json').read_text())
    release = ROOT / '.github/release'
    sys.path.insert(0, str(release))
    spec = importlib.util.spec_from_file_location('native_release_gate', release / 'gate.py')
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    lock = json.loads((release / 'release-evidence-lock.json').read_text())
    require(lock['product_sha'] == VALIDATION and lock['native_run_id'] == 43477028469, 'Wrong native evidence lock')
    # The original gate verifies the exact tree used by native CI. The adapter
    # separately proves the functional equivalence of the image source tree.
    os.environ['EXPECTED_PRODUCT_SHA'] = VALIDATION
    native_report = Path(os.environ['RUNNER_TEMP']) / 'validated-native-tree.json'
    gate.execute(lock, execution, validation, native_report)
    gh = gate.GitHub(lock['repository'], os.environ['GH_TOKEN'])
    artifact = next(a for a in lock['artifacts'] if a['name'].startswith('runtime-contract-'))
    raw = gh.download(gh.base + '/actions/artifacts/' + str(artifact['id']) + '/zip')
    archive = gate.archive(raw, artifact['sha256'])
    contract = json.loads(gate.member(archive, 'runtime-contract.json'))
    hashes = {item['path']: hashlib.sha256((product / item['path']).read_bytes()).hexdigest() for item in manifest['files']}
    binding = layout_binding(manifest, contract, git(product, 'diff', '--name-only', BASE, PRODUCT).splitlines(), hashes)
    binding.update(native_run_id=lock['native_run_id'], infrastructure_sha=execution,
                   native_gate_report_sha256=hashlib.sha256(native_report.read_bytes()).hexdigest(),
                   image_built=False, published=False, browser_homologated=False)
    (Path(os.environ['RUNNER_TEMP']) / 'layout-release-gate-report.json').write_text(json.dumps(binding, indent=2) + '\n')
    print(json.dumps(binding))

if __name__ == '__main__':
    main()
