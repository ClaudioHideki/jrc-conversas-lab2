import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root = new URL('../../app/javascript/dashboard/routes/dashboard/serviceDesk/automationStudio/', import.meta.url);
const source = readFileSync(new URL('flowRules.js', root), 'utf8');
const rules = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

for (const [name, value, unit, expected] of [
  ['minutes', 30, 'minutes', 1800], ['hours', 2, 'hours', 7200],
  ['half hour', 0.5, 'hours', 1800], ['seconds exact', 0.25, 'minutes', 15],
  ['zero', 0, 'minutes', null], ['negative', -1, 'hours', null],
  ['blank', '', 'hours', null], ['whitespace', ' ', 'hours', null],
  ['unknown unit', 1, 'days', null], ['fractional second', 0.001, 'minutes', null],
  ['not number', 'abc', 'minutes', null], ['overflow', 999999999, 'hours', null],
]) test(`duration ${name}`, () => assert.equal(rules.secondsFor(value, unit), expected));
test('three ordered workflows have 6, 5 and 6 steps', () => {
  assert.equal(rules.OLA_STEPS.length, 6); assert.equal(rules.NOTIFICATION_STEPS.length, 5); assert.equal(rules.CLOSURE_STEPS.length, 6);
});
test('a threshold is not silently inferred from an empty policy', () => assert.equal(rules.validThresholds({}), true));
for (const [name, value, expected] of [
  ['ordered', {enabled:true,thresholds:[{percent:75},{percent:100}]}, true],
  ['duplicate', {enabled:true,thresholds:[{percent:75},{percent:75}]}, false],
  ['descending', {thresholds:[{percent:90},{percent:75}]}, false],
  ['out of range', {thresholds:[{percent:101}]}, false],
  ['zero', {thresholds:[{percent:0}]}, false],
  ['no rows', {enabled:true,thresholds:[]}, false],
  ['team without queue', {thresholds:[{percent:80,team_id:'2'}]}, false],
  ['team with queue', {thresholds:[{percent:80,team_id:'2',queue_id:'3'}]}, true],
  ['automatic without executor', {enabled:true,automatic:true,thresholds:[{percent:80}]}, false],
  ['automatic with executor', {enabled:true,automatic:true,execution_account_user_id:'2',thresholds:[{percent:80}]}, true],
]) test(`threshold ${name}`, () => assert.equal(rules.validThresholds(value), expected));
test('selection omits blocked and deduplicates current rows', () => {
  assert.deepEqual(rules.selectedPage(['1'], [{id:'1'}, {id:'2'}, {id:'3',reason:'contractual_ticket'}]), {ok:true,selected:['1','2']});
});
test('100 is accepted without truncation', () => assert.equal(rules.selectedPage([], Array.from({length:100},(_,i)=>({id:String(i+1)}))).selected.length,100));
test('101 is rejected atomically preserving the prior selection', () => {
  const prior=['999']; const result=rules.selectedPage(prior,Array.from({length:100},(_,i)=>({id:String(i+1)})));
  assert.equal(result.ok,false); assert.deepEqual(result.selected,prior); assert.equal(prior.length,1);
});
for (const [name, preview, expected] of [
  ['valid',{receipt:'signed',expires_at:'2026-10-24T01:00:01Z'},true],
  ['exact expiry',{receipt:'signed',expires_at:'2026-10-24T01:00:00Z'},false],
  ['past',{receipt:'signed',expires_at:'2026-10-24T00:59:59Z'},false],
  ['no receipt',{expires_at:'2026-10-25T01:00:00Z'},false],
  ['invalid expiry',{receipt:'signed',expires_at:'invalid'},false],
]) test(`preview ${name}`,()=>assert.equal(rules.previewCurrent(preview,Date.parse('2026-10-24T01:00:00Z')),expected));
test('draft namespace partitions account, actor, unit and queue', () => {
  const base={account_id:'1',user_id:'2'};
  const one=rules.draftKey('queue',base,'3','4');
  assert.notEqual(one,rules.draftKey('queue',{...base,account_id:'5'},'3','4'));
  assert.notEqual(one,rules.draftKey('queue',{...base,user_id:'5'},'3','4'));
  assert.notEqual(one,rules.draftKey('queue',base,'5','4'));
  assert.notEqual(one,rules.draftKey('queue',base,'3','5'));
  assert.equal(rules.draftKey('queue',null,'3','4'),null);
});
const store=()=>{const map=new Map();return{setItem:(k,v)=>map.set(k,v),getItem:k=>map.get(k)??null};};
test('draft roundtrip is independent and version-aware',()=>{
  const storage=store();const value={name:'test',thresholds:[{percent:80}]};
  rules.writeDraft(storage,'scoped',value,'v1');value.name='changed';
  assert.equal(rules.readDraft(storage,'scoped','v1').name,'test');
  assert.throws(()=>rules.readDraft(storage,'scoped','v2'));
});
test('missing draft, malformed JSON and absent scope are rejected',()=>{
  const storage=store();assert.throws(()=>rules.readDraft(storage,'missing',null));
  storage.setItem('broken','oops');assert.throws(()=>rules.readDraft(storage,'broken',null));
  assert.throws(()=>rules.writeDraft(storage,null,{},null));
});
test('latest policy is determined by version, not response order',()=>{
  const a={event_type:'closed',channel:'email',version:2};const b={...a,version:1};
  const c={...a,channel:'whatsapp'};
  assert.deepEqual(rules.latestPolicies([b,c,a]),[a,c]);
});
test('policy identity separates channels, service and type',()=>{
  const a={event_type:'closed',channel:'email'};
  assert.notEqual(rules.policyIdentity(a),rules.policyIdentity({...a,service_id:'2'}));
  assert.notEqual(rules.policyIdentity(a),rules.policyIdentity({...a,ticket_type_id:'2'}));
});
test('progress includes blocked and conflict without inventing success',()=>{
  const value=rules.batchProgress({results:[{status:'applied'},{status:'blocked'},{status:'conflict'},{status:'pending'}]});
  assert.deepEqual(value,{applied:1,blocked:1,conflict:1,pending:1,total:4,finished:3});
});
test('JSON order does not change a snapshot but array order does',()=>{
  assert.equal(rules.sameJSON({a:1,b:[1,2]},{b:[1,2],a:1}),true);
  assert.equal(rules.sameJSON([1,2],[2,1]),false);
});
test('no placeholder transport or automatically applied revision in the views',()=>{
  const n=readFileSync(new URL('NotificationWorkbench.vue',root),'utf8');
  const c=readFileSync(new URL('ClosureRevisionWorkbench.vue',root),'utf8');
  assert.ok(n.includes('useNotificationPolicy'));assert.ok(n.includes('publishFinal'));
  assert.ok(c.includes('executionConfirmed'));assert.ok(c.includes('currentPreview'));
  assert.ok(c.includes('applyAsync'));assert.ok(!c.includes('update_all'));
});
test('all new locale keys exist in both languages',()=>{
  const path=loc=>new URL(`../../app/javascript/dashboard/i18n/locale/${loc}/jrcServiceDesk.json`,import.meta.url);
  const keys=(o,p='')=>Object.entries(o).flatMap(([k,v])=>v && typeof v==='object'&&!Array.isArray(v)?keys(v,`${p}${k}.`):[p+k]);
  const pt=JSON.parse(readFileSync(path('pt_BR'),'utf8')).JRC_SERVICE_DESK.AUTOMATION_STUDIO;
  const en=JSON.parse(readFileSync(path('en'),'utf8')).JRC_SERVICE_DESK.AUTOMATION_STUDIO;
  assert.deepEqual(keys(pt).sort(),keys(en).sort());
});
