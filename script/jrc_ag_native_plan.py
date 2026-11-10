"""Read-only RSpec plan. No Ruby, database, dependency install or network call."""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCOPES = [
    'spec/services/jrc_crm', 'spec/services/jrc_customers',
    'spec/services/jrc_relationship', 'spec/services/jrc_backoffice',
    'spec/services/jrc_approvals', 'spec/requests/api/v1/accounts/crm',
    'spec/requests/api/v1/accounts/customers', 'spec/requests/api/v1/accounts/relationship',
    'spec/requests/api/v1/accounts/jrc_approvals', 'spec/models/jrc_relationship',
    'spec/models/jrc_backoffice', 'spec/jobs/jrc_backoffice',
]
EXTRA_SPECS = [
    'spec/services/jrc_service_desk/create_ticket_service_spec.rb',
    'spec/services/jrc_service_desk/internal_intake_integration_spec.rb',
    'spec/services/jrc_service_desk/assignment_eligibility_spec.rb',
    'spec/requests/api/v1/accounts/jrc_service_desk/operations_spec.rb',
    'spec/requests/requester_portal/phase_one_spec.rb',
    'spec/requests/requester_portal/protected_attachment_owners_spec.rb',
    'spec/listeners/action_cable_listener_spec.rb',
    'spec/enterprise/listeners/action_cable_listener_spec.rb',
    'spec/models/notification_spec.rb',
    'spec/services/jrc_nico/operational_access_authentication_spec.rb',
    'spec/services/jrc_nico/domain_access_relationship_sla_spec.rb',
    'spec/services/jrc_nico/context_builder_spec.rb',
    'spec/services/jrc_nico/domain_actions_spec.rb',
    'spec/services/jrc_flows/ownership_identity_spec.rb',
    'spec/requests/api/v1/accounts/jrc_operations/project_individual_permissions_spec.rb',
]

EXCLUSIVE_SPECS = {
    'signing_identity': {'database': 'jrc_rel_v2_candidate_test', 'path': 'spec/services/jrc_customers/signing_identity_upgrade_spec.rb'},
    'document_scan': {'database': 'jrc_rel_v2_candidate_test', 'path': 'spec/services/jrc_backoffice/document_scan_upgrade_spec.rb'},
    'contract_version': {'database': 'jrc_rel_v2_candidate_test', 'path': 'spec/services/jrc_backoffice/contract_version_upgrade_spec.rb'},
    'signature_integration': {'database': 'jrc_rel_v2_candidate_test', 'path': 'spec/services/jrc_backoffice/signature_integration_upgrade_spec.rb'},
    'signature_connection': {'database': 'jrc_rel_v2_candidate_test', 'path': 'spec/services/jrc_backoffice/signature_connection_upgrade_spec.rb'},
    'reviewed_operations': {'database': 'jrc_jornada_candidate_test', 'path': 'spec/services/jrc_relationship/reviewed_operations_upgrade_spec.rb'},
}

DATABASES = [
    'jrc_rel_v2_candidate_test', 'jrc_four_domains_schema_admission_test',
    'jrc_rel_sd_candidate_test', 'jrc_jornada_candidate_test',
    'jrc_four_domains_schema_authority_test', 'jrc_four_domains_schema_test',
    'jrc_ag_retention_native_test',
]


def plan():
    groups = {database: [] for database in DATABASES}
    paths = sorted({p for scope in SCOPES for p in (ROOT / scope).rglob('*_spec.rb')} | {ROOT / p for p in EXTRA_SPECS})
    exclusive_paths = {entry['path'] for entry in EXCLUSIVE_SPECS.values()}
    for path in paths:
        if path.relative_to(ROOT).as_posix() in exclusive_paths:
            continue
        text = path.read_text(encoding='utf-8')
        inherited_concurrency = ':sd_concurrency' in text or 'JrcServiceDeskConcurrency' in text
        has_database_guard = any(token in text for token in (
            'POSTGRES_DATABASE', 'connection_db_config', 'config.database', 'current_database',
        ))
        guarded = set(re.findall(r'jrc_[a-z0-9_]+_test', text)) if has_database_guard else set()
        database = next((name for name in DATABASES if name in guarded), None)
        if database is None and inherited_concurrency:
            database = 'jrc_rel_sd_candidate_test'
        if guarded and database is None:
            raise ValueError(f'Unreviewed synthetic database guard: {path.relative_to(ROOT)}')
        groups[database or DATABASES[0]].append(path.relative_to(ROOT).as_posix())
    assert sum(map(len, groups.values())) == len(paths) - len(exclusive_paths) and paths
    return groups


def shard(paths, index, count):
    if count < 1 or not 0 <= index < count:
        raise ValueError('Invalid native test shard')
    return paths[index::count]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', choices=DATABASES)
    parser.add_argument('--paths', action='store_true')
    parser.add_argument('--exclusive', choices=['', *EXCLUSIVE_SPECS], default='')
    parser.add_argument('--shard-index', type=int, default=0)
    parser.add_argument('--shard-count', type=int, default=1)
    args = parser.parse_args()
    groups = plan()
    if args.shard_count < 1 or not 0 <= args.shard_index < args.shard_count:
        parser.error('Invalid native test shard')
    if args.paths:
        if not args.database:
            parser.error('--paths requires --database')
        if args.exclusive:
            exclusive = EXCLUSIVE_SPECS[args.exclusive]
            if exclusive['database'] != args.database or (args.shard_index, args.shard_count) != (0, 1):
                parser.error('Exclusive native fixture does not match its dedicated service')
            print(exclusive['path'])
        else:
            print('\n'.join(shard(groups[args.database], args.shard_index, args.shard_count)))
    else:
        print(json.dumps({'executed': False, 'groups': groups, 'exclusive_groups': EXCLUSIVE_SPECS}, indent=2))
