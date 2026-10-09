import test from 'node:test';
import assert from 'node:assert/strict';
import {
  rulesDefinition,
  deadlineDefinition,
  recurrenceDefinition,
  loadRules,
  integer,
  code,
  jsonObject,
  assertEnvelope,
  reportFilters,
} from '../../../app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/operationalRules.mjs';
import {
  parseTicketIds,
  batchAttributes,
  decodeBatchPreview,
  decodeRecurrences,
  decodeMetrics,
} from '../../../app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/operationalResults.mjs';
import { createTicketDraft } from '../../../app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/drafts.js';
const context = {
  account_id: '1',
  user_id: '2',
  units: [{ id: '10' }],
  effective_permissions: [
    'jrc_service_desk_customers_view',
    'jrc_service_desk_history_view',
    'jrc_service_desk_sla_view',
    'jrc_service_desk_conversations_view',
  ],
};
const envelope = { account_id: '1', unit_id: '10', contract_version: 1 };
const row = (extra = {}) => ({
  key: 'r1',
  precedence: '0',
  match: { inbox_id: '4' },
  target: '8',
  snapshot: {},
  ...extra,
});
const ticket = { id: '50', lock_version: 0 };
const batch = { action: 'link', tickets: [ticket] };
const preview = {
  ...envelope,
  preview: {
    action: 'link',
    receipt: 'signature',
    ticket_ids: ['50'],
    notes: [],
    expires_at: '2026-10-09T10:00:00Z',
  },
};

