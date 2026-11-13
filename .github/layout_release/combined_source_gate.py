"""Bind the immutable native gate to an explicitly reviewed frontend-only correction."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'product'
REPO = 'ClaudioHideki/jrc-conversas-lab2'
PRODUCT = '98e201efd33e1cf66706c4d51c5383052754cd34'
BASE = 'd68885508f36a8fda2725a3c03d78470e9f9ff70'

def require(value, message):
    if not value:
        raise RuntimeError(message)

def api(path):
    request = urllib.request.Request('https://api.github.com/repos/' + REPO + '/' + path,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

def artifact(run_id, artifact_id, sha, digest):
    run = api('actions/runs/' + str(run_id))
    require(run['head_sha'] == sha and run['status'] == 'completed' and run['conclusion'] == 'success', 'Unapproved evidence run')
    jobs = api('actions/runs/' + str(run_id) + '/jobs?per_page=100')['jobs']
    require(jobs and all(j['conclusion'] == 'success' for j in jobs), 'Evidence jobs incomplete')
    meta = api('actions/artifacts/' + str(artifact_id))
    require(meta['workflow_run']['id'] == run_id and meta['workflow_run']['head_sha'] == sha and not meta['expired'], 'Wrong artifact identity')
    require(meta['digest'] == 'sha256:' + digest, 'Artifact digest changed')
    request = urllib.request.Request(meta['archive_download_url'], headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN']})
    try:
        urllib.request.build_opener(NoRedirect()).open(request, timeout=60)
        raise RuntimeError('Expected signed artifact redirect')
    except urllib.error.HTTPError as response:
        require(response.code == 302, 'Artifact redirect refused')
        url = response.headers['Location']
    require(url.startswith('https://'), 'Insecure artifact transport')
    # Authorization is deliberately absent on the signed object-storage request.
    with urllib.request.urlopen(url, timeout=90) as response:
        raw = response.read(16 * 1024 * 1024 + 1)
    require(len(raw) <= 16 * 1024 * 1024 and hashlib.sha256(raw).hexdigest() == digest, 'Corrupt artifact')
    return zipfile.ZipFile(io.BytesIO(raw))

def validate_frontend(report):
    require(report['success'] is True and report['numTotalTests'] == 2502 and report['numPassedTests'] == 2502, 'Frontend examples missing')
    require(all(report[k] == 0 for k in ['numFailedTests', 'numPendingTests', 'numTodoTests']), 'Frontend failures or pending cases')

def main():
    require(os.environ.get('GITHUB_REPOSITORY') == REPO and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Hosted repository required')
    require(os.environ['GITHUB_SHA'] == os.environ['EXPECTED_EXECUTION_SHA'], 'Wrong infrastructure SHA')
    require(subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD'], text=True).strip() == PRODUCT, 'Wrong product SHA')
    lock = json.loads((ROOT / '.github/layout_release/final-source-lock.json').read_text())
    paths = subprocess.check_output(['git', '-C', str(SOURCE), 'diff', '--name-only', BASE, PRODUCT], text=True).splitlines()
    require(paths == sorted(v['path'] for v in lock['frontend_only_delta']), 'Unvalidated product changes')
    for item in lock['files']:
        require(hashlib.sha256((SOURCE / item['path']).read_bytes()).hexdigest() == item['sha256'], 'Reviewed source hash changed')
    front_sha = '3552bae70a36a56ccd7adc69b0ee7a53896e5c85'
    delta = subprocess.check_output(['git', '-C', str(SOURCE), 'diff', '--name-only', PRODUCT, front_sha], text=True).splitlines()
    require(delta == ['.github/workflows/ag-native-candidate.yml'], 'Frontend validation source differs')
    native_zip = artifact(43494477512, 14069914420, '62327981029b56c27236f4003ec3fc6596310b7b',
                          '90e76c00c991e3a73ac1485a385ccfc33887b68f4cdd815798c3cdcfdf1d5c2c')
    native = json.loads(native_zip.read('layout-release-gate-report.json'))
    require(native['passed'] and native['product_sha'] == BASE and native['native_run_id'] == 43477028469, 'Native gate identity wrong')
    frontend_zip = artifact(43495454717, 14071517660, front_sha,
                            '337e81aeeb49287ed3c30013bcc1eca0e6ee6fbf3740972d417da19cfc048573')
    frontend = json.loads(frontend_zip.read('approvals-vue.json'))
    validate_frontend(frontend)
    require(api('git/ref/heads/codex/approvals-word-layout-20261113')['object']['sha'] == PRODUCT, 'Product branch moved')
    result = {'passed': True, 'product_sha': PRODUCT, 'infrastructure_sha': os.environ['GITHUB_SHA'],
              'native_product_sha': BASE, 'native_validation_sha': native['native_validation_sha'],
              'native_gate_run': 43494477512, 'native_matrix_identities': 36, 'native_matrix_examples': 5572,
              'frontend_run': 43495454717, 'frontend_examples': 2502, 'frontend_only_delta': lock['frontend_only_delta'],
              'image_built': False, 'published': False}
    Path(os.environ['RUNNER_TEMP'], 'combined-source-gate.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result))

if __name__ == '__main__':
    main()
