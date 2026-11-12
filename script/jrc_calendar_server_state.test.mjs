import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCalendarPageState, calendarPageQuery } from '../app/javascript/dashboard/routes/dashboard/crm/utils/calendarPageState.js';

const query = { accountId: 1, identity: 'account1:actor7:agent', startsOn: '2026-11-01', endsBefore: '2026-12-01', filters: {} };
const reply = (ids = [1], options = {}) => ({ data: { data: ids.map(id => ({ id, title: `Synthetic ${id}` })),
  owners: [{ id: 7, name: 'Synthetic actor' }], meta: { total: ids.length, page: 1, per_page: 25, pages: 1, ...options } } });
const defer = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; };
const harness = fetchPage => {
  let state; let identity = query.identity;
  const reader = createCalendarPageState({ fetchPage, publish: next => { state=next; }, currentContext: () => identity });
  return { reader, state: () => state, setIdentity: v => { identity=v; } };
};

test('all filters are sent to the server before pagination', () => {
  assert.deepEqual(calendarPageQuery({ ...query, filters: { search:'renewal', type:'call', owner:7, status:'open' }, customerSegmentId:4 }, 3), {
    starts_on:'2026-11-01', ends_before:'2026-12-01', per_page:25, include_owners:'1', page:3,
    search:'renewal', activity_type:'call', user_id:7, status:'open', customer_segment_id:4,
  });
});
test('empty filters are omitted rather than inferred from the current page', () => {
  assert.deepEqual(Object.keys(calendarPageQuery(query)).sort(), ['starts_on','ends_before','page','per_page','include_owners'].sort());
});
test('requests use captured account and an abort signal', async () => {
  let args; const h=harness(async (...a) => { args=a; return reply(); });
  assert.equal(await h.reader.load(query), true);
  assert.equal(args[0],1); assert(args[2].signal instanceof AbortSignal); assert.equal(h.state().rows[0].id,1);
});
test('clears old records and owner choices before the next request resolves', async () => {
  const later=defer(); let calls=0;const h=harness(() => ++calls===1 ? Promise.resolve(reply()) : later.promise);
  await h.reader.load(query);const task=h.reader.load(query,2);
  assert.deepEqual(h.state().rows,[]);assert.deepEqual(h.state().owners,[]);assert.equal(h.state().meta,null);assert(h.state().loading);
  later.resolve(reply([2]));await task;assert.equal(h.state().rows[0].id,2);
});
for (const status of [401,403,404,500]) test(`clears rows and counts after HTTP ${status}`, async () => {
  let fail=false;const h=harness(async()=> { if(fail)throw {response:{status}};return reply(); });
  await h.reader.load(query);fail=true;assert.equal(await h.reader.load(query),false);
  assert.deepEqual(h.state().rows,[]);assert.deepEqual(h.state().owners,[]);assert.equal(h.state().meta,null);
  assert.equal(h.state().error,status===500?'LOAD_FAILED':'ACCESS_DENIED');
});
test('late success cannot overwrite a new query', async () => {
  const one=defer(),two=defer();let calls=0;const h=harness(()=>++calls===1?one.promise:two.promise);
  const a=h.reader.load(query), b=h.reader.load({...query,filters:{search:'new'}});
  two.resolve(reply([2]));await b;one.resolve(reply([1]));assert.equal(await a,false);assert.equal(h.state().rows[0].id,2);
});
test('late denial cannot clear a newer authorized page', async () => {
  const one=defer();let calls=0;const h=harness(()=>++calls===1?one.promise:Promise.resolve(reply([2])));
  const task=h.reader.load(query);await h.reader.load(query);one.reject({response:{status:403}});await task;
  assert.equal(h.state().rows[0].id,2);assert.equal(h.state().error,null);
});
test('account or capability changes invalidate an in-flight response', async () => {
  const one=defer();const h=harness(()=>one.promise);const task=h.reader.load(query);
  h.setIdentity('account2:actor7:readonly');h.reader.clear();one.resolve(reply());assert.equal(await task,false);assert.deepEqual(h.state().rows,[]);
});
test('disposal prevents late responses and later loads', async () => {
  const one=defer();let calls=0;const h=harness(()=>{calls++;return one.promise;});const task=h.reader.load(query);
  h.reader.dispose();one.resolve(reply());await task;assert.deepEqual(h.state().rows,[]);
  assert.equal(await h.reader.load(query),false);assert.equal(calls,1);
});
test('new authorized success clears a previous denial',async()=>{
  let fail=true;const h=harness(async()=>{if(fail)throw {response:{status:403}};return reply();});
  await h.reader.load(query);fail=false;await h.reader.load(query);assert.equal(h.state().error,null);assert.equal(h.state().rows.length,1);
});
for (const body of [null,[],{data:[],meta:{}},{data:[{id:1},{id:1}],meta:{total:2,page:1,per_page:25,pages:1}},
 {data:[],meta:{total:100,page:1,per_page:25,pages:1}}, {data:[{id:'1'}],meta:{total:1,page:1,per_page:25,pages:1}}]) {
 test(`rejects malformed page ${JSON.stringify(body)}`,async()=>{const h=harness(async()=>({data:body}));assert.equal(await h.reader.load(query),false);assert.equal(h.state().error,'LOAD_FAILED');assert.deepEqual(h.state().rows,[]);});
}
test('accepts clamped server page after records are removed',async()=>{const h=harness(async()=>reply([1]));await h.reader.load(query,99);assert.equal(h.state().meta.page,1);});
test('zero is a valid authorized count, not an unavailable value',async()=>{const h=harness(async()=>reply([]));await h.reader.load(query);assert.equal(h.state().meta.total,0);assert.equal(h.state().error,null);});
test('invalid account prevents any transport call',async()=>{let count=0;const h=harness(async()=>{count++;return reply();});for(const accountId of [false,'../2',[],0,-1,'9007199254740992'])assert.equal(await h.reader.load({...query,accountId}),false);assert.equal(count,0);});
test('filter changes use a cloned request; callers cannot mutate an in-flight query',async()=>{let args;const wait=defer();const h=harness((...a)=>{args=a;return wait.promise;});const q={...query,filters:{search:'original'}};const task=h.reader.load(q);q.filters.search='changed';assert.equal(args[1].search,'original');wait.resolve(reply());await task;});
