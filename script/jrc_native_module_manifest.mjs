import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const canonical=bytes=>Buffer.from(bytes.toString('utf8').replaceAll('\r\n','\n'));
export function buildManifests(root,input,baseBlob){
 root=fs.realpathSync(root);
 const files=new Map();
 for(const relative of input.artifactFiles){
  if(typeof relative!=='string'||relative.includes('\\')||path.posix.isAbsolute(relative)||relative.split('/').some(part=>!part||part==='.'||part==='..'))throw new Error('Unsafe module path');
  const actual=fs.realpathSync(path.join(root,relative));
  if(!actual.startsWith(root+path.sep)||!fs.statSync(actual).isFile())throw new Error('Module path escapes artifact: '+relative);
  const bytes=fs.readFileSync(actual);
  if(bytes.includes(0))throw new Error('Binary payload requires an explicit encoding: '+relative);
  files.set(relative,canonical(bytes));
 }
 const guards={schemaVersion:2,baseSourceSha:input.baseSourceSha,paths:input.paths,additionalEntrypoints:input.additionalEntrypoints,
  files:Object.fromEntries([...input.guardFiles].sort().map(relative=>{
   if(!files.has(relative))throw new Error('Missing guarded module artifact: '+relative);
   return [relative,sha(files.get(relative))];
  }))};
 const guardBytes=Buffer.from(JSON.stringify(guards,null,2)+'\n');
 files.set('config/jrc_flow_ownership_guards.json',guardBytes);
 const composition={schemaVersion:1,baseSourceSha:input.baseSourceSha,provenanceSourceSha:input.provenanceSourceSha,
  encoding:'Git text payloads with LF line endings',installedProof:false,compositionCount:input.compositionCount,
  editorStatus:input.editorStatus,limitations:input.limitations,
  files:[...files].sort(([a],[b])=>a.localeCompare(b)).map(([relative,bytes])=>{
   const base=baseBlob(relative);
   return {path:relative,baseSha256:base===null?null:sha(base),sha256:sha(bytes),bytes:bytes.length};
  })};
 return new Map([['config/jrc_flow_ownership_guards.json',guardBytes],['deploy/jrc/MODULE-COMPOSITION-MANIFEST.json',Buffer.from(JSON.stringify(composition,null,2)+'\n')]]);
}

function main(){
 const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),input=JSON.parse(fs.readFileSync(path.join(root,'deploy/jrc/module-composition-input.json'),'utf8'));
 if(!/^[a-f0-9]{40}$/.test(input.baseSourceSha))throw new Error('Exact Git base SHA required');
 const exists=spawnSync('git',['cat-file','-e',input.baseSourceSha+'^{commit}'],{cwd:root});
 if(exists.status!==0)throw new Error('Exact Git base is not available; fetch its history before generation');
 const baseBlob=relative=>{
  const object=input.baseSourceSha+':'+relative;
  if(spawnSync('git',['cat-file','-e',object],{cwd:root}).status!==0)return null;
  const result=spawnSync('git',['show',object],{cwd:root,maxBuffer:32*1024*1024});
  if(result.status!==0)throw new Error('Cannot read exact Git base blob '+relative);
  return result.stdout;
 };
 const manifests=buildManifests(root,input,baseBlob),write=process.argv.includes('--write');
 for(const [relative,bytes] of manifests){
  const target=path.join(root,relative);
  if(write)fs.writeFileSync(target,bytes);
  else if(!fs.existsSync(target)||!canonical(fs.readFileSync(target)).equals(bytes))throw new Error('Manifest is stale: '+relative+'; regenerate with --write after source freeze');
  console.log(JSON.stringify({path:relative,sha256:sha(bytes),bytes:bytes.length,operation:write?'generated':'verified'}));
 }
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main();
