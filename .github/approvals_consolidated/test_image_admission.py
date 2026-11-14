import copy
import json
from pathlib import Path
import unittest
import image_admission as gate

class VisualAdmissionTest(unittest.TestCase):
    def setUp(self):
        self.fixture=json.loads((Path(__file__).parent/'visual-test-fixture.json').read_text())

    def check(self):
        gate.visual_valid(self.fixture['report'],self.fixture['browser'],self.fixture['screenshots'])

    def test_actual_nine_case_proof_is_accepted(self): self.check()

    def test_wrong_source_is_denied(self):
        self.fixture['report']['product_sha']='0'*40
        with self.assertRaises(RuntimeError): self.check()

    def test_old_eight_case_proof_is_denied(self):
        self.fixture['browser']['stats']['expected']=8
        with self.assertRaises(RuntimeError): self.check()

    def test_pending_failure_flaky_and_external_errors_are_denied(self):
        original=copy.deepcopy(self.fixture)
        for key in ['skipped','unexpected','flaky']:
            with self.subTest(key=key):
                self.fixture=copy.deepcopy(original);self.fixture['browser']['stats'][key]=1
                with self.assertRaises(RuntimeError): self.check()
        self.fixture=copy.deepcopy(original);self.fixture['browser']['errors']=[{'message':'outside examples'}]
        with self.assertRaises(RuntimeError): self.check()

    def test_missing_or_duplicate_visual_evidence_is_denied(self):
        original=copy.deepcopy(self.fixture)
        self.fixture['screenshots'].pop()
        with self.assertRaises(RuntimeError): self.check()
        self.fixture=original;self.fixture['screenshots'][-1]=self.fixture['screenshots'][0]
        with self.assertRaises(RuntimeError): self.check()

    def test_mocked_application_or_old_assets_are_denied(self):
        original=copy.deepcopy(self.fixture)
        self.fixture['report']['mocked_application']=True
        with self.assertRaises(RuntimeError): self.check()
        self.fixture=original;self.fixture['report']['frontend_heap']['passed']=False
        with self.assertRaises(RuntimeError): self.check()

    def test_reserve_violation_is_denied(self):
        self.fixture['report']['resources']['ram_min']=750*1024**2
        with self.assertRaises(RuntimeError): self.check()

    def test_absent_native_theme_annotations_are_denied(self):
        def remove(suites):
            for suite in suites:
                for spec in suite.get('specs',[]):
                    for test in spec['tests']: test['annotations']=[a for a in test['annotations'] if a['type']!='native-theme']
                remove(suite.get('suites',[]))
        remove(self.fixture['browser']['suites'])
        with self.assertRaises(RuntimeError): self.check()

if __name__=='__main__': unittest.main(verbosity=2)
