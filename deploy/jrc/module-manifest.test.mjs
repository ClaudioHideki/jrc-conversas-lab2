import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import {buildManifests} from '../../script/jrc_native_module_manifest.mjs';

const sha=value=>createHash('sha256').update(value).digest('hex');
function withFixture(work){
 const base=fs.mkdtempSync(path.join(os.tmpdir(),'jrc-module-manifest-')),root=path.join(base,'artifact');
 fs.mkdirSync(path.join(root,'app'),{recursive:true});fs.mkdirSync(path.join(root,'config'));
 fs.writeFileSync(path.join(root,'app/guard.rb'),'# guard\r\n');fs.writeFileSync(path.join(root,'config/schedule.yml'),'heartbeat: true\r\n');
 fs.writeFileSync(path.join(root,'config/jrc_flow_ownership_guards.json'),'{}');
 const input={baseSourceSha:'a'.repeat(40),provenanceSourceSha:'b'.repeat(40),compositionCount:1,paths:['runner'],additionalEntrypoints:[],
  editorStatus:'fixture-only',limitations:[],artifactFiles:['app/guard.rb','config/schedule.yml','config/jrc_flow_ownership_guards.json'],guardFiles:['app/guard.rb','config/schedule.yml']};
 try{return work({base,root,input});}
 finally{
  if(!path.resolve(base).startsWith(path.resolve(os.tmpdir())+path.sep)||!path.basename(base).startsWith('jrc-module-manifest-'))throw new Error('Unexpected fixture cleanup target');
  fs.rmSync(base,{recursive:true,force:true});
 }
}

test('hashes actual base bytes including existing schedules and emits canonical Git LF payload hashes',()=>withFixture(({root,input})=>{
 const baseSchedule=Buffer.from('existing_schedule: true\n');
 const result=buildManifests(root,input,relative=>relative==='config/schedule.yml'?baseSchedule:null);
 const guard=JSON.parse(result.get('config/jrc_flow_ownership_guards.json')),manifest=JSON.parse(result.get('deploy/jrc/MODULE-COMPOSITION-MANIFEST.json'));
 assert.equal(guard.files['app/guard.rb'],sha('# guard\n'));
 const schedule=manifest.files.find(file=>file.path==='config/schedule.yml');
 assert.equal(schedule.baseSha256,sha(baseSchedule));assert.equal(schedule.sha256,sha('heartbeat: true\n'));
 assert.equal(manifest.installedProof,false);
 assert.equal(manifest.files.find(file=>file.path==='config/jrc_flow_ownership_guards.json').sha256,sha(result.get('config/jrc_flow_ownership_guards.json')));
}));

test('does not hash a missing or unlisted guard as if it were installed',()=>withFixture(({root,input})=>{
 input.guardFiles.push('app/missing.rb');
 assert.throws(()=>buildManifests(root,input,()=>null),/Missing guarded module artifact/);
}));

test('rejects traversal and ancestor symlinks escaping the artifact',()=>withFixture(({base,root,input})=>{
 assert.throws(()=>buildManifests(root,{...input,artifactFiles:['../outside.rb']},()=>null),/Unsafe module path/);
 const outside=path.join(base,'outside');fs.renameSync(path.join(root,'app'),outside);
 fs.symlinkSync(outside,path.join(root,'app'),process.platform==='win32'?'junction':'dir');
 assert.throws(()=>buildManifests(root,input,()=>null),/escapes artifact/);
}));
