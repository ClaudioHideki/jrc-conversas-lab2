import copy
import json
from pathlib import Path
import unittest
import image_admission as gate

class QuickVisualTest(unittest.TestCase):
    def setUp(self):
        self.fixture=json.loads((Path(__file__).parent/'quick-visual-fixture.json').read_text())

    def check(self):gate.quick_visual_valid(self.fixture['report'],self.fixture['browser'],self.fixture['screenshots'])

    def deny(self):
        with self.assertRaises(RuntimeError):self.check()

    def test_exact_thirteen_pass(self):self.check()

    def test_old_product_denied(self):
        self.fixture['report']['product_sha']='2be22e86baecbe75c302bb03208e78e67301c743';self.deny()

    def test_missing_and_duplicate_screenshots(self):
        original=copy.deepcopy(self.fixture)
        self.fixture['screenshots'].pop();self.deny()
        self.fixture=original;self.fixture['screenshots'][-1]=self.fixture['screenshots'][0];self.deny()

    def test_pending_flaky_failed_or_incomplete_counts(self):
        original=copy.deepcopy(self.fixture)
        for key in ['skipped','flaky','unexpected','expected']:
            self.fixture=copy.deepcopy(original);self.fixture['browser']['stats'][key]+=1;self.deny()

    def test_external_error(self):
        self.fixture['browser']['errors']=[{'message':'synthetic external error'}];self.deny()

    def test_mocked_or_unbuilt_assets(self):
        original=copy.deepcopy(self.fixture)
        self.fixture['report']['mocked_application']=True;self.deny()
        self.fixture=original;self.fixture['report']['frontend_heap']['passed']=False;self.deny()

    def test_wrong_heap_or_build_scope(self):
        original=copy.deepcopy(self.fixture)
        self.fixture['report']['frontend_heap']['heap_mib']=2048;self.deny()
        self.fixture=original;self.fixture['report']['frontend_heap']['build_only']=False;self.deny()

    def test_resource_violation(self):
        original=copy.deepcopy(self.fixture)
        for key,value in [('ram_min',750*1024**2),('disk_min',750_000_000)]:
            self.fixture=copy.deepcopy(original);self.fixture['report']['resources'][key]=value;self.deny()

    def test_theme_or_viewport_proof_cannot_be_removed(self):
        for suite in self.fixture['browser']['suites']:
            for spec in suite.get('specs',[]):
                for test in spec['tests']:test['annotations']=[]
        self.deny()

    def test_missing_native_phase(self):
        self.fixture['report']['phases'].pop();self.deny()

if __name__=='__main__':unittest.main(verbosity=2)
