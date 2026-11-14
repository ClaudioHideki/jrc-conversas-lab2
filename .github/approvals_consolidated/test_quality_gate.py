import copy
import json
import os
from pathlib import Path
import unittest
import quality_gate as gate

class ConsolidatedDenials(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads((Path(__file__).parent / 'quality-lock.json').read_text())
        self.snapshot = {'total_count':49, 'jobs':[{
            **job, 'head_sha':gate.PRODUCT, 'run_id':self.lock['native_run_id'], 'run_attempt':1,
            'status':'completed','conclusion':'success','runner_id':1,'steps':[{'conclusion':'success'}]
        } for job in self.lock['jobs']]}
        self.snapshot['jobs'] += [{**j, 'head_sha':gate.PRODUCT,'run_id':self.lock['native_run_id'],'run_attempt':1,'status':'completed','conclusion':'skipped','runner_id':None,'steps':[]} for j in self.lock['expected_skipped_image_jobs']]

    def test_exact_positive_snapshot(self):
        gate.jobs_valid(self.lock, self.snapshot)

    def test_out_of_order_snapshot_is_valid(self):
        self.snapshot['jobs'].reverse()
        gate.jobs_valid(self.lock, self.snapshot)

    def test_missing_job_denied(self):
        self.snapshot['jobs'].pop()
        with self.assertRaises(RuntimeError): gate.jobs_valid(self.lock, self.snapshot)

    def test_duplicate_job_denied(self):
        self.snapshot['jobs'][1] = self.snapshot['jobs'][0]
        with self.assertRaises(RuntimeError): gate.jobs_valid(self.lock, self.snapshot)

    def test_wrong_source_attempt_and_run_denied(self):
        for key, value in [('head_sha','0'*40),('run_attempt',2),('run_id',0)]:
            with self.subTest(key=key):
                data=copy.deepcopy(self.snapshot);data['jobs'][0][key]=value
                with self.assertRaises(RuntimeError): gate.jobs_valid(self.lock,data)

    def test_cancelled_pending_and_runnerless_denied(self):
        for key,value in [('conclusion','cancelled'),('status','queued'),('runner_id',None)]:
            with self.subTest(key=key):
                data=copy.deepcopy(self.snapshot);data['jobs'][0][key]=value
                with self.assertRaises(RuntimeError): gate.jobs_valid(self.lock,data)

    def test_failed_step_cannot_be_hidden_by_success(self):
        self.snapshot['jobs'][0]['steps'][0]['conclusion']='failure'
        with self.assertRaises(RuntimeError): gate.jobs_valid(self.lock,self.snapshot)

    def test_positive_migration_metadata(self):
        gate.migration_metadata_valid(self.lock['migration_audit'])

    def test_old_36_version_ledger_cannot_attest_new_migrations(self):
        data=copy.deepcopy(self.lock['migration_audit'])
        data['upgrade']['required_versions']=[v for v in data['upgrade']['required_versions'] if v not in ['20261111170000','20261112120000']]
        with self.assertRaises(RuntimeError): gate.migration_metadata_valid(data)

    def test_missing_populated_subject_denied(self):
        data=copy.deepcopy(self.lock['migration_audit']);data['upgrade']['preserved_subjects']=11
        with self.assertRaises(RuntimeError): gate.migration_metadata_valid(data)

    def test_pending_and_changed_ledger_denied(self):
        for key,value in [('pending_after',True),('existing_versions_preserved',False),('missing_after',['20261112120000'])]:
            with self.subTest(key=key):
                data=copy.deepcopy(self.lock['migration_audit']);data['upgrade'][key]=value
                with self.assertRaises(RuntimeError): gate.migration_metadata_valid(data)

    def test_unexpected_image_execution_denied(self):
        self.snapshot['jobs'][-1]['conclusion']='success'
        with self.assertRaises(RuntimeError): gate.jobs_valid(self.lock,self.snapshot)

    def test_skipped_mandatory_test_denied(self):
        self.snapshot['jobs'][0]['conclusion']='skipped'
        with self.assertRaises(RuntimeError): gate.jobs_valid(self.lock,self.snapshot)

if __name__ == '__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ConsolidatedDenials))
    Path(os.environ['RUNNER_TEMP'],'consolidated-denial-tests.json').write_text(json.dumps({
        'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':len(result.failures),
        'errors':len(result.errors),'skipped':len(result.skipped)}))
    raise SystemExit(0 if result.wasSuccessful() else 1)
