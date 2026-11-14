"""Independent native + nine real Chrome proofs before a local-only runner image."""
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.github/approvals_consolidated'))
import quality_gate as native
require = native.require


def visual_valid(report, browser, names):
    require(report['passed'] is True and report['product_sha'] == native.PRODUCT
            and report['image_built'] is False and report['mocked_application'] is False, 'Wrong visual source or failed acceptance')
    stats = browser['stats']
    require(stats['expected'] == 9 and all(stats[k] == 0 for k in ['unexpected','skipped','flaky'])
            and browser['errors'] == [], 'Incomplete browser acceptance')
    def cases(suites):
        for suite in suites:
            for spec in suite.get('specs',[]):
                for test in spec['tests']:
                    yield test
            yield from cases(suite.get('suites',[]))
    tests = list(cases(browser['suites']))
    require(len(tests)==9 and all(t['status']=='expected' and len(t['results'])==1
            and t['results'][0]['status']=='passed' and t['results'][0]['errors']==[]
            and t['results'][0]['retry']==0 for t in tests), 'Failed, retried or missing Chrome scenario')
    expected = {mode+'-'+screen+'.png' for mode in ['desktop-light','desktop-dark','mobile-light','mobile-dark']
                for screen in ['inbox','detail','confirmation','rule-summary','simulation','delegation','adjustment','history']}
    expected |= {'desktop-real-conflict.png','desktop-empty.png','desktop-denied-profile.png'}
    require(set(names)==expected and len(names)==35, 'Visual evidence incomplete')
    themes=[json.loads(a['description']) for t in tests for a in t['annotations'] if a['type']=='native-theme']
    require(len(themes)==32 and {a['screenshot'] for a in themes}==expected-{'desktop-real-conflict.png','desktop-empty.png','desktop-denied-profile.png'},
            'Native effective theme evidence absent')
    for item in themes:
        dark='-dark-' in item['screenshot']
        require(item['body_dark'] is dark and item['color_scheme']==('dark' if dark else 'light')
                and item['stored_preference']==('dark' if dark else 'light')
                and item['viewport']==(390 if item['screenshot'].startswith('mobile-') else 1440), 'Artificial or wrong theme/viewport')
    require({p['name'] for p in report['phases']} >= {'isolated-database','isolated-schema','fresh-frontend-assets','synthetic-fixture','native-chrome'}
            and all(p['exit_code']==0 for p in report['phases']), 'Native runtime phase failed')
    require(report['frontend_heap']['passed'] is True and report['frontend_heap']['heap_mib']==6144
            and report['frontend_heap']['build_only'] is True, 'Actual guarded assets absent')
    r = report['resources']
    require(r['initial']['ram_available']>=8*1024**3 and r['initial']['disk_free']>=3*1024**3
            and r['ram_min']>750*1024**2 and r['disk_min']>750_000_000, 'Acceptance resource guard failed')
    require(any(a['path'].endswith('.css') for a in report['assets'])
            and any(a['path'].endswith('.js') for a in report['assets']), 'Actual CSS/JS missing')


def main():
    lock=json.loads((ROOT/'.github/approvals_consolidated/image-lock.json').read_text())
    require(lock['product_sha']==native.PRODUCT and os.environ['EXPECTED_PRODUCT_SHA']==native.PRODUCT
            and os.environ['AUTHORIZED_BUILD_SHA']==native.PRODUCT, 'Unauthorized image product')
    require(os.environ['EXPECTED_APPROVED_SHA']==lock['visual_infrastructure_sha'], 'Wrong accepted Chrome infrastructure')
    for path,digest in lock['infrastructure_hashes'].items():
        require(hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,'Unreviewed image infrastructure: '+path)
    # Re-download and verify all native report and APT proofs on this same product.
    native.main()
    gh=native.client()
    run=gh.api('/actions/runs/'+str(lock['visual_run_id']))
    require(run['head_sha']==lock['visual_infrastructure_sha'] and run['head_branch']==lock['visual_branch']
            and run['run_attempt']==1 and run['status']=='completed' and run['conclusion']=='success', 'Visual run not approved')
    jobs=gh.api('/actions/runs/'+str(run['id'])+'/attempts/1/jobs?per_page=100')
    require(jobs['total_count']==len(jobs['jobs'])==2 and {j['name'] for j in jobs['jobs']}=={'source-gate','native-visual'},'Unexpected visual jobs')
    require(all(j['head_sha']==run['head_sha'] and j['run_attempt']==1 and j['conclusion']=='success'
                and j['runner_id'] and j['steps'] and not any(s['conclusion'] in ['failure','cancelled','timed_out'] for s in j['steps']) for j in jobs['jobs']), 'Visual job not approved')
    verified=[]
    for item in lock['visual_artifacts']:
        meta=gh.api('/actions/artifacts/'+str(item['id']))
        require(meta['name']==item['name'] and meta['workflow_run']['id']==run['id']
                and meta['workflow_run']['head_sha']==run['head_sha'] and not meta['expired']
                and meta['digest']=='sha256:'+item['sha256'],'Wrong visual artifact identity')
        z=native.parser.archive(gh.download(meta['archive_download_url']),item['sha256'])
        if any(Path(n).name=='native-visual-result.json' for n in z.namelist()):
            report=json.loads(native.parser.member(z,'native-visual-result.json'))
            require(report['infrastructure_sha']==run['head_sha'],'Visual infrastructure differs')
            browser=json.loads(native.parser.member(z,'playwright-results.json'))
            visual_valid(report,browser,[Path(n).name for n in z.namelist() if n.endswith('.png')])
            for n,digest in item['members'].items():
                require(hashlib.sha256(z.read(n)).hexdigest()==digest,'Visual member corrupted')
            verified.append('native-visual')
        elif any(Path(n).name=='consolidated-quality-gate.json' for n in z.namelist()):
            report=json.loads(native.parser.member(z,'consolidated-quality-gate.json'))
            require(report['passed'] is True and report['product_sha']==native.PRODUCT
                    and report['infrastructure_sha']==run['head_sha'] and report['matrix_identities']==36
                    and report['matrix_examples']==5572 and report['mandatory_jobs']==47,'Independent native gate incomplete')
            verified.append('source-gate')
    require(sorted(verified)==['native-visual','source-gate'],'Both independent proofs required')
    native.check_refs()
    result={'passed':True,'product_sha':native.PRODUCT,'execution_sha':os.environ['GITHUB_SHA'],
            'visual_run':run['id'],'visual_infrastructure_sha':run['head_sha'],'native_run':lock['native_run_id'],
            'matrix_identities':36,'browser_scenarios':9,'screenshots':35,'registry_publication':False,'deploy':False}
    Path(os.environ['RUNNER_TEMP'],'image-admission-'+sys.argv[1]+'.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))

if __name__=='__main__':
    require(sys.argv[1:] in [['prepare'],['build']],'Explicit admission stage required')
    main()
