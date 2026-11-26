"""Pure verifier tests; no Ruby, CI, credentials or application startup."""
import copy
import unittest

from jrc_call_center_lint_server_probe import FILE, report_signature, require_parity


class LinterServerParity(unittest.TestCase):
    def report(self):
        return {'metadata': {'rubocop_version': '1.75.6'},
                'summary': {'inspected_file_count': 1, 'target_file_count': 1, 'offense_count': 1},
                'files': [{'path': FILE, 'offenses': [{'cop_name': 'Synthetic/VerifierOnly',
                                                     'message': 'synthetic verifier fixture', 'location': {'line': 7}}]}]}

    def test_identical_failures_are_compared_not_discarded(self):
        signature = report_signature(self.report(), 1)
        require_parity(signature, copy.deepcopy(signature))
        self.assertEqual(signature['offenses'], 1)

    def test_changed_offense_or_location_fails_parity(self):
        original = report_signature(self.report(), 1)
        changed = self.report()
        changed['files'][0]['offenses'][0]['location']['line'] = 8
        with self.assertRaises(AssertionError):
            require_parity(original, report_signature(changed, 1))

    def test_changed_exit_status_fails_parity(self):
        with self.assertRaises(AssertionError):
            require_parity(report_signature(self.report(), 1), report_signature(self.report(), 0))

    def test_missing_inspected_file_is_not_success(self):
        report = self.report()
        report['files'] = []
        with self.assertRaises(AssertionError):
            report_signature(report, 0)

    def test_wrong_linter_version_or_internal_error_is_rejected(self):
        report = self.report()
        report['metadata']['rubocop_version'] = '0.0.0'
        with self.assertRaises(AssertionError):
            report_signature(report, 0)
        with self.assertRaises(AssertionError):
            report_signature(self.report(), 2)


if __name__ == '__main__':
    unittest.main()