test('configuration integers are explicit and bounded', () => {
  assert.equal(integer('0', 0), 0);
  assert.equal(integer('20'), 20);
  [null, true, [], {}, '1.5', '-1', '01', '1e3', '9007199254740992'].forEach(
    value => assert.throws(() => integer(value))
  );
});
test('codes are bounded tokens, not expressions', () => {
  assert.equal(code('major-urgent.1'), 'major-urgent.1');
  ['', 'with space', '../path', ';exec', 'a'.repeat(65)].forEach(value =>
    assert.throws(() => code(value))
  );
});
test('routing produces native structured IDs and no fabricated defaults', () => {
  assert.deepEqual(rulesDefinition('routing', [row()]), {
    rules: [
      {
        key: 'r1',
        precedence: 0,
        match: { inbox_id: 4 },
        output: { queue_id: 8 },
      },
    ],
  });
  assert.throws(() => rulesDefinition('routing', [row({ precedence: '' })]));
  assert.throws(() => rulesDefinition('routing', [row({ target: '' })]));
});
test('rule count, duplicate keys and family are rejected', () => {
  assert.throws(() => rulesDefinition('routing', []));
  assert.throws(() => rulesDefinition('routing', [row(), row()]));
  assert.throws(() =>
    rulesDefinition(
      'routing',
      Array.from({ length: 101 }, (_, i) => row({ key: `k${i}` }))
    )
  );
  assert.throws(() => rulesDefinition('ruby', [row()]));
});
test('matrix requires both axes and preserves explicit precedence', () => {
  assert.throws(() => rulesDefinition('priority_matrix', [row()]));
  const value = rulesDefinition('priority_matrix', [
    row({ match: { impact: 'high', urgency: 'today' } }),
  ]);
  assert.deepEqual(value.rules[0].output, { priority_id: 8 });
  assert.equal(value.rules[0].match.impact, 'high');
});
test('native channel type is not executable syntax', () => {
  const value = rulesDefinition('routing', [
    row({ match: { channel_type: 'Channel::Whatsapp' } }),
  ]);
  assert.equal(value.rules[0].match.channel_type, 'Channel::Whatsapp');
  assert.throws(() =>
    rulesDefinition('routing', [
      row({ match: { channel_type: 'Kernel.eval' } }),
    ])
  );
});
test('rule editing round trip retains predicates/output', () => {
  const original = rulesDefinition('routing', [row()]);
  assert.deepEqual(rulesDefinition('routing', loadRules(original)), original);
});
test('JSON configuration rejects secrets and prototype keys recursively', () => {
  [
    'password',
    'api_key',
    'secret',
    'access_token',
    '__proto__',
    'constructor',
    'prototype',
  ].forEach(key => {
    assert.throws(() => jsonObject(`{"nested":[{"${key}":"test"}]}`));
  });
  assert.throws(() => jsonObject('[]'));
  assert.throws(() => jsonObject('null'));
  assert.throws(() => jsonObject('{"n":1e999}'));
  assert.deepEqual(jsonObject('{"clock":60}'), { clock: 60 });
});
test('snapshot fields must all be explicit', () => {
  assert.throws(() => rulesDefinition('sla_selection', [row()]));
  const snapshot = Object.fromEntries(
    [
      'source_system',
      'source_reference',
      'source_version',
      'policy_key',
      'policy_version',
      'calendar_key',
      'calendar_version',
    ].map(k => [k, 'v1'])
  );
  Object.assign(snapshot, {
    timezone: 'UTC',
    calendar_scope: 'unit',
    policy_conditions:
      '{"clock_budgets_seconds":{"first_response":60,"resolution":600}}',
    contract_conditions: '{}',
    calendar_conditions: '{}',
  });
  const original = rulesDefinition('sla_selection', [row({ snapshot })]);
  assert.deepEqual(
    rulesDefinition('sla_selection', loadRules(original)),
    original
  );
});
test('deadline configuration has one explicit target and timing', () => {
  const draft = {
    executor_account_user_id: '4',
    after_due_seconds: '0',
    new_due_seconds: '60',
    target_kind: 'approver_account_user_id',
    target_value: '7',
    reason: 'Escalate after due',
  };
  assert.deepEqual(deadlineDefinition(draft).target, {
    approver_account_user_id: 7,
  });
  assert.throws(() => deadlineDefinition({ ...draft, new_due_seconds: '0' }));
  assert.throws(() =>
    deadlineDefinition({ ...draft, executor_account_user_id: '' })
  );
  assert.throws(() =>
    deadlineDefinition({
      ...draft,
      target_kind: 'approver_role',
      target_value: 'CEO',
    })
  );
  assert.deepEqual(
    deadlineDefinition({
      ...draft,
      target_kind: 'approver_role',
      target_value: 'agent',
    }).target,
    { approver_role: 'agent' }
  );
});
test('recurrence has bounded explicit dimensions and window', () => {
  const draft = {
    window_days: '30',
    minimum_occurrences: '3',
    group_by: ['company_id', 'service_id'],
  };
  assert.deepEqual(recurrenceDefinition(draft), {
    window_days: 30,
    minimum_occurrences: 3,
    group_by: ['company_id', 'service_id'],
  });
  [[], ['sql'], ['company_id', 'company_id']].forEach(group_by =>
    assert.throws(() => recurrenceDefinition({ ...draft, group_by }))
  );
  assert.throws(() => recurrenceDefinition({ ...draft, window_days: '367' }));
});
test('envelopes reject account and unit changes', () => {
  assert.equal(assertEnvelope(envelope, context, '10'), envelope);
  assert.throws(() =>
    assertEnvelope({ ...envelope, account_id: '2' }, context, '10')
  );
  assert.throws(() =>
    assertEnvelope({ ...envelope, unit_id: '11' }, context, '10')
  );
  assert.throws(() =>
    assertEnvelope(envelope, { ...context, units: [] }, '10')
  );
});
test('report filters require explicit offset and half-open order', () => {
  assert.deepEqual(
    reportFilters({
      service_id: '2',
      from: '2026-10-01T00:00:00-03:00',
      to: '2026-10-02T00:00:00-03:00',
    }),
    {
      service_id: '2',
      from: '2026-10-01T00:00:00-03:00',
      to: '2026-10-02T00:00:00-03:00',
    }
  );
  assert.throws(() => reportFilters({ from: '2026-10-01' }));
  assert.throws(() => reportFilters({ sql: 'anything' }));
  assert.throws(() =>
    reportFilters({ from: '2026-10-02T00:00:00Z', to: '2026-10-01T00:00:00Z' })
  );
  assert.throws(() => reportFilters({ per_page: 101 }));
});
test('batch ticket selection is finite and unique', () => {
  assert.deepEqual(parseTicketIds('1, 2;3\n4'), ['1', '2', '3', '4']);
  [
    '',
    '1,1',
    '0',
    '1e2',
    '#3',
    '1;rm',
    Array.from({ length: 101 }, (_, i) => i + 1).join(','),
  ].forEach(value => assert.throws(() => parseTicketIds(value)));
});
test('batch supports only link/internal note/silent note', () => {
  assert.deepEqual(batchAttributes('link', [ticket], '', 'internal'), batch);
  assert.equal(
    batchAttributes(
      'note',
      [ticket],
      'Approved progress',
      'public_without_notification'
    ).visibility,
    'public_without_notification'
  );
  ['customer', 'technical_team'].forEach(audience =>
    assert.throws(() => batchAttributes('note', [ticket], 'x', audience))
  );
  assert.throws(() => batchAttributes('close', [ticket], '', 'internal'));
  assert.throws(() => batchAttributes('note', [ticket], ' ', 'internal'));
  assert.throws(() =>
    batchAttributes('link', [ticket, ticket], '', 'internal')
  );
});
test('preview is bound to exact selected tickets', () => {
  assert.equal(
    decodeBatchPreview(preview, context, '10', batch).receipt,
    'signature'
  );
  assert.throws(() =>
    decodeBatchPreview(
      { ...preview, preview: { ...preview.preview, ticket_ids: ['51'] } },
      context,
      '10',
      batch
    )
  );
  assert.throws(() =>
    decodeBatchPreview({ ...preview, account_id: '2' }, context, '10', batch)
  );
});
test('note preview cannot change body/audience or omit individual receipts', () => {
  const noteBatch = batchAttributes('note', [ticket], 'Progress', 'internal');
  const source = {
    ...envelope,
    preview: {
      ...preview.preview,
      action: 'note',
      notes: [
        {
          ticket_id: '50',
          body: 'Progress',
          visibility: 'internal',
          receipt: 'note-proof',
        },
      ],
    },
  };
  assert.equal(
    decodeBatchPreview(source, context, '10', noteBatch).notes[0].body,
    'Progress'
  );
  assert.throws(() =>
    decodeBatchPreview(source, context, '10', { ...noteBatch, body: 'Altered' })
  );
  assert.throws(() =>
    decodeBatchPreview(
      { ...source, preview: { ...source.preview, notes: [] } },
      context,
      '10',
      noteBatch
    )
  );
});
test('recurrence payload cannot include inconsistent IDs or foreign envelope', () => {
  const source = {
    ...envelope,
    recurrence: {
      enabled: true,
      truncated: false,
      groups: [
        {
          key: 'a'.repeat(64),
          count: 2,
          ticket_ids: ['1', '2'],
          unlinked_ticket_ids: ['2'],
        },
      ],
    },
  };
  assert.equal(decodeRecurrences(source, context, '10').groups[0].count, 2);
  assert.throws(() =>
    decodeRecurrences({ ...source, unit_id: '2' }, context, '10')
  );
  const bad = structuredClone(source);
  bad.recurrence.groups[0].unlinked_ticket_ids = ['3'];
  assert.throws(() => decodeRecurrences(bad, context, '10'));
});
const metrics = () => ({
  observed_at: '2026-10-09T10:00:00Z',
  cohort: 'authorized_tickets_opened_in_half_open_period',
  total: 2,
  ...Object.fromEntries(
    [
      'by_unit',
      'by_service',
      'by_origin',
      'by_category',
      'by_priority',
      'by_customer',
    ].map(key => [key, { items: [], truncated: false }])
  ),
  by_channel: [],
  reopen: {
    events: 1,
    tickets: 1,
    cohort_ticket_count: 2,
    closed_tickets: 1,
    cohort_reopen_percentage: 50,
  },
  sla: Object.fromEntries(
    ['first_response', 'attendance', 'resolution'].map(kind => [
      kind,
      {
        observed: 0,
        completed: 0,
        mean_elapsed_seconds: null,
        completed_breached: 0,
        running_overdue: 0,
      },
    ])
  ),
  fcr: { value: null },
  quality: { value: null },
});
test('metrics preserve absence, authorized counts and null means', () => {
  assert.equal(
    decodeMetrics(metrics(), context).sla.attendance.mean_elapsed_seconds,
    null
  );
  assert.equal(
    decodeMetrics(metrics(), context).reopen.cohort_reopen_percentage,
    50
  );
  assert.throws(() =>
    decodeMetrics(metrics(), { ...context, effective_permissions: [] })
  );
  const safe = metrics();
  safe.by_customer = null;
  safe.by_channel = null;
  safe.reopen = null;
  safe.sla = null;
  assert.equal(
    decodeMetrics(safe, { ...context, effective_permissions: [] }).sla,
    null
  );
});
test('metrics reject invented FCR and invalid counts', () => {
  const input = metrics();
  input.fcr.value = 100;
  assert.throws(() => decodeMetrics(input, context));
  input.fcr.value = null;
  input.total = -1;
  assert.throws(() => decodeMetrics(input, context));
});
const unit = {
  id: '10',
  permissions: { create_ticket: true },
  initial_status: { id: '1' },
};
const draft = {
  unit_id: '10',
  title: 'Example',
  description: '',
  requester_id: '5',
  priority_id: '7',
  queue_id: '2',
  team_id: '3',
  assignee_id: '4',
};
test('legacy draft stays unchanged when new controls are omitted', () => {
  assert.deepEqual(createTicketDraft(draft, unit, 'key').ticket, {
    title: 'Example',
    description: '',
    requester_id: '5',
    priority_id: '7',
    status_id: '1',
    queue_id: '2',
    team_id: '3',
    assignee_account_user_id: '4',
  });
});
test('matrix draft sends both codes without fabricating priority', () => {
  const result = createTicketDraft(
    { ...draft, impact_code: 'major', urgency_code: 'urgent' },
    unit,
    'key'
  );
  assert.equal(result.ticket.impact_code, 'major');
  assert.equal(Object.hasOwn(result.ticket, 'priority_id'), false);
  assert.throws(() =>
    createTicketDraft({ ...draft, impact_code: 'major' }, unit, 'key')
  );
});
test('routing opt-in omits manual assignment but preserves conversation', () => {
  const result = createTicketDraft(
    { ...draft, use_channel_routing: true, conversation_id: '9' },
    unit,
    'key'
  );
  ['queue_id', 'team_id', 'assignee_account_user_id'].forEach(key =>
    assert.equal(Object.hasOwn(result.ticket, key), false)
  );
  assert.equal(result.conversation_id, '9');
  assert.equal(result.ticket.priority_id, '7');
});
