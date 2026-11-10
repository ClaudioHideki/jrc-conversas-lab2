import unittest

from jrc_ag_native_plan import DATABASES, EXTRA_SPECS, ROOT, SCOPES, plan, shard


class NativePlanGuardsTest(unittest.TestCase):
    def test_committed_signature_api_uses_its_config_based_database_guard(self):
        groups = plan()
        self.assertIn(
            'spec/requests/api/v1/accounts/crm/backoffice_signature_submission_commit_spec.rb',
            groups['jrc_four_domains_schema_admission_test'],
        )

    def test_authority_and_roster_concurrency_keep_their_separate_native_databases(self):
        groups = plan()
        self.assertIn('spec/services/jrc_backoffice/authority_proposals_concurrency_spec.rb',
                      groups['jrc_four_domains_schema_authority_test'])
        self.assertIn('spec/services/jrc_backoffice/signer_rosters_concurrency_spec.rb',
                      groups['jrc_four_domains_schema_test'])

    def test_every_native_spec_is_planned_exactly_once_without_changing_guards(self):
        groups = plan()
        expected = {p.relative_to(ROOT).as_posix() for scope in SCOPES for p in (ROOT / scope).rglob('*_spec.rb')}
        expected.update(EXTRA_SPECS)
        actual = [path for files in groups.values() for path in files]
        self.assertTrue(expected)
        self.assertEqual(set(groups), set(DATABASES))
        self.assertEqual(len(actual), len(set(actual)))
        self.assertEqual(set(actual), expected)

    def test_shards_cover_every_example_source_once_without_excluding_failures(self):
        paths = plan()[DATABASES[0]]
        shards = [shard(paths, index, 6) for index in range(6)]
        actual = [path for part in shards for path in part]
        self.assertTrue(all(shards))
        self.assertEqual(len(actual), len(set(actual)))
        self.assertEqual(set(actual), set(paths))
        for index, count in [(-1, 6), (6, 6), (0, 0)]:
            with self.assertRaises(ValueError):
                shard(paths, index, count)

    def test_repeatable_read_retention_api_uses_committed_fixtures_in_its_own_database(self):
        self.assertIn('spec/requests/api/v1/accounts/relationship/approved_retention_spec.rb',
                      plan()['jrc_ag_retention_native_test'])


if __name__ == '__main__':
    unittest.main()
