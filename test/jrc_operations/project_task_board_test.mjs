import assert from 'node:assert/strict';
import test from 'node:test';
import { filterProjectTasks, persistTaskMove, projectTaskStatuses } from '../../app/javascript/dashboard/routes/dashboard/jrcProjects/taskBoard.js';
const today = '2026-09-24';
const tasks = [
  { id: 1, title: 'Install gateway', assignee_id: 7, status: 'in_progress', priority: 'high', labels: ['Telefonia'], due_on: '2026-09-24' },
  { id: 2, title: 'Review gateway', assignee_id: 8, status: 'review', priority: 'medium', labels: ['Infra'], due_on: '2026-09-23' },
  { id: 3, title: 'Done', assignee_id: null, status: 'completed', priority: 'low', labels: [], due_on: '2026-09-20' },
  { id: 4, title: 'Canceled', assignee_id: null, status: 'canceled', priority: 'urgent', labels: [], due_on: '2026-09-20' },
  { id: 5, title: 'Backlog', assignee_id: 7, status: 'backlog', priority: 'medium', labels: [], due_on: null },
  { id: 6, title: 'Blocked', assignee_id: 7, status: 'blocked', priority: 'high', labels: ['Telefonia'], due_on: '2026-09-30' },
  { id: 7, title: 'Future', assignee_id: 8, status: 'backlog', priority: 'low', labels: [], due_on: '2026-10-01' },
];
const ids = filters => filterProjectTasks(tasks, filters, today).map(task => task.id);

test('task status taxonomy contains exactly the six persisted statuses', () => {
  assert.deepEqual(Object.keys(projectTaskStatuses), ['backlog', 'in_progress', 'review', 'completed', 'blocked', 'canceled']);
});
test('all six task filters combine on one collection', () => {
  assert.deepEqual(ids({ q: ' GATEWAY ', assignee: '7', status: 'in_progress', priority: 'high', due: 'today', label: 'telefonia' }), [1]);
});
test('each categorical or title filter works independently and empty results stay empty', () => {
  assert.deepEqual(ids({ q: 'gateway' }), [1, 2]);
  assert.deepEqual(ids({ assignee: '7' }), [1, 5, 6]);
  assert.deepEqual(ids({ status: 'blocked' }), [6]);
  assert.deepEqual(ids({ priority: 'high' }), [1, 6]);
  assert.deepEqual(ids({ label: 'INFRA' }), [2]);
  assert.deepEqual(ids({ label: 'missing' }), []);
});
test('deadline filters use date-only boundaries and overdue excludes finished tasks', () => {
  assert.deepEqual(ids({ due: 'overdue' }), [2]);
  assert.deepEqual(ids({ due: 'today' }), [1]);
  assert.deepEqual(ids({ due: 'week' }), [1, 6]);
  assert.deepEqual(ids({ due: 'none' }), [5]);
});
test('filtering preserves source objects and their persisted order without mutations', () => {
  const snapshot = structuredClone(tasks);
  const filtered = filterProjectTasks(tasks, {}, today);
  assert.notEqual(filtered, tasks);
  assert.equal(filtered[0], tasks[0]);
  assert.deepEqual(filtered, tasks);
  filterProjectTasks(tasks, { label: 'Telefonia' }, today);
  assert.deepEqual(tasks, snapshot);
});
test('successful move waits for the API then reloads the persisted state', async () => {
  const events = []; let finish;
  const pending = persistTaskMove(() => new Promise(resolve => { events.push('send'); finish = resolve; }), async () => { events.push('reload'); });
  assert.deepEqual(events, ['send']);
  finish(); await pending;
  assert.deepEqual(events, ['send', 'reload']);
});
test('rejected move reloads before exposing the original API error', async () => {
  const error = new Error('WIP limit'); const events = [];
  await assert.rejects(persistTaskMove(async () => { events.push('send'); throw error; }, async () => { events.push('reload'); }), value => value === error);
  assert.deepEqual(events, ['send', 'reload']);
});
test('failure to refresh is exposed as a failure and never reported as restored', async () => {
  const rejected = new Error('Dependency pending'); const refresh = new Error('Network failure');
  await assert.rejects(persistTaskMove(async () => { throw rejected; }, async () => { throw refresh; }), error => {
    assert.deepEqual(error.errors, [rejected, refresh]); return true;
  });
  await assert.rejects(persistTaskMove(async () => {}, async () => { throw refresh; }), error => error === refresh);
});
