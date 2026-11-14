"""Preserve the complete legacy RSpec inventory while routing guarded fixtures."""
import argparse
import json
from pathlib import Path
from jrc_ag_native_plan import plan as native_plan

ROOT = Path(__file__).resolve().parent.parent
SCOPES = ['spec/services/jrc_crm', 'spec/requests/api/v1/accounts/crm',
          'spec/services/jrc_approvals', 'spec/requests/api/v1/accounts/jrc_approvals',
          'spec/models/jrc_service_desk', 'spec/policies/jrc_service_desk',
          'spec/services/jrc_service_desk', 'spec/requests/api/v1/accounts/jrc_service_desk']
ROUTES = {
    'current': ['spec/services/jrc_crm/nexora_end_to_end_spec.rb',
                'spec/requests/api/v1/accounts/crm/backoffice_authorities_spec.rb',
                'spec/requests/api/v1/accounts/crm/backoffice_completion_dossiers_spec.rb',
                'spec/requests/api/v1/accounts/crm/backoffice_signature_evidence_spec.rb'],
    'submission': ['spec/requests/api/v1/accounts/crm/backoffice_signature_history_spec.rb',
                   'spec/requests/api/v1/accounts/crm/backoffice_signature_submission_commit_spec.rb',
                   'spec/requests/api/v1/accounts/crm/backoffice_signature_submission_spec.rb',
                   'spec/requests/api/v1/accounts/crm/backoffice_version_directory_access_spec.rb'],
}


def inventory():
    return sorted({path.relative_to(ROOT).as_posix() for scope in SCOPES
                   for path in (ROOT / scope).rglob('*_spec.rb')})


def partition(paths, routes=ROUTES):
    routed = [path for group in routes.values() for path in group]
    if not paths or len(paths) != len(set(paths)) or len(routed) != len(set(routed)):
        raise ValueError('Empty or duplicated native test inventory')
    if not set(routed).issubset(paths):
        raise ValueError('Reviewed guarded fixture missing from the original inventory')
    return {'legacy': [path for path in paths if path not in routed], **routes}


def verify_native_routes():
    native = {path: database for database, paths in native_plan().items() for path in paths}
    for group, database in [('current', 'jrc_rel_v2_candidate_test'),
                            ('submission', 'jrc_four_domains_schema_admission_test')]:
        if any(native.get(path) != database for path in ROUTES[group]):
            raise ValueError('Guarded fixture differs from the reviewed native routing')


def merge_core(paths):
    if len(paths) != 3:
        raise ValueError('All three core partitions are required')
    examples = []
    for path in paths:
        result = json.loads(Path(path).read_text(encoding='utf8'))
        summary = result['summary']
        rows = result['examples']
        if not rows or summary['example_count'] != len(rows):
            raise ValueError('Empty or inconsistent RSpec partition')
        if any(summary[key] != 0 for key in ('failure_count', 'pending_count', 'errors_outside_of_examples_count')):
            raise ValueError('Failed, pending or invalid RSpec partition')
        if any(row['status'] != 'passed' for row in rows):
            raise ValueError('Every partition example must pass')
        examples.extend(rows)
    identities = [row['id'] for row in examples]
    if not examples or len(set(identities)) != len(identities):
        raise ValueError('Empty or duplicated RSpec execution')
    return {'examples': examples, 'summary': {'example_count': len(examples), 'failure_count': 0,
            'pending_count': 0, 'errors_outside_of_examples_count': 0}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', choices=['legacy', *ROUTES])
    parser.add_argument('--merge-core', nargs='+')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.merge_core:
        if not args.output or args.group:
            parser.error('--merge-core requires --output and cannot select a group')
        args.output.write_text(json.dumps(merge_core(args.merge_core)), encoding='utf8')
    elif args.group:
        verify_native_routes()
        print('\n'.join(partition(inventory())[args.group]))
    else:
        verify_native_routes()
        print(json.dumps(partition(inventory()), indent=2))
