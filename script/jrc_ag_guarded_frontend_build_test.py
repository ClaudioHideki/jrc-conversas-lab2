import unittest
from unittest.mock import patch

from jrc_ag_guarded_frontend_build import authorize, resource_reason, node_heap_mib, vite_output_environment, START_RAM, START_DISK, STOP_RAM, STOP_DISK, BRANCH
from pathlib import Path


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

    def test_delivery_candidate_only_accepts_first_attempt_push_or_manual_on_hosted_linux(self):
        candidate = {**self.env, 'GITHUB_REF': 'refs/heads/codex/whatsapp-delivery-reliability-20261116'}
        with patch('jrc_ag_guarded_frontend_build.sys.platform', 'linux'):
            for event in ['push', 'workflow_dispatch']:
                authorize({**candidate, 'GITHUB_EVENT_NAME': event}, self.sha)
            for key, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_RUN_ATTEMPT', '2'),
                               ('GITHUB_REF', 'refs/heads/main'), ('RUNNER_ENVIRONMENT', 'self-hosted')]:
                with self.assertRaises(RuntimeError):
                    authorize({**candidate, key: value}, self.sha)

    def test_receipt_projection_requires_exact_manual_candidate_and_sha(self):
        for ref in ['refs/heads/codex/projecao-recibos-20261128', 'refs/heads/codex/recibo-direto-sem-vinculo-20261128',
                    'refs/heads/codex/obrigacao-terminal-e-contexto-20261128']:
            with self.subTest(ref=ref):
                self.check_receipt_projection_manual_only(ref)

    def check_receipt_projection_manual_only(self, ref):
        candidate = {**self.env, 'GITHUB_REF': ref}
        with patch('jrc_ag_guarded_frontend_build.sys.platform', 'linux'):
            authorize(candidate, self.sha)
            for key, value in [('GITHUB_EVENT_NAME', 'push'), ('GITHUB_EVENT_NAME', 'pull_request'),
                               ('GITHUB_REF', ref + '-other'), ('GITHUB_REF', ref.replace('heads/', 'tags/')),
                               ('GITHUB_RUN_ATTEMPT', '2'), ('RUNNER_ENVIRONMENT', 'self-hosted'),
                               ('GITHUB_SHA', 'b' * 40), ('JRC_AG_AUTHORIZED_BUILD_SHA', 'b' * 40)]:
                with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                    authorize({**candidate, key: value}, self.sha)

    def test_delivery_admission_retains_eight_gib_of_available_ram(self):
        self.assertGreaterEqual(START_RAM, 8 * 1024 ** 3)

    def test_heap_is_bounded_by_observed_ram_with_a_non_heap_reserve(self):
        gib = 1024 ** 3
        for available in [5 * gib, 6 * gib]:
            with self.assertRaises(RuntimeError):
                node_heap_mib(available)
        self.assertEqual(node_heap_mib(8 * gib), 6144)
        self.assertEqual(node_heap_mib(32 * gib), 6144)
        with self.assertRaises(RuntimeError):
            node_heap_mib(5 * gib - 1)

    def test_actual_ruby_plugin_receives_the_owned_output_directory(self):
        output = Path('owned-runner-output').resolve() / 'frontend'
        env = vite_output_environment(output)
        self.assertEqual(Path(env['VITE_RUBY_PUBLIC_DIR']) / env['VITE_RUBY_PUBLIC_OUTPUT_DIR'], output)
        self.assertEqual(env['VITE_RUBY_PUBLIC_OUTPUT_DIR'], 'frontend')


if __name__ == '__main__':
    unittest.main()
