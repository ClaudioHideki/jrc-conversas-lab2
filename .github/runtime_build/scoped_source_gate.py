"""Admission for the exact scoped test run, never a Docker/image gate."""
import hashlib,json,os,urllib.request,urllib.parse,zipfile,io
from pathlib import Path
PRODUCT='2be22e86baecbe75c302bb03208e78e67301c743'
BRANCH='codex/respostas-rapidas-aprovacoes-20261115'
MAIN='55da80eb1254aee54ee0f1fb5c42f2be46a98737'
BASE_PRODUCT='55da80eb1254aee54ee0f1fb5c42f2be46a98737'
INITIAL_MAIN='309a3e04f32ae1ca469fc202f6d1be0f9e50a20a'
RUN=43760616930
INFRA='6dab105021422a43b382e8c9721d3e0201d360e4'
REPO='ClaudioHideki/jrc-conversas-lab2'
def api(path):
 req=urllib.request.Request('https://api.github.com/repos/'+REPO+'/'+path,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'})
 with urllib.request.urlopen(req,timeout=45) as r:return json.load(r)
def check_refs():
 assert api('git/ref/heads/main')['object']['sha']==MAIN,'Main changed; review concurrent updates'
 assert api('git/ref/heads/'+BRANCH)['object']['sha']==PRODUCT,'Candidate changed'
 assert api('compare/'+BASE_PRODUCT+'...'+PRODUCT)['merge_base_commit']['sha']==BASE_PRODUCT,'Candidate no longer descends from the reviewed base'
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None
def artifact_bytes(identifier):
 req=urllib.request.Request('https://api.github.com/repos/'+REPO+'/actions/artifacts/'+str(identifier)+'/zip',headers={'Authorization':'Bearer '+os.environ['GH_TOKEN']})
 try:urllib.request.build_opener(NoRedirect).open(req,timeout=45)
 except urllib.error.HTTPError as e:
  assert e.code==302
  url=e.headers['Location'];parsed=urllib.parse.urlsplit(url)
  assert parsed.scheme=='https' and parsed.hostname.endswith(('.blob.core.windows.net','.githubusercontent.com','.github.com','.actions.githubusercontent.com'))
  with urllib.request.urlopen(urllib.request.Request(url),timeout=60) as r:
   data=r.read(32*1024*1024+1);assert len(data)<=32*1024*1024;return data
 raise RuntimeError('Missing artifact redirect')
def main():
 check_refs()
 run=api('actions/runs/'+str(RUN))
 assert run['head_sha']==INFRA and run['status']=='completed' and run['conclusion']=='success' and run['run_attempt']==1
 snapshot=api('actions/runs/'+str(RUN)+'/jobs?per_page=100');jobs=snapshot['jobs']
 assert snapshot['total_count']==len(jobs)==2 and {j['name'] for j in jobs}=={'frontend','backend'}
 assert all(j['head_sha']==INFRA and j['run_attempt']==1 and j['conclusion']=='success' and j['status']=='completed' for j in jobs)
 artifacts=api('actions/runs/'+str(RUN)+'/artifacts')['artifacts'];assert len(artifacts)==2
 found=set();proof=[]
 for a in artifacts:
  assert not a['expired'] and a['name'].endswith(PRODUCT)
  data=artifact_bytes(a['id']);digest=hashlib.sha256(data).hexdigest()
  if a.get('digest'):assert a['digest']=='sha256:'+digest
  with zipfile.ZipFile(io.BytesIO(data)) as z:
   names=z.namelist();assert len(names)==1
   d=json.loads(z.read(names[0]))
   if names[0]=='quick-rspec.json':
    s=d['summary'];assert s['example_count']>0 and all(s[k]==0 for k in ['failure_count','pending_count','errors_outside_of_examples_count']);found.add('rails')
   elif names[0]=='quick-vue.json':
    assert d['success'] and d['numTotalTests']>0 and d['numFailedTests']==d['numPendingTests']==0;found.add('vue')
   else:raise RuntimeError('Unexpected report')
  proof.append({'id':a['id'],'name':a['name'],'sha256':digest})
 assert found=={'rails','vue'}
 result={'passed':True,'product_sha':PRODUCT,'test_infrastructure_sha':INFRA,'test_run':RUN,'initial_main':INITIAL_MAIN,'preserved_main':MAIN,'base_product':BASE_PRODUCT,'artifacts':proof,'jobs':[{k:j[k] for k in ['id','name','conclusion']} for j in jobs]}
 Path(os.environ['RUNNER_TEMP'],'scoped-source-gate.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if __name__=='__main__':main()
