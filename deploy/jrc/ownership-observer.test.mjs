import assert from 'node:assert/strict';
import {generateKeyPairSync,verify} from 'node:crypto';
import {test} from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {collectObservation,signObservation,DockerObservationDriver} from './ownership-observer.mjs';

const NOW=Date.parse('2026-10-15T15:00:00Z'),source='a'.repeat(40),digest='sha256:'+'b'.repeat(64),manifest='c'.repeat(64);
function fixture(){
 const containers=['rails','sidekiq'].map((service,index)=>({Id:String(index+1).repeat(64),Image:'sha256:'+'d'.repeat(64),
  Config:{Labels:{'com.docker.compose.project':'candidate','com.docker.compose.service':service},Cmd:[service==='rails'?'puma':'sidekiq']},
  State:{Running:true,Restarting:false,Status:'running',Pid:100+index,StartedAt:'2026-10-15T14:00:00Z'}}));
 const config={project:'candidate',services:{rails:{role:'rails',minimumReplicas:1},sidekiq:{role:'worker',minimumReplicas:1}},ignoredServices:[],
  imageRepository:'ghcr.io/example/jrc',expectedImageDigest:digest,expectedSourceSha:source,guardManifestSha256:manifest,guardFiles:{'app/example.rb':'e'.repeat(64)},
  appRoot:'/app',ttlSeconds:120,maxHeartbeatAgeSeconds:30,maxWaitSeconds:1};
 const calls=[],reports=new Map();let inventoryCalls=0;
 const driver={
  async prepareChallenge(){calls.push('prepare');},
  async inventory(){calls.push('inventory');inventoryCalls++;return structuredClone(containers);},
  async image(){calls.push('image');return {RepoDigests:['ghcr.io/example/jrc@'+digest],Config:{Labels:{'org.opencontainers.image.revision':source}}};},
  async challenge(container,nonce){calls.push('challenge');reports.set(container.Id,{sourceSha:source,guardManifestSha256:manifest,files:{'app/example.rb':'e'.repeat(64)},
   processes:[{pid:1,startTicks:'123',role:container.Config.Labels['com.docker.compose.service']==='rails'?'rails':'worker',namespace:'pid:[123]',
    heartbeat:{nonce,pid:1,startTicks:'123',namespace:'pid:[123]',role:container.Config.Labels['com.docker.compose.service']==='rails'?'rails':'worker',
     sourceSha:source,guardManifestSha256:manifest,loadedHooks:true,observedAt:new Date(NOW-1000).toISOString()}}]});},
  async probe(container){calls.push('probe');return structuredClone(reports.get(container.Id));}
 };
 return {config,driver,containers,calls,reports,inventoryCalls:()=>inventoryCalls,clock:{now:()=>NOW}};
}
test('observes Docker image, artifacts and every live Rails/worker PID before signing',async()=>{
 const f=fixture(),payload=await collectObservation(f.config,f.driver,f.clock);
 assert.equal(payload.hostSourceSha,source);assert.equal(payload.hostImageDigest,digest);
 assert.equal(payload.workers.length,2);assert.deepEqual(payload.workers.map(p=>p.role),['rails','worker']);
 assert.match(payload.observationNonce,/^[A-Za-z0-9_-]{43}$/);
 assert.ok(payload.workers.every(p=>p.observed&&p.pid===1&&p.processStartTicks==='123'));
 assert.equal(f.inventoryCalls(),2);assert.equal(f.calls.filter(c=>c==='probe').length,4);
 const {privateKey,publicKey}=generateKeyPairSync('ed25519'),envelope=signObservation(payload,privateKey);
 assert.ok(verify(null,Buffer.from(JSON.stringify(envelope.payload)),publicKey,Buffer.from(envelope.signature,'base64')));
 assert.equal(Date.parse(payload.expiresAt)-Date.parse(payload.observedAt),120000);
});
test('rejects a missing worker, stopped container and uninventoried application service',async()=>{
 for(const mutate of [
  f=>f.containers.pop(),
  f=>{f.containers[1].State.Running=false;},
  f=>{f.containers.push({...structuredClone(f.containers[1]),Id:'9'.repeat(64),Config:{Labels:{'com.docker.compose.service':'forgotten-worker'},Cmd:['sidekiq']}});}
 ]){
  const f=fixture();mutate(f);await assert.rejects(collectObservation(f.config,f.driver,f.clock));
 }
});
test('rejects image and source identity copied from configuration when Docker differs',async()=>{
 for(const image of [{RepoDigests:[],Config:{Labels:{'org.opencontainers.image.revision':source}}},
  {RepoDigests:['ghcr.io/example/jrc@'+digest],Config:{Labels:{'org.opencontainers.image.revision':'f'.repeat(40)}}}]){
  const f=fixture();f.driver.image=async()=>image;await assert.rejects(collectObservation(f.config,f.driver,f.clock));
 }
});
test('rejects stale/future heartbeats, stale nonce, false hooks and another PID/startticks',async()=>{
 const mutations=[
  r=>{r.heartbeat.observedAt=new Date(NOW-31000).toISOString();},
  r=>{r.heartbeat.observedAt=new Date(NOW+1).toISOString();},
  r=>{r.heartbeat.nonce='old-challenge';},
  r=>{r.heartbeat.loadedHooks=false;},
  r=>{r.heartbeat.pid=2;},
  r=>{r.heartbeat.startTicks='124';},
  r=>{r.heartbeat.namespace='pid:[999]';}
 ];
 for(const mutate of mutations){
  const f=fixture(),probe=f.driver.probe;f.driver.probe=async c=>{const report=await probe(c);mutate(report.processes[0]);return report;};
  await assert.rejects(collectObservation(f.config,f.driver,f.clock));
 }
});
test('rejects a missing process heartbeat or artifact hash mismatch',async()=>{
 for(const mutate of [r=>{r.processes[0].heartbeat=null;},r=>{r.files['app/example.rb']='0'.repeat(64);},r=>{r.sourceSha='0'.repeat(40);}]){
  const f=fixture(),probe=f.driver.probe;f.driver.probe=async c=>{const report=await probe(c);mutate(report);return report;};
  await assert.rejects(collectObservation(f.config,f.driver,f.clock));
 }
});
test('rechecks container generation after measurement and refuses a restart before signing',async()=>{
 const f=fixture(),inventory=f.driver.inventory;let n=0;
 f.driver.inventory=async()=>{const list=await inventory();if(++n===2)list[1].State.StartedAt='2026-10-15T14:59:59Z';return list;};
 await assert.rejects(collectObservation(f.config,f.driver,f.clock),/CHANGED/);
});

