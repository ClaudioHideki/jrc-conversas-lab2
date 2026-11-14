"""Independent exact-main-309 gate. No image, registry, migration or deploy execution."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'product'
PRODUCT = '55da80eb1254aee54ee0f1fb5c42f2be46a98737'
BASE_MAIN = '309a3e04f32ae1ca469fc202f6d1be0f9e50a20a'
REPO = 'ClaudioHideki/jrc-conversas-lab2'
CANDIDATE = 'codex/central-aprovacoes-consolidada-20261114'
sys.path.insert(0, str(ROOT / '.github/release'))
import gate as parser

def require(value, message):
    if not value:
        raise RuntimeError(message)

def client():
    return parser.GitHub(REPO, os.environ['GH_TOKEN'])

def check_refs():
    gh = client()
    require(gh.api('/git/ref/heads/main')['object']['sha'] == BASE_MAIN, 'Main advanced; stop consolidation')
    require(gh.api('/git/ref/heads/' + CANDIDATE)['object']['sha'] == PRODUCT, 'Candidate moved')

def jobs_valid(lock, snapshot):
    all_jobs = snapshot['jobs']
    require(snapshot['total_count'] == len(all_jobs) == 49, 'Incomplete overall jobs')
    skipped = [j for j in all_jobs if j['name'] in ['guarded-candidate-build','guarded-consolidated-image']]
    require({(j['id'],j['name']) for j in skipped} == {(j['id'],j['name']) for j in lock['expected_skipped_image_jobs']}, 'Unexpected image jobs')
    require(all(j['status']=='completed' and j['conclusion']=='skipped' and j['head_sha']==PRODUCT and j['run_attempt']==1 and j['run_id']==lock['native_run_id'] for j in skipped), 'Image executed before admission')
    jobs = [j for j in all_jobs if j not in skipped]
    require(len(jobs) == len(lock['jobs']) == 47, 'Incomplete mandatory jobs')
    require(len({j['id'] for j in jobs}) == len({j['name'] for j in jobs}) == 47, 'Duplicate jobs')
    require({(j['id'], j['name']) for j in jobs} == {(j['id'], j['name']) for j in lock['jobs']}, 'Changed jobs')
    matrix = {}
    for job in jobs:
        require(job['head_sha'] == PRODUCT and job['run_id'] == lock['native_run_id'] and job['run_attempt'] == 1, 'Wrong job identity')
        require(job['status'] == 'completed' and job['conclusion'] == 'success' and job['runner_id'] and job['steps'], 'Unapproved job')
        require(not any(s['conclusion'] in ['failure', 'cancelled', 'timed_out'] for s in job['steps']), 'Failed job step')
        if job['name'].startswith('rails ('):
            identity = parser.logical(job['name'])
            require(identity not in matrix, 'Duplicate logical identity')
            matrix[identity] = job['id']
    require(len(matrix) == 36 and matrix == {r['identity']: r['job_id'] for r in lock['matrix']}, 'Matrix mismatch')

def migration_metadata_valid(report):
    require(report['source_sha'] == PRODUCT and report['production_changed'] is False and report['docker_build_executed'] is False, 'Wrong migration source/isolation')
    require(set(report['schema_paths_passed']) == {'fresh_migrate_and_reexecute', 'populated_main_upgrade_and_reexecute', 'empty_schema_reload'}
            and report['catalog_equivalence_passed'] is True, 'Missing migration scenario')
    upgrade = report['upgrade']
    # Authorized main adds receipts + media to the earlier 36-version ledger.
    require(len(upgrade['required_versions']) == len(set(upgrade['required_versions'])) == 38, 'Wrong consolidated migration count')
    require({'20261111170000', '20261112120000', '20261111150000', '20261112000000'} <= set(upgrade['required_versions']), 'Additional migrations unproved')
    require(len(upgrade['historical_versions']) == 27 and upgrade['preserved_subjects'] == 13, 'Historical/populated subjects missing')
    require(upgrade['existing_versions_preserved'] is True and upgrade['populated_upgrade'] is True
            and upgrade['missing_after'] == [] and upgrade['pending_after'] is False, 'Upgrade failed')
    return report

def migration_valid(z):
    report = migration_metadata_valid(json.loads(parser.member(z, 'ag-migration-audit-result.json')))
    for path, digest in report['sha256'].items():
        require(hashlib.sha256(parser.member(z, Path(path).name)).hexdigest() == digest, 'Schema/catalog digest differs')
    return report

def main():
    require(os.environ['GITHUB_REPOSITORY'] == REPO and os.environ['GITHUB_ACTIONS'] == 'true'
            and os.environ['RUNNER_ENVIRONMENT'] == 'github-hosted', 'Hosted repository required')
    require(os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch' and os.environ['GITHUB_RUN_ATTEMPT'] == '1', 'First manual attempt required')
    infra = os.environ['EXPECTED_EXECUTION_SHA']
    require(os.environ['GITHUB_SHA'] == infra and subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip() == infra, 'Wrong infrastructure SHA')
    require(subprocess.check_output(['git','rev-parse','HEAD'],cwd=SOURCE,text=True).strip() == PRODUCT, 'Wrong product checkout')
    require(not subprocess.check_output(['git','status','--porcelain'],cwd=SOURCE,text=True).strip(), 'Dirty product')
    check_refs()
    lock = json.loads((ROOT / '.github/approvals_consolidated/quality-lock.json').read_text())
    require(lock['product_sha'] == PRODUCT and lock['authorized_main'] == BASE_MAIN and lock['native_run_id'] == 43620872234, 'Wrong evidence lock')
    for path, digest in lock['reviewed_source_hashes'].items():
        require(hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == digest, 'Reviewed source changed: ' + path)
    gh = client()
    run = gh.api('/actions/runs/' + str(lock['native_run_id']))
    require(run['head_sha'] == PRODUCT and run['head_branch'] == lock['native_branch'] and run['path'] == lock['native_workflow']
            and run['run_attempt'] == 1 and run['status'] == 'completed' and run['conclusion'] == 'success', 'Native run not approved')
    jobs_valid(lock, gh.api('/actions/runs/' + str(lock['native_run_id']) + '/attempts/1/jobs?per_page=100'))
    snapshot = gh.api('/actions/runs/' + str(lock['native_run_id']) + '/artifacts?per_page=100')
    require(snapshot['total_count'] == len(snapshot['artifacts']) == len(lock['artifacts']) == 46, 'Artifacts missing')
    expected = {v['id']:v for v in lock['artifacts']}
    require(len(expected) == 46 and {v['id'] for v in snapshot['artifacts']} == set(expected), 'Artifact identity differs')
    verified_reports = []
    matrix = []
    migrations = None
    for meta in snapshot['artifacts']:
        item = expected[meta['id']]
        require(meta['name'] == item['name'] and meta['digest'] == 'sha256:' + item['sha256'] and not meta['expired']
                and meta['workflow_run']['id'] == lock['native_run_id'] and meta['workflow_run']['head_sha'] == PRODUCT, 'Artifact source/digest differs')
        raw = gh.download(meta['archive_download_url'])
        require(hashlib.sha256(raw).hexdigest() == item['sha256'], 'Downloaded artifact corrupted')
        if meta['name'].startswith('ag-guarded-build-'):
            # Its compiled binaries are not inflated; its exact SHA is independently checked.
            continue
        z = parser.archive(raw, item['sha256'])
        for name in z.namelist():
            kind = parser.report_kind(name)
            if kind:
                report_raw = z.read(name)
                count = parser.rspec(json.loads(report_raw)) if kind == 'rspec' else parser.vue(json.loads(report_raw))
                verified_reports.append({'artifact_id':meta['id'],'path':name,'kind':kind,'examples':count,'sha256':hashlib.sha256(report_raw).hexdigest()})
        if any(Path(n).name == 'ag-rspec.json' for n in z.namelist()):
            approved = next(v for v in lock['matrix'] if v['artifact_id'] == meta['id'])
            report_raw = parser.member(z,'ag-rspec.json')
            require(hashlib.sha256(report_raw).hexdigest() == approved['report_sha256'], 'Matrix report changed')
            parser.rspec(json.loads(report_raw), approved['examples'])
            log = gh.download(f'https://api.github.com/repos/{REPO}/actions/jobs/{approved["job_id"]}/logs').decode(errors='replace')
            require(parser.apt(log) == approved['mirror'], 'Signed APT mirror proof changed')
            matrix.append(approved)
        if meta['name'].startswith('ag-migration-admission-'):
            migrations = migration_valid(z)
    require(len(matrix) == 36 and sum(v['examples'] for v in matrix) == lock['matrix_examples'] == 5572, 'Native coverage incomplete')
    canonical = lambda rows: sorted(rows, key=lambda row: (row['artifact_id'], row['path']))
    require(canonical(verified_reports) == canonical(lock['reports']) and migrations is not None, 'Report coverage differs')
    require(next(v['examples'] for v in verified_reports if v['path']=='ag-vue-results.json') == 2505, 'Consolidated frontend missing')
    check_refs()
    result = {'passed':True,'product_sha':PRODUCT,'infrastructure_sha':infra,'authorized_main':BASE_MAIN,
              'native_run':lock['native_run_id'],'matrix_identities':36,'matrix_examples':5572,'frontend_examples':2505,
              'mandatory_jobs':47,'artifacts':46,'reports':len(verified_reports),'required_migrations':38,
              'additional_history_migrations_verified':True,'old_candidate_evidence_reused':False,
              'browser_homologated':False,'image_built_by_this_task':False,'published_by_this_task':False}
    Path(os.environ['RUNNER_TEMP'],'consolidated-quality-gate.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))

if __name__ == '__main__': main()
