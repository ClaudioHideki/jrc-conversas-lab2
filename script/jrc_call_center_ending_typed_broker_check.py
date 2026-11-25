"""Verify real owned typed-worker evidence; never starts or retries a worker."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

SPEC = 'spec/requests/api/v1/accounts/jrc_contact_center/ending_typed_actual_broker_concurrency_spec.rb'
BOOT = 'spec/integration/jrc_contact_center/owned_ending_typed_worker_boot.rb'
MODES = {'duplicate_delivery', 'revoked_original_permission', 'deactivated_pending'}
FIELDS = {'source_sha', 'synthetic', 'mode', 'account_id', 'attempt_id', 'qualification_id',
          'original_account_user_id', 'original_user_id', 'destination_kind', 'operation', 'owned_queue',
          'worker_pid', 'worker_receipts', 'actual_database', 'actual_redis_database', 'producer_backend_pid',
          'healthy_worker_before_owned_shutdown', 'owned_queue_empty_after_worker', 'tasks', 'audits',
          'native_successes', 'outcome_codes', 'http_egress_blocked_by_test_boundary',
          'public_editor_or_provider_or_whole_Part1_homologation'}
RECEIPT_FIELDS = {'jid', 'account_id', 'attempt_id', 'worker_pid', 'source_sha', 'witness_sha256',
                  'postgres_backend_pid', 'database', 'redis_database'}


def positive(value):
    return type(value) is int and value > 0


def verify_proof(data, sha, witness_hash):
    assert set(data) == FIELDS
    assert re.fullmatch('[a-f0-9]{40}', sha) and data['source_sha'] == sha
    assert re.fullmatch('[a-f0-9]{64}', witness_hash)
    assert data['synthetic'] is True and data['mode'] in MODES
    for key in ['account_id', 'attempt_id', 'qualification_id', 'original_account_user_id',
                'original_user_id', 'worker_pid', 'producer_backend_pid']:
        assert positive(data[key])
    assert data['destination_kind'] == 'project_task' and data['operation'] == 'create_task'
    assert re.fullmatch('[a-zA-Z0-9_:.-]*jrc_cc_typed_native_[a-f0-9]{24}', data['owned_queue'])
    assert data['actual_database'] == 'corporate_gratuity_disposable'
    assert type(data['actual_redis_database']) is int and data['actual_redis_database'] == 15
    for key in ['healthy_worker_before_owned_shutdown', 'owned_queue_empty_after_worker', 'http_egress_blocked_by_test_boundary']:
        assert data[key] is True
    assert data['public_editor_or_provider_or_whole_Part1_homologation'] is False
    assert type(data['audits']) is int and type(data['native_successes']) is int
    receipts = data['worker_receipts']
    assert isinstance(receipts, list) and receipts
    jids = set()
    for row in receipts:
        assert set(row) == RECEIPT_FIELDS
        assert re.fullmatch('[a-f0-9]{24}', row['jid']) and row['jid'] not in jids
        jids.add(row['jid'])
        for key in ['account_id', 'attempt_id', 'worker_pid']:
            assert row[key] == data[key] and positive(row[key])
        assert row['source_sha'] == sha and row['witness_sha256'] == witness_hash
        assert positive(row['postgres_backend_pid']) and row['postgres_backend_pid'] != data['producer_backend_pid']
        assert row['database'] == data['actual_database']
        assert type(row['redis_database']) is int and row['redis_database'] == 15
    if data['mode'] == 'duplicate_delivery':
        assert len(receipts) >= 2 and data['audits'] == data['native_successes'] == 1
        assert len(data['tasks']) == 1 and len(data['tasks'][0]) == 2
        assert all(positive(value) for value in data['tasks'][0]) and data['tasks'][0][1] == data['original_user_id']
        assert data['outcome_codes'] == [['succeeded', 'completed']]
    else:
        assert data['tasks'] == [] and data['audits'] == data['native_successes'] == 0
        expected = 'authorization_denied' if data['mode'] == 'revoked_original_permission' else 'deactivated'
        assert data['outcome_codes'] == [['blocked', expected]]
    return {'mode': data['mode'], 'account_id': data['account_id'], 'attempt_id': data['attempt_id'],
            'worker_pid': data['worker_pid'], 'owned_queue': data['owned_queue'],
            'worker_deliveries': len(receipts), 'native_successes': data['native_successes']}


def require_complete(rows):
    assert len(rows) == 3 and {row['mode'] for row in rows} == MODES
    for key in ['account_id', 'attempt_id', 'owned_queue']:
        assert len({row[key] for row in rows}) == 3


def main():
    assert os.environ['GITHUB_ACTIONS'] == 'true' and os.environ['RUNNER_ENVIRONMENT'] == 'github-hosted'
    assert os.environ['RAILS_ENV'] == 'test' and os.environ['POSTGRES_HOST'] == '127.0.0.1'
    assert os.environ['POSTGRES_DATABASE'] == 'corporate_gratuity_disposable'
    assert os.environ['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    sha = os.environ['GITHUB_SHA']
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == sha
    assert Path.cwd().resolve() == Path(os.environ['GITHUB_WORKSPACE']).resolve()
    witness_hash = hashlib.sha256(Path(BOOT).read_bytes()).hexdigest()
    report = json.loads(Path('/tmp/call-center-ending-typed-actual-broker-rspec.json').read_text())
    summary = report['summary']
    assert type(summary['example_count']) is int and summary['example_count'] == len(report['examples']) == 3
    assert all(type(summary[key]) is int and summary[key] == 0
               for key in ['failure_count', 'pending_count', 'errors_outside_of_examples_count'])
    assert not report.get('messages')
    assert len({row['full_description'] for row in report['examples']}) == 3
    assert all(row['status'] == 'passed' and row['file_path'].removeprefix('./') == SPEC for row in report['examples'])
    files = sorted(Path('/tmp').glob('call-center-ending-typed-broker-*.json'))
    assert len(files) == 3
    rows = []
    for path in files:
        proof = json.loads(path.read_text())
        assert path.stem.endswith(proof['owned_queue'][-24:])
        rows.append(verify_proof(proof, sha, witness_hash))
    require_complete(rows)
    result = {'source_sha': sha, 'native_examples': 3, 'witness_sha256': witness_hash,
              'spec_sha256': hashlib.sha256(Path(SPEC).read_bytes()).hexdigest(),
              'proof_hashes': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in files},
              'verified_owned_worker_modes': rows, 'public_editor_or_provider_or_whole_Part1_homologation': False}
    Path('/tmp/call-center-ending-typed-actual-broker-verification.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
