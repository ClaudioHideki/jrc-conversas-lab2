import unittest
from jrc_delivery_evidence import verify


class EvidenceTest(unittest.TestCase):
    def test_rspec_rejects_failure_pending_empty_and_outside_errors(self):
        summary = dict(example_count=6, failure_count=0, pending_count=0, errors_outside_of_examples_count=0)
        verify('rspec', {'summary': summary}, 6)
        for key, value in [('failure_count', 1), ('pending_count', 1), ('example_count', 0), ('errors_outside_of_examples_count', 1)]:
            with self.assertRaises(ValueError):
                verify('rspec', {'summary': {**summary, key: value}}, 6)

    def test_vitest_rejects_skipped_todo_empty_failed_and_runner_errors(self):
        result = dict(success=True, numTotalTests=36, numPassedTests=36, numFailedTests=0, numPendingTests=0, numTodoTests=0,
                      numRuntimeErrorTestSuites=0)
        verify('vitest', result, 36)
        for key, value in [('success', False), ('numPassedTests', 35), ('numPendingTests', 1), ('numFailedTests', 1),
                           ('numTodoTests', 1), ('numTotalTests', 0), ('numRuntimeErrorTestSuites', 1)]:
            with self.assertRaises(ValueError):
                verify('vitest', {**result, key: value}, 36)


if __name__ == '__main__':
    unittest.main()
