import json
import os
from pathlib import Path
import unittest
import combined_source_gate as gate

class FrontendEvidenceDenials(unittest.TestCase):
    def setUp(self):
        self.report = {'success': True, 'numTotalTests': 2502, 'numPassedTests': 2502,
            'numFailedTests': 0, 'numPendingTests': 0, 'numTodoTests': 0,
            'numFailedTestSuites': 0, 'numPendingTestSuites': 0,
            'testResults': [{'status': 'passed', 'message': '', 'assertionResults': [{'status': 'passed'} for _ in range(2502)]}]}
    def test_complete_evidence(self):
        gate.validate_frontend(self.report)
    def test_failed_example(self):
        self.report['numFailedTests'] = 1
        with self.assertRaises(RuntimeError): gate.validate_frontend(self.report)
    def test_pending_example(self):
        self.report['numPendingTests'] = 1
        with self.assertRaises(RuntimeError): gate.validate_frontend(self.report)
    def test_empty_assertions(self):
        self.report['testResults'][0]['assertionResults'] = []
        with self.assertRaises(RuntimeError): gate.validate_frontend(self.report)
    def test_file_error(self):
        self.report['testResults'][0]['message'] = 'Synthetic initialization failure'
        with self.assertRaises(RuntimeError): gate.validate_frontend(self.report)
    def test_false_counter(self):
        self.report['numFailedTests'] = False
        with self.assertRaises(RuntimeError): gate.validate_frontend(self.report)
    def test_unsuccessful_report(self):
        self.report['success'] = False
        with self.assertRaises(RuntimeError): gate.validate_frontend(self.report)
    def test_skipped_assertion(self):
        self.report['testResults'][0]['assertionResults'][0]['status'] = 'pending'
        with self.assertRaises(RuntimeError): gate.validate_frontend(self.report)

if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(FrontendEvidenceDenials)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    Path(os.environ['RUNNER_TEMP'], 'combined-source-denial-tests.json').write_text(json.dumps({
        'passed': result.wasSuccessful(), 'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors), 'skipped': len(result.skipped)}))
    raise SystemExit(0 if result.wasSuccessful() else 1)
