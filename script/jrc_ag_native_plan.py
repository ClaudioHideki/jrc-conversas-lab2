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
DATABASES = [
    'jrc_rel_v2_candidate_test', 'jrc_four_domains_schema_admission_test',
    'jrc_rel_sd_candidate_test', 'jrc_jornada_candidate_test',
    'jrc_four_domains_schema_authority_test', 'jrc_four_domains_schema_test',
]


def plan():
    groups = {database: [] for database in DATABASES}
    paths = sorted({p for scope in SCOPES for p in (ROOT / scope).rglob('*_spec.rb')})
    for path in paths:
        text = path.read_text(encoding='utf-8')
        has_database_guard = any(token in text for token in (
            'POSTGRES_DATABASE', 'connection_db_config', 'config.database', 'current_database',
        ))
        guarded = set(re.findall(r'jrc_[a-z0-9_]+_test', text)) if has_database_guard else set()
        database = next((name for name in DATABASES if name in guarded), None)
        if guarded and database is None:
            raise ValueError(f'Unreviewed synthetic database guard: {path.relative_to(ROOT)}')
        groups[database or DATABASES[0]].append(path.relative_to(ROOT).as_posix())
    assert sum(map(len, groups.values())) == len(paths) and paths
    return groups


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', choices=DATABASES)
    parser.add_argument('--paths', action='store_true')
    args = parser.parse_args()
    groups = plan()
    if args.paths:
        if not args.database:
            parser.error('--paths requires --database')
        print('\n'.join(groups[args.database]))
    else:
        print(json.dumps({'executed': False, 'groups': groups}, indent=2))
