import assert from 'node:assert/strict';
import test from 'node:test';
import { projectTimeline, timelineBar } from '../../app/javascript/dashboard/routes/dashboard/jrcProjects/planningProjection.js';

test('timeline preserves the original project, tasks and milestone records without mutation', () => {
  const project = Object.freeze({ id: 1, name: 'Delivery', starts_on: '2026-10-01', due_on: '2026-10-31' });
  const parent = Object.freeze({ id: 10, title: 'Parent', due_on: '2026-10-10' });
  const child = Object.freeze({ id: 11, title: 'Child', parent_id: 10, starts_on: '2026-10-05', due_on: '2026-10-06' });
  const milestone = Object.freeze({ id: 10, name: 'Acceptance', due_on: '2026-10-20' });
  const result = projectTimeline(project, Object.freeze([parent, child]), Object.freeze([milestone]));
  assert.equal(result.rows.length, 4);
  assert.deepEqual(result.rows.map(row => row.kind), ['project', 'task', 'subtask', 'milestone']);
  assert.equal(result.rows[0].record, project);
  assert.equal(result.rows[1].record, parent);
  assert.equal(result.rows[2].record, child);
  assert.equal(result.rows[2].parent, parent);
  assert.equal(result.rows[3].record, milestone);
  assert.equal(new Set(result.rows.map(row => row.key)).size, 4);
});

test('timeline range includes dates outside tasks and handles one-day milestones', () => {
  const result = projectTimeline({ id: 1, name: 'Delivery', starts_on: '2026-10-01' }, [{ id: 2, title: 'Task', due_on: '2026-10-05' }], [{ id: 3, name: 'Acceptance', due_on: '2026-10-10' }]);
  assert.equal(result.range.end - result.range.start + 1, 10);
  assert.deepEqual(timelineBar(result.rows[0], result.range), { x: 0, width: 100 });
  assert.deepEqual(timelineBar(result.rows[2], result.range), { x: 900, width: 100 });
});

test('undated records remain visible without invented dates or bars', () => {
  const result = projectTimeline({ id: 1, name: 'Internal' }, [{ id: 2, title: 'Unscheduled', parent_id: 99 }], [{ id: 3, name: 'Unscheduled milestone' }]);
  assert.equal(result.rows.length, 3);
  assert.equal(result.range, null);
  assert.equal(result.rows[1].parent, null);
  assert.ok(result.rows.every(row => row.start === null && row.end === null && timelineBar(row, result.range) === null));
});

test('timeline bars preserve a task interval and do not invent milestone task links', () => {
  const result = projectTimeline({ id: 1, name: 'Delivery' }, [{ id: 2, title: 'Execution', starts_on: '2026-10-02', due_on: '2026-10-04' }], [{ id: 3, name: 'Complete', due_on: '2026-10-04' }]);
  assert.deepEqual(timelineBar(result.rows[1], result.range), { x: 0, width: 1000 });
  assert.equal(result.rows[2].record.task_id, undefined);
  assert.equal(result.rows[2].record.progress, undefined);
});
