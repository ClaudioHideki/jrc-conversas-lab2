import unittest
from unittest.mock import patch

from jrc_ag_guarded_frontend_build import authorize, resource_reason, START_RAM, START_DISK, STOP_RAM, STOP_DISK, BRANCH


class BuildAdmissionTest(unittest.TestCase):
    def setUp(self):
        self.sha = 'a' * 40
        self.env = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_REF': BRANCH,
                    'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_RUN_ATTEMPT': '1',
                    'GITHUB_SHA': self.sha, 'JRC_AG_AUTHORIZED_BUILD_SHA': self.sha}

    def test_start_never_lowers_the_explicit_resource_limits(self):
        self.assertIsNone(resource_reason(START_DISK, START_RAM, starting=True))
        self.assertIsNotNone(resource_reason(START_DISK - 1, START_RAM, starting=True))
        self.assertIsNotNone(resource_reason(START_DISK, START_RAM - 1, starting=True))

    def test_exact_safety_floor_also_stops_the_build(self):
        for value in [STOP_DISK - 1, STOP_DISK]:
            self.assertEqual(resource_reason(value, START_RAM), 'disk_reserve_reached')
        for value in [STOP_RAM - 1, STOP_RAM]:
            self.assertEqual(resource_reason(START_DISK, value), 'physical_ram_reserve_reached')
        self.assertIsNone(resource_reason(STOP_DISK + 1, STOP_RAM + 1))

    def test_only_exact_manual_first_attempt_can_be_admitted(self):
        with patch('jrc_ag_guarded_frontend_build.sys.platform', 'linux'):
            authorize(self.env, self.sha)
            for key, value in [('GITHUB_EVENT_NAME', 'push'), ('GITHUB_RUN_ATTEMPT', '2'),
                               ('GITHUB_REF', 'refs/heads/main'), ('RUNNER_ENVIRONMENT', 'self-hosted'),
                               ('JRC_AG_AUTHORIZED_BUILD_SHA', ''), ('GITHUB_SHA', 'b' * 40)]:
                with self.assertRaises(RuntimeError):
                    authorize({**self.env, key: value}, self.sha)

    def test_cannot_execute_on_the_protected_windows_host(self):
        with patch('jrc_ag_guarded_frontend_build.sys.platform', 'win32'):
            with self.assertRaises(RuntimeError):
                authorize(self.env, self.sha)

    def test_exact_history_consolidation_branch_keeps_all_existing_guards(self):
        candidate = {**self.env, 'GITHUB_REF': 'refs/heads/codex/whatsapp-history-order-20261111'}
        with patch('jrc_ag_guarded_frontend_build.sys.platform', 'linux'):
            authorize(candidate, self.sha)
            with self.assertRaises(RuntimeError):
                authorize({**candidate, 'GITHUB_SHA': 'b' * 40}, self.sha)


if __name__ == '__main__':
    unittest.main()
