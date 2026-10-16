import fs from 'node:fs';
import path from 'node:path';
import {randomBytes,createHash,createPrivateKey,createPublicKey,sign} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';

const exec=promisify(execFile),sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const fail=code=>{throw new Error(code);};
const serviceOf=container=>container.Config?.Labels?.['com.docker.compose.service'];
function applicationContainers(config,inventory){
 const result=[],counts=new Map();
 for(const container of inventory){
  const service=serviceOf(container),oneoff=container.Config?.Labels?.['com.docker.compose.oneoff']==='True';
  if(oneoff&&!container.State?.Running)continue;
  const specification=config.services[service];
  if(!specification){
   const command=[...(container.Config?.Entrypoint||[]),...(container.Config?.Cmd||[])].join(' ');
   if(!config.ignoredServices.includes(service)||/puma|sidekiq|rails (s|server)\b/i.test(command))fail('FLOW_OBSERVER_UNINVENTORIED_SERVICE');
   continue;
  }
  if(oneoff||!container.State?.Running||container.State.Restarting||container.State.Status!=='running'||!(container.State.Pid>0))fail('FLOW_OBSERVER_CONTAINER_NOT_LIVE');
  if(!/^[a-f0-9]{64}$/.test(container.Id))fail('FLOW_OBSERVER_CONTAINER_ID');
  counts.set(service,(counts.get(service)||0)+1);result.push(container);
 }
 for(const [service,specification] of Object.entries(config.services))if((counts.get(service)||0)<specification.minimumReplicas)fail('FLOW_OBSERVER_SERVICE_MISSING');
 if(!result.length)fail('FLOW_OBSERVER_NO_PROCESSES');
 return result.sort((a,b)=>a.Id.localeCompare(b.Id));
}
const generation=containers=>JSON.stringify(containers.map(c=>[c.Id,c.Image,c.State.StartedAt,serviceOf(c)]));
function verifyProbe(config,container,report,nonce,now){
 if(report.sourceSha!==config.expectedSourceSha||report.guardManifestSha256!==config.guardManifestSha256)fail('FLOW_OBSERVER_ARTIFACT_CHANGED');
 if(Object.entries(config.guardFiles).some(([file,hash])=>report.files?.[file]!==hash))fail('FLOW_OBSERVER_GUARD_FILE_CHANGED');
 if(!Array.isArray(report.processes)||!report.processes.length)fail('FLOW_OBSERVER_PROCESS_MISSING');
 const seen=new Set(),role=config.services[serviceOf(container)].role;
 return report.processes.map(process=>{
  const h=process.heartbeat,stamp=Date.parse(h?.observedAt);
  if(!Number.isSafeInteger(process.pid)||process.pid<1||seen.has(process.pid)||!/^\d+$/.test(process.startTicks)||!/^pid:\[\d+\]$/.test(process.namespace)||process.role!==role)fail('FLOW_OBSERVER_PROCESS_CHANGED');
  seen.add(process.pid);
  if(!h||h.nonce!==nonce||h.pid!==process.pid||h.startTicks!==process.startTicks||h.namespace!==process.namespace||h.role!==role)fail('FLOW_OBSERVER_HEARTBEAT_REQUIRED');
  if(h.loadedHooks!==true||h.sourceSha!==report.sourceSha||h.guardManifestSha256!==report.guardManifestSha256)fail('FLOW_OBSERVER_HOOKS_REQUIRED');
  if(!Number.isFinite(stamp)||stamp>now||now-stamp>config.maxHeartbeatAgeSeconds*1000)fail('FLOW_OBSERVER_CLOCK_OR_STALE');
  return {containerId:container.Id,service:serviceOf(container),role,pid:process.pid,processStartTicks:process.startTicks,
   observedAt:h.observedAt,imageDigest:config.expectedImageDigest,guardManifestSha256:report.guardManifestSha256,observed:true};
 });
}
export async function collectObservation(config,driver,clock={now:Date.now}){
 const roles=new Set(Object.values(config.services).map(s=>s.role));
 if(!roles.has('rails')||!roles.has('worker'))fail('FLOW_OBSERVER_RAILS_AND_WORKERS_REQUIRED');
 const containers=applicationContainers(config,await driver.inventory(config.project)),nonce=randomBytes(32).toString('base64url'),workers=[];
 await driver.prepareChallenge(nonce,config);
 let actualSource,actualDigest;
 for(const container of containers){
  const image=await driver.image(container.Image),reference=image.RepoDigests?.find(value=>value===config.imageRepository+'@'+config.expectedImageDigest);
  const source=image.Config?.Labels?.['org.opencontainers.image.revision'];
  if(!reference||source!==config.expectedSourceSha)fail('FLOW_OBSERVER_IMAGE_IDENTITY_CHANGED');
  actualSource=source;actualDigest=reference.split('@')[1];
  await driver.challenge(container,nonce,config.appRoot,config);
 }
 for(const container of containers){
  const deadline=performance.now()+config.maxWaitSeconds*1000;
  for(;;){
   try{workers.push(...verifyProbe(config,container,await driver.probe(container,nonce,config.appRoot),nonce,clock.now()));break;}
   catch(error){
    if(error.message!=='FLOW_OBSERVER_HEARTBEAT_REQUIRED'||performance.now()>=deadline)throw error;
    await new Promise(resolve=>setTimeout(resolve,250));
   }
  }
 }
 const latest=[];
 for(const container of containers)latest.push(...verifyProbe(config,container,await driver.probe(container,nonce,config.appRoot),nonce,clock.now()));
 const identities=list=>JSON.stringify(list.map(worker=>[worker.containerId,worker.pid,worker.processStartTicks,worker.role]).sort());
 if(identities(latest)!==identities(workers))fail('FLOW_OBSERVER_PROCESS_CHANGED');
 const after=applicationContainers(config,await driver.inventory(config.project));
 if(generation(after)!==generation(containers))fail('FLOW_OBSERVER_CONTAINER_CHANGED');
 const now=clock.now();
 if(latest.some(worker=>Date.parse(worker.observedAt)>now||now-Date.parse(worker.observedAt)>config.maxHeartbeatAgeSeconds*1000))fail('FLOW_OBSERVER_CLOCK_OR_STALE');
 const observed=Math.min(...latest.map(w=>Date.parse(w.observedAt)));
 return {hostSourceSha:actualSource,hostImageDigest:actualDigest,guardManifestSha256:config.guardManifestSha256,
  observationNonce:nonce,observedAt:new Date(observed).toISOString(),expiresAt:new Date(observed+config.ttlSeconds*1000).toISOString(),workers:latest};
}
export function signObservation(payload,privateKey){
 return {payload,signature:sign(null,Buffer.from(JSON.stringify(payload)),privateKey).toString('base64')};
}
export class DockerObservationDriver {
 async docker(args){try{return (await exec('docker',args,{encoding:'utf8',timeout:30000,maxBuffer:8*1024*1024})).stdout.trim();}catch{fail('FLOW_OBSERVER_DOCKER_FAILED');}}
 async inventory(project){
  const ids=(await this.docker(['ps','--all','--no-trunc','--filter','label=com.docker.compose.project='+project,'--format','{{.ID}}'])).split(/\s+/).filter(Boolean);
  return ids.length?JSON.parse(await this.docker(['inspect',...ids])):[];
 }
 async image(id){return JSON.parse(await this.docker(['image','inspect',id]))[0];}
 async prepareChallenge(nonce,config){
  const directory=fs.realpathSync(config.challengeDirectory);
  if((fs.statSync(directory).mode&0o022)!==0)fail('FLOW_OBSERVER_CHALLENGE_PERMISSIONS');
  const now=Date.now(),temporary=path.join(directory,'.challenge-'+randomBytes(16).toString('hex'));
  fs.writeFileSync(temporary,JSON.stringify({nonce,issuedAt:new Date(now).toISOString(),expiresAt:new Date(now+30000).toISOString()}),{flag:'wx',mode:0o644});
  fs.renameSync(temporary,path.join(directory,'challenge.json'));
 }
 async challenge(container,_nonce,_root,config){
  const environment=Object.fromEntries((container.Config.Env||[]).map(value=>{const at=value.indexOf('=');return [value.slice(0,at),value.slice(at+1)];}));
  for(const [hostDirectory,destination,variable] of [
   [config.challengeDirectory,config.challengeContainerDirectory,'JRC_FLOW_OWNERSHIP_CHALLENGE_DIR'],
   [config.attestationDirectory,config.attestationContainerDirectory,'JRC_FLOW_OWNERSHIP_ATTESTATION_DIR']
  ]){
   const mount=container.Mounts?.find(entry=>entry.Destination===destination);
   if(!mount||mount.Type!=='bind'||mount.RW!==false||fs.realpathSync(mount.Source)!==fs.realpathSync(hostDirectory)||
    environment[variable]!==destination||container.Mounts.some(entry=>entry.Destination.startsWith(destination+'/')))fail('FLOW_OBSERVER_CHALLENGE_OR_ATTESTATION_MOUNT');
  }
  if(!environment.JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR||environment.JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR===config.challengeContainerDirectory||
   environment.JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR===config.attestationContainerDirectory)fail('FLOW_OBSERVER_CHALLENGE_CHANNEL');
 }
 async probe(container,nonce,root){return JSON.parse(await this.docker(['exec',container.Id,'ruby',root+'/script/jrc_flow_ownership_probe.rb','--nonce',nonce]));}
}
export function loadConfig(file){
 const absolute=fs.realpathSync(file);if((fs.statSync(absolute).mode&0o022)!==0)fail('FLOW_OBSERVER_CONFIG_PERMISSIONS');
 const config=JSON.parse(fs.readFileSync(absolute,'utf8'));
 if(!/^[a-z0-9][a-z0-9_-]{0,62}$/.test(config.project)||!/^sha256:[a-f0-9]{64}$/.test(config.expectedImageDigest)||!/^[a-f0-9]{40}$/.test(config.expectedSourceSha))fail('FLOW_OBSERVER_CONFIG_IDENTITY');
 if(typeof config.imageRepository!=='string'||!config.imageRepository||!config.services||!Array.isArray(config.ignoredServices))fail('FLOW_OBSERVER_CONFIG_REQUIRED');
 for(const specification of Object.values(config.services))if(!['rails','worker'].includes(specification.role)||!Number.isInteger(specification.minimumReplicas)||specification.minimumReplicas<1)fail('FLOW_OBSERVER_SERVICE_CONFIG');
 for(const field of ['appRoot','challengeContainerDirectory','attestationContainerDirectory'])if(!/^\/[a-zA-Z0-9_/-]+$/.test(config[field])||config[field].split('/').includes('..'))fail('FLOW_OBSERVER_APP_ROOT');
 if(fs.realpathSync(config.challengeDirectory)===fs.realpathSync(config.attestationDirectory))fail('FLOW_OBSERVER_CHALLENGE_CHANNEL');
 for(const [key,min,max] of [['ttlSeconds',30,300],['maxHeartbeatAgeSeconds',1,30],['maxWaitSeconds',1,30]])if(!Number.isInteger(config[key])||config[key]<min||config[key]>max)fail('FLOW_OBSERVER_TIME_CONFIG');
 const bytes=fs.readFileSync(config.guardManifestFile),guard=JSON.parse(bytes);
 config.guardManifestSha256=sha(bytes);config.guardFiles=guard.files;
 if(!config.guardFiles||!Object.keys(config.guardFiles).length)fail('FLOW_OBSERVER_GUARD_MANIFEST');
 return config;
}
function publish(config,envelope,publicKey){
 const directory=fs.realpathSync(config.attestationDirectory);if((fs.statSync(directory).mode&0o022)!==0)fail('FLOW_OBSERVER_OUTPUT_PERMISSIONS');
 const keyPath=path.join(directory,'jrc_flow_ownership_attestation_public.pem'),pem=publicKey.export({type:'spki',format:'pem'});
 if(fs.existsSync(keyPath)){if(fs.readFileSync(keyPath,'utf8')!==pem)fail('FLOW_OBSERVER_KEY_ROTATION_REQUIRED');}
 else fs.writeFileSync(keyPath,pem,{flag:'wx',mode:0o644});
 const target=path.join(directory,'jrc_flow_ownership_attestation.json'),temp=path.join(directory,'.observation-'+randomBytes(16).toString('hex'));
 fs.writeFileSync(temp,JSON.stringify(envelope)+'\n',{flag:'wx',mode:0o644});fs.renameSync(temp,target);
}
async function main(){
 const index=process.argv.indexOf('--config');if(index<0||!process.argv[index+1])fail('Use --config /private/observer.json [--check]');
 const config=loadConfig(process.argv[index+1]);
 try{
  const payload=await collectObservation(config,new DockerObservationDriver());
  if(!process.argv.includes('--check')){
   const privateFile=fs.realpathSync(config.privateKeyFile);if((fs.statSync(privateFile).mode&0o077)!==0)fail('FLOW_OBSERVER_PRIVATE_KEY_PERMISSIONS');
   const key=createPrivateKey(fs.readFileSync(privateFile));if(key.asymmetricKeyType!=='ed25519')fail('FLOW_OBSERVER_ED25519_REQUIRED');
   publish(config,signObservation(payload,key),createPublicKey(key));
  }
  console.log(JSON.stringify({verified:true,published:!process.argv.includes('--check'),source:payload.hostSourceSha,image:payload.hostImageDigest,processes:payload.workers.length,expiresAt:payload.expiresAt}));
 }catch(error){
  if(config.attestationDirectory){
   const target=path.join(fs.realpathSync(config.attestationDirectory),'jrc_flow_ownership_attestation.json');
   if(fs.existsSync(target))fs.unlinkSync(target);
  }
  throw error;
 }
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{console.error(error.message);process.exitCode=1;});
