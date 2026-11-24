"""Verify actual owned Sidekiq receipts; no worker start, retry or provider operation."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

SPEC = 'spec/requests/api/v1/accounts/jrc_contact_center/ending_actual_broker_concurrency_spec.rb'
MODES = {'duplicate_delivery', 'revoked_original_permission', 'deactivated_pending'}
FIELDS = {'source_sha', 'synthetic', 'mode', 'account_id', 'qualification_id', 'original_account_user_id',
          'original_user_id', 'worker_pid', 'owned_queue', 'worker_receipts', 'healthy_worker_before_owned_shutdown',
          'http_egress_blocked_by_test_boundary', 'provider_or_whole_Part1_homologation', 'tasks', 'audits',
          'native_successes', 'outcome_codes', 'actual_database', 'actual_redis_database'}


def positive_id(value):
    return type(value) is int and value > 0


def verify_proof(data, sha, witness_hash):
    assert set(data) == FIELDS
    assert re.fullmatch('[a-f0-9]{40}', sha) and data['source_sha'] == sha
    assert re.fullmatch('[a-f0-9]{64}', witness_hash)
    assert data['synthetic'] is True and data['mode'] in MODES
    for key in ['account_id', 'qualification_id', 'original_account_user_id', 'original_user_id', 'worker_pid']:
        assert positive_id(data[key])
    assert re.fullmatch(r'[a-zA-Z0-9_:.-]*jrc_cc_native_[a-f0-9]{24}', data['owned_queue'])
    assert data['actual_database'] == 'corporate_gratuity_disposable'
    assert type(data['actual_redis_database']) is int and data['actual_redis_database'] == 15
    assert data['healthy_worker_before_owned_shutdown'] is True
    assert data['http_egress_blocked_by_test_boundary'] is True
    assert data['provider_or_whole_Part1_homologation'] is False
    assert type(data['audits']) is int and type(data['native_successes']) is int
    receipts = data['worker_receipts']
    assert isinstance(receipts, list) and receipts
    jids = set()
    for row in receipts:
        assert set(row) == {'jid', 'account_id', 'qualification_id', 'worker_pid', 'source_sha', 'witness_sha256'}
        assert re.fullmatch('[a-f0-9]{24}', row['jid']) and row['jid'] not in jids
        jids.add(row['jid'])
        for key in ['account_id', 'qualification_id', 'worker_pid']:
            assert row[key] == data[key] and positive_id(row[key])
        assert row['source_sha'] == sha and row['witness_sha256'] == witness_hash
    if data['mode'] == 'duplicate_delivery':
        assert len(receipts) >= 2
        assert data['audits'] == data['native_successes'] == 1
        assert len(data['tasks']) == 1 and len(data['tasks'][0]) == 2
        assert positive_id(data['tasks'][0][0]) and data['tasks'][0][1] == data['original_user_id']
        assert data['outcome_codes'] == [['succeeded', 'completed']]
    else:
        assert data['tasks'] == [] and data['audits'] == data['native_successes'] == 0
        code = 'authorization_denied' if data['mode'] == 'revoked_original_permission' else 'deactivated'
        assert data['outcome_codes'] == [['blocked', code]]
    return {'mode': data['mode'], 'account_id': data['account_id'], 'worker_pid': data['worker_pid'],
            'owned_queue': data['owned_queue'], 'worker_deliveries': len(receipts), 'native_successes': data['native_successes']}



def require_complete(rows):
    assert len(rows) == 3 and {row['mode'] for row in rows} == MODES
    assert len({row['account_id'] for row in rows}) == len({row['owned_queue'] for row in rows}) == 3


def main():
    assert os.environ['GITHUB_ACTIONS'] == 'true' and os.environ['RUNNER_ENVIRONMENT'] == 'github-hosted'
    assert os.environ['RAILS_ENV'] == 'test' and os.environ['POSTGRES_HOST'] == '127.0.0.1'
    assert os.environ['POSTGRES_DATABASE'] == 'corporate_gratuity_disposable'
    assert os.environ['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    sha = os.environ['GITHUB_SHA']
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    assert sha == head and re.fullmatch('[a-f0-9]{40}', sha)
    assert Path.cwd().resolve() == Path(os.environ['GITHUB_WORKSPACE']).resolve()
    witness = Path('spec/integration/jrc_contact_center/owned_ending_worker_boot.rb')
    witness_hash = hashlib.sha256(witness.read_bytes()).hexdigest()
    spec = 'spec/requests/api/v1/accounts/jrc_contact_center/ending_actual_broker_concurrency_spec.rb'
    report = json.loads(Path('/tmp/call-center-ending-actual-broker-rspec.json').read_text())
    summary = report['summary']
    assert summary['example_count'] == len(report['examples']) == 3
    assert all(summary[key] == 0 for key in ['failure_count', 'pending_count', 'errors_outside_of_examples_count'])
    assert not report.get('messages')
    assert len({row['full_description'] for row in report['examples']}) == 3
    assert all(row['status'] == 'passed' and row['file_path'].removeprefix('./') == spec for row in report['examples'])
    files = sorted(Path('/tmp').glob('call-center-ending-broker-*.json'))
    assert len(files) == 3
    rows = [verify_proof(json.loads(path.read_text()), sha, witness_hash) for path in files]
    require_complete(rows)
    result = {'source_sha': sha, 'native_examples': 3, 'witness_sha256': witness_hash,
              'proof_hashes': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in files},
              'verified_owned_worker_modes': rows, 'provider_or_whole_Part1_homologation': False}
    Path('/tmp/call-center-ending-actual-broker-verification.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
