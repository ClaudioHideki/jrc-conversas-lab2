import copy,hashlib,io,json,os,tempfile,unittest,zipfile
from unittest.mock import patch
import scoped_source_gate as gate
class ScopedAdmissionTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
  self.env=patch.dict(os.environ,{'RUNNER_TEMP':self.temp.name});self.env.start();self.addCleanup(self.env.stop)
  self.run={'head_sha':gate.INFRA,'status':'completed','conclusion':'success','run_attempt':1}
  self.jobs={'total_count':2,'jobs':[{'id':i,'name':name,'head_sha':gate.INFRA,'run_attempt':1,'conclusion':'success','status':'completed'} for i,name in enumerate(['frontend','backend'])]}
  self.reports=[{'summary':{'example_count':1,'failure_count':0,'pending_count':0,'errors_outside_of_examples_count':0}},{'success':True,'numTotalTests':1,'numFailedTests':0,'numPendingTests':0}]
  self.zip_names=['quick-rspec.json','quick-vue.json'];self.main=gate.MAIN;self.ancestor=gate.BASE_PRODUCT
 def execute(self):
  data={}
  for i,r in enumerate(self.reports):
   b=io.BytesIO()
   with zipfile.ZipFile(b,'w') as z:z.writestr(self.zip_names[i],json.dumps(r))
   data[i]=b.getvalue()
  artifacts=[{'id':i,'name':'report-'+gate.PRODUCT,'expired':False,'digest':'sha256:'+hashlib.sha256(b).hexdigest()} for i,b in data.items()]
  def api(path):
   if path.startswith('compare/'):return {'merge_base_commit':{'sha':self.ancestor}}
   if path=='git/ref/heads/main':return {'object':{'sha':self.main}}
   if path.startswith('git/ref/heads/'):return {'object':{'sha':gate.PRODUCT}}
   if path.endswith('/jobs?per_page=100'):return self.jobs
   if path.endswith('/artifacts'):return {'artifacts':artifacts}
   return self.run
  with patch.object(gate,'api',side_effect=api),patch.object(gate,'artifact_bytes',side_effect=lambda identifier:data[identifier]):gate.main()
 def test_complete_positive_reports(self):self.execute()
 def test_wrong_test_sha_denied(self):
  self.run['head_sha']='f'*40
  with self.assertRaises(AssertionError):self.execute()
 def test_cancelled_or_skipped_jobs_denied(self):
  for status in ['cancelled','skipped']:
   self.jobs['jobs'][0]['conclusion']=status
   with self.assertRaises(AssertionError):self.execute()
 def test_zero_native_examples_denied(self):
  self.reports[0]['summary']['example_count']=0
  with self.assertRaises(AssertionError):self.execute()
 def test_native_pending_and_outside_errors_denied(self):
  for key in ['failure_count','pending_count','errors_outside_of_examples_count']:
   self.reports[0]['summary'][key]=1
   with self.assertRaises(AssertionError):self.execute()
   self.reports[0]['summary'][key]=0
 def test_vue_pending_denied(self):
  self.reports[1]['numPendingTests']=1
  with self.assertRaises(AssertionError):self.execute()
 def test_missing_job_denied(self):
  self.jobs['jobs'].pop()
  with self.assertRaises(AssertionError):self.execute()
 def test_wrong_report_denied(self):
  self.zip_names[1]='unrelated.json'
  with self.assertRaises(RuntimeError):self.execute()
 def test_main_drift_denied(self):
  self.main='f'*40
  with self.assertRaises(AssertionError):self.execute()
 def test_wrong_base_ancestor_denied(self):
  self.ancestor='f'*40
  with self.assertRaises(AssertionError):self.execute()
if __name__=='__main__':unittest.main()

