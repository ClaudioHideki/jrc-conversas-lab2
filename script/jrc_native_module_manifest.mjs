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

export function readBaseBlobs(root, baseSha, relatives) {
 if(!/^[a-f0-9]{40}$/.test(baseSha))throw new Error('Exact Git base SHA required');
 for(const relative of relatives){
  if(typeof relative!=='string'||/[\r\n\0]/.test(relative)||relative.includes('\\')||path.posix.isAbsolute(relative)||relative.split('/').some(part=>!part||part==='.'||part==='..'))throw new Error('Unsafe module path');
 }
 if(!relatives.length)return new Map();
 const result=spawnSync('git',['-c','safe.directory='+path.resolve(root).replaceAll('\\','/'),'cat-file','--batch'],{
  cwd:root,input:relatives.map(relative=>baseSha+':'+relative).join('\n')+'\n',maxBuffer:64*1024*1024,
 });
 if(result.error||result.status!==0)throw new Error('Cannot read exact Git base blobs');
 const output=result.stdout,blobs=new Map();let offset=0;
 for(const relative of relatives){
  const end=output.indexOf(10,offset);if(end<0)throw new Error('Incomplete Git blob header');
  const header=output.subarray(offset,end).toString('utf8');offset=end+1;
  if(header===baseSha+':'+relative+' missing'){blobs.set(relative,null);continue;}
  const match=/^[a-f0-9]{40} blob (\d+)$/.exec(header);if(!match)throw new Error('Unexpected Git base object');
  const size=Number(match[1]);if(!Number.isSafeInteger(size)||offset+size>=output.length||output[offset+size]!==10)throw new Error('Incomplete Git blob content');
  blobs.set(relative,Buffer.from(output.subarray(offset,offset+size)));offset+=size+1;
 }
 if(offset!==output.length)throw new Error('Unexpected Git blob output');
 return blobs;
}

function main(){
 const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),input=JSON.parse(fs.readFileSync(path.join(root,'deploy/jrc/module-composition-input.json'),'utf8'));
 if(!/^[a-f0-9]{40}$/.test(input.baseSourceSha))throw new Error('Exact Git base SHA required');
 const exists=spawnSync('git',['cat-file','-e',input.baseSourceSha+'^{commit}'],{cwd:root});
 if(exists.status!==0)throw new Error('Exact Git base is not available; fetch its history before generation');
 const baseBlobs=readBaseBlobs(root,input.baseSourceSha,input.artifactFiles);
 const baseBlob=relative=>baseBlobs.get(relative)??null;
 const manifests=buildManifests(root,input,baseBlob),write=process.argv.includes('--write');
 for(const [relative,bytes] of manifests){
  const target=path.join(root,relative);
  if(write)fs.writeFileSync(target,bytes);
  else if(!fs.existsSync(target)||!canonical(fs.readFileSync(target)).equals(bytes))throw new Error('Manifest is stale: '+relative+'; regenerate with --write after source freeze');
  console.log(JSON.stringify({path:relative,sha256:sha(bytes),bytes:bytes.length,operation:write?'generated':'verified'}));
 }
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main();
