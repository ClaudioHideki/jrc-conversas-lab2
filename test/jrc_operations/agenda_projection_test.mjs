import assert from 'node:assert/strict';
import test from 'node:test';
import { agendaTarget, formatAgendaDue } from '../../app/javascript/dashboard/routes/dashboard/jrcOperations/agenda.js';

test('3E formats a date-only deadline without assigning time or shifting the day in any timezone', () => {
  for (const timeZone of ['America/Sao_Paulo', 'Pacific/Honolulu', 'Pacific/Kiritimati']) {
    const value = formatAgendaDue({ due: '2026-09-24', due_type: 'date' }, timeZone);
    assert.equal(value, '24/09/2026');
    assert.ok(!value.includes(':'));
  }
});

test('3E timed commitments display the actual instant in the account timezone across a UTC date boundary', () => {
  const item = { due: '2026-09-25T01:30:00Z', due_type: 'datetime' };
  assert.match(formatAgendaDue(item, 'America/Sao_Paulo'), /24\/09\/2026.*22:30/);
  assert.match(formatAgendaDue(item, 'UTC'), /25\/09\/2026.*01:30/);
  assert.match(formatAgendaDue(item, 'Asia/Tokyo'), /25\/09\/2026.*10:30/);
});

test('3E respects real offsets and daylight-saving transitions without browser timezone inference', () => {
  assert.match(formatAgendaDue({ due: '2026-03-08T06:30:00Z', due_type: 'datetime' }, 'America/New_York'), /01:30/);
  assert.match(formatAgendaDue({ due: '2026-03-08T07:30:00Z', due_type: 'datetime' }, 'America/New_York'), /03:30/);
  assert.equal(formatAgendaDue({ due: '2026-09-24T12:00:00-03:00', due_type: 'datetime' }, 'America/Sao_Paulo'), formatAgendaDue({ due: '2026-09-24T15:00:00Z', due_type: 'datetime' }, 'America/Sao_Paulo'));
});

test('3E Project links carry the original parent and task identifiers within the current account', () => {
  assert.deepEqual(agendaTarget({ kind: 'project_task', project_id: 30, task_id: 40, parent_id: 35 }, '7'), { name: 'jrc_projects_detail', params: { accountId: '7', projectId: 30 }, query: { taskId: 40 } });
});

test('3E Activity and FollowUp links use separate original IDs without converting either source', () => {
  assert.deepEqual(agendaTarget({ kind: 'crm_activity', activity_id: 9 }, 7), { name: 'crm_activities', params: { accountId: 7 }, query: { activityId: 9 } });
  assert.deepEqual(agendaTarget({ kind: 'crm_follow_up', follow_up_id: 9 }, 7), { name: 'crm_activities', params: { accountId: 7 }, query: { followUpId: 9 } });
});