test('rechecks process start ticks before signing even when Docker container generation is unchanged',async()=>{
 const f=fixture(),probe=f.driver.probe;let calls=0;
 f.driver.probe=async container=>{const report=await probe(container);if(++calls>2){report.processes[0].startTicks='999';report.processes[0].heartbeat.startTicks='999';}return report;};
 await assert.rejects(collectObservation(f.config,f.driver,f.clock),/PROCESS_CHANGED/);
});

test('refuses a measurement that became stale while measuring other containers',async()=>{
 const f=fixture(),inventory=f.driver.inventory;let after=false;
 f.driver.inventory=async()=>{const value=await inventory();if(f.inventoryCalls()===2)after=true;return value;};
 f.clock.now=()=>NOW+(after?31000:0);
 await assert.rejects(collectObservation(f.config,f.driver,f.clock),/CLOCK_OR_STALE/);
});
test('requires a distinct challenge bind mounted read-only rather than the heartbeat RW channel',async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'jrc-observer-mount-')),challenge=path.join(directory,'challenge'),attestation=path.join(directory,'attestation');
 fs.mkdirSync(challenge);fs.mkdirSync(attestation);
 try{
  const driver=new DockerObservationDriver();driver.docker=async()=>JSON.stringify({challengeAccepted:true});
  const config={challengeDirectory:challenge,challengeContainerDirectory:'/run/jrc/challenge',attestationDirectory:attestation,attestationContainerDirectory:'/run/jrc/attestation'};
  const container={Id:'1'.repeat(64),Config:{Env:['JRC_FLOW_OWNERSHIP_CHALLENGE_DIR=/run/jrc/challenge','JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR=/run/jrc/heartbeat','JRC_FLOW_OWNERSHIP_ATTESTATION_DIR=/run/jrc/attestation']},
   Mounts:[{Type:'bind',Source:challenge,Destination:'/run/jrc/challenge',RW:true},{Type:'bind',Source:attestation,Destination:'/run/jrc/attestation',RW:false}]};
  await assert.rejects(driver.challenge(container,'n'.repeat(43),'/app',config),/CHALLENGE/);
  container.Mounts[0].RW=false;
  await driver.challenge(container,'n'.repeat(43),'/app',config);
  container.Config.Env[1]='JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR=/run/jrc/challenge';
  await assert.rejects(driver.challenge(container,'n'.repeat(43),'/app',config),/CHALLENGE/);
 }finally{fs.rmdirSync(challenge);fs.rmdirSync(attestation);fs.rmdirSync(directory);}
});
