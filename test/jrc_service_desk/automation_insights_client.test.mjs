import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = path => readFileSync(new URL('../../' + path, import.meta.url), 'utf8');
const moduleURL = s => 'data:text/javascript;base64,' + Buffer.from(s).toString('base64');
const access = moduleURL(source('app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/access.js'));
const input = source('app/javascript/dashboard/api/serviceDeskAutomationInsights.js').replace("'../routes/dashboard/serviceDesk/helpers/access'", JSON.stringify(access));
const { createAutomationInsightsClient } = await import(moduleURL(input));
const valid = () => ({contract_version:1,account_id:'1',unit_id:'2',queue_id:'3',total:0,items:[],delivery_rate:null});
for (const [name, fields] of [
  ['account',{account_id:'4'}],['unit',{unit_id:'4'}],['version',{contract_version:2}],
  ['queue',{queue_id:'5'}],['total',{total:-1}],['items',{items:null}],
]) test(`rejects mismatched ${name}`, async()=>{
  const client=createAutomationInsightsClient({get:async()=>({data:{...valid(),...fields}})});
  await assert.rejects(client.read('1','2','ola',{queue_id:'3'}));
});
test('uses exact authorized query scope and native transport options',async()=>{
  let request;const signal=new AbortController().signal;
  const client=createAutomationInsightsClient({get:async(url,options)=>{request={url,options};return {data:valid()};}});
  const result=await client.read(1,2,'ola',{queue_id:'3',unit_id:'foreign',page:2},signal);
  assert.equal(result.total,0);assert.equal(request.url,'/api/v1/accounts/1/jrc_service_desk/automation_insights/ola');
  assert.deepEqual(request.options.params,{queue_id:'3',unit_id:'2',page:2});assert.equal(request.options.signal,signal);assert.equal(request.options.timeout,30000);
});
for(const [name,account,unit,kind] of [['no account',null,2,'ola'],['no unit',1,null,'ola'],['unsupported',1,2,'other']])
 test(`rejects ${name} before HTTP`,async()=>{const client=createAutomationInsightsClient({get:()=>assert.fail('must not call')});await assert.rejects(client.read(account,unit,kind));});
for(const rate of [-1,101,NaN,Infinity,'80']) test(`invalid rate ${String(rate)}`,async()=>{
 const client=createAutomationInsightsClient({get:async()=>({data:{...valid(),delivery_rate:rate}})});await assert.rejects(client.read(1,2,'notifications'));
});
test('no delivery rate remains unavailable, not fabricated zero',async()=>{
 const client=createAutomationInsightsClient({get:async()=>({data:valid()})});assert.equal((await client.read(1,2,'notifications')).delivery_rate,null);
});
