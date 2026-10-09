import { normalizeQuery, queryWithinContext } from '../helpers/query.js';
import {
  SCREEN_CATALOG,
  ticketListQuery,
  metricQuery,
  displayedScope,
  dueState,
  namedReportValue,
} from '../helpers/screenExperience.js';
import {
  readLifecycleDraft,
  blankLifecycleDraft,
  blankTransition,
  patchLifecycleDraft,
  explicitInteger,
  lifecycleDraftIssues,
  simulateLifecycleDraft,
} from '../helpers/lifecycleDesigner.js';
import {
  historyFields,
  historyChanges,
  sameHistoryScope,
} from '../helpers/historyPresentation.js';
import { decodeBoard } from '../helpers/v2Projection.js';

const context = () => ({
  account_id: '1',
  units: [
    {
      id: '10',
      name: 'North',
      operator_company: { id: '3', name: 'Operator A' },
    },
    {
      id: '11',
      name: 'South',
      operator_company: { id: '4', name: 'Operator B' },
    },
  ],
});
const ticket = () => ({
  id: '20',
  account_id: '1',
  unit_id: '10',
  status: { id: '30', name: 'Working' },
  assignee: { id: '7', name: 'Agent' },
});
const event = data => ({
  account_id: '1',
  unit_id: '10',
  ticket_id: '20',
  data,
});
export function validDraft() {
  const d = JSON.parse(blankLifecycleDraft());
  d.sla.mode = 'calendar_snapshot';
  d.transitions = [
    {
      ...blankTransition(d),
      key: 'resolve-v1',
      action: 'resolve',
      from_status_ids: [30],
      to_status_id: 31,
      requirements: {
        note: true,
        solution: true,
        evidence: false,
        classification: false,
        fields: {
          reviewed: {
            type: 'boolean',
            label: 'Reviewed',
            required: true,
            equals: true,
          },
        },
      },
      clocks: {
        first_response: 'keep',
        attendance: 'complete',
        resolution: 'complete',
      },
    },
  ];
  return JSON.stringify(d);
}
export function registerScreenExperienceCases(test, assert) {
  test('catalogue maps all 22 areas without inventing another customer module', () => {
    assert.equal(SCREEN_CATALOG.length, 22);
    assert.equal(new Set(SCREEN_CATALOG.map(row => row.key)).size, 22);
    assert.equal(SCREEN_CATALOG[21].key, 'history');
    assert.equal(
      SCREEN_CATALOG.some(row => row.key === 'related'),
      false
    );
    assert.ok(SCREEN_CATALOG.every(Object.isFrozen));
  });
  Array.from([
    'active',
    'open',
    'waiting',
    'resolved',
    'closed',
    'cancelled',
  ]).forEach(phase => {
    test(`phase ${phase} is passed as a selector, not a grant`, () => {
      assert.equal(normalizeQuery({ phase }).phase, phase);
      assert.equal(
        normalizeQuery(metricQuery({ unit_id: '10', status_id: '20' }, phase))
          .phase,
        phase
      );
    });
  });
  test('metric total clears only status and phase and resets paging', () => {
    const q = {
      unit_id: '10',
      priority_id: '7',
      q: '#249',
      phase: 'waiting',
      status_id: '5',
      page: 4,
    };
    const next = metricQuery(q, 'total');
    assert.equal(next.page, 1);
    assert.equal(next.q, '#249');
    assert.equal(next.unit_id, '10');
    assert.equal(next.priority_id, '7');
    assert.equal(next.phase, undefined);
    assert.equal(next.status_id, undefined);
    assert.equal(q.page, 4);
  });
  test('unknown metric cannot add arbitrary filters', () =>
    assert.throws(() => metricQuery({}, '__proto__')));
  test('personal queue defaults to mine', () =>
    assert.equal(ticketListQuery('mine', {}).mine, 'true'));
  test('unassigned selection never also requests mine', () => {
    const result = ticketListQuery('mine', {
      assignment: 'unassigned',
      mine: 'true',
      unit_id: '10',
    });
    assert.equal(result.mine, undefined);
    assert.equal(result.assignment, 'unassigned');
    assert.equal(normalizeQuery(result).unit_id, '10');
  });
  test('ticket list does not drop a supplied mine filter', () =>
    assert.equal(ticketListQuery('tickets', { mine: 'true' }).mine, 'true'));
  Array.from([
    { phase: 'unpublished' },
    { phase: ['open'] },
    { assignment: 'any' },
    { assignment: 'unassigned', mine: 'true' },
    { admin: true },
  ]).forEach(q => {
    test(`invalid filter remains rejected ${JSON.stringify(q)}`, () =>
      assert.throws(() => normalizeQuery(q)));
  });
  test('phase and assignment do not bypass operator/unit authorization', () => {
    assert.equal(
      queryWithinContext(
        normalizeQuery({
          phase: 'active',
          assignment: 'unassigned',
          operator_company_id: '3',
          unit_id: '11',
        }),
        context()
      ),
      false
    );
    assert.equal(displayedScope(context(), 'foreign'), null);
    assert.equal(displayedScope(context(), '10').name, 'North');
  });
  test('board enforces requested operating company separately from owner', () => {
    const payload = {
      contract_version: 1,
      account_id: '1',
      kind: 'tasks',
      meta: { page: 1, per_page: 20, total: 1 },
      items: [
        {
          id: '8',
          account_id: '1',
          unit_id: '10',
          permissions: { show: true },
          title: 'Allowed',
          status: 'open',
          ticket_id: '20',
        },
      ],
    };
    assert.equal(
      decodeBoard(payload, context(), 'tasks', {
        page: 1,
        per_page: 20,
        operator_company_id: '3',
      }).items[0].id,
      '8'
    );
    assert.throws(() =>
      decodeBoard(payload, context(), 'tasks', {
        page: 1,
        per_page: 20,
        operator_company_id: '4',
      })
    );
  });
  test('due badge is advisory and does not flag concluded work or invalid time', () => {
    const due_at = '2026-10-09T10:00:00Z';
    const now = '2026-10-09T11:00:00Z';
    assert.equal(dueState({ due_at, status: 'open' }, now), 'overdue');
    assert.equal(dueState({ due_at, status: 'completed' }, now), 'none');
    assert.equal(dueState({ due_at: 'broken', status: 'open' }, now), 'none');
    assert.equal(dueState({ due_at, status: 'pending' }, due_at), 'scheduled');
  });
  test('report names come only from the authorized displayed scope', () => {
    const rows = [
      {
        account_id: '1',
        unit_id: '10',
        company: { id: '44', name: 'Visible customer' },
      },
      { account_id: '2', unit_id: '10', company: { id: '45', name: 'Hidden' } },
    ];
    assert.equal(
      namedReportValue('by_customer', '44', rows, context(), '10'),
      'Visible customer'
    );
    assert.equal(
      namedReportValue('by_customer', '45', rows, context(), '10'),
      null
    );
    assert.equal(
      namedReportValue('by_customer', '44', rows, context(), '11'),
      null
    );
    assert.equal(
      namedReportValue('by_unit', '99', rows, context(), '10'),
      null
    );
  });
  test('blank lifecycle draft never selects times, states, recipients or threshold defaults', () => {
    const d = JSON.parse(blankLifecycleDraft());
    assert.equal(d.sla.mode, '');
    assert.deepEqual(d.transitions, []);
    assert.deepEqual(d.sla.escalation_policy, {});
    assert.equal(d.reopen.window_seconds, null);
    assert.equal(d.reopen.allowed, false);
    assert.ok(lifecycleDraftIssues(JSON.stringify(d)).length);
  });
  test('valid lifecycle draft and selected transition can be previewed without writes', () => {
    const raw = validDraft();
    assert.deepEqual(lifecycleDraftIssues(raw), []);
    const rows = simulateLifecycleDraft(raw, '30');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].to_status_id, 31);
    assert.equal(raw, validDraft());
    assert.deepEqual(simulateLifecycleDraft(raw, '99'), []);
  });
  test('editing a visible field preserves every unrelated advanced requirement', () => {
    const raw = validDraft();
    const original = JSON.parse(raw);
    const updated = JSON.parse(
      patchLifecycleDraft(raw, ['transitions', 0, 'key'], 'resolve-v2')
    );
    assert.deepEqual(
      updated.transitions[0].requirements.fields,
      original.transitions[0].requirements.fields
    );
    assert.deepEqual(updated.sla, original.sla);
    assert.deepEqual(JSON.parse(raw), original);
    assert.equal(updated.transitions[0].key, 'resolve-v2');
  });
  Array.from([
    ['__proto__', 'polluted'],
    ['transitions', 0, 'constructor'],
    ['sla', 'new_unknown'],
    ['missing', 'key'],
    [],
  ]).forEach(path => {
    test(`invalid draft path ${JSON.stringify(path)}`, () =>
      assert.throws(() => patchLifecycleDraft(validDraft(), path, true)));
  });
  Array.from([
    'not json',
    'null',
    '{}',
    '{"schema_version":9}',
    JSON.stringify({ ...JSON.parse(validDraft()), transitions: [null] }),
  ]).forEach(malformed => {
    test(`malformed draft remains advanced-only ${malformed.slice(0, 35)}`, () =>
      assert.equal(readLifecycleDraft(malformed), null));
  });
  test('invalid transition and duplicate keys cannot get a successful local simulation', () => {
    const d = JSON.parse(validDraft());
    d.transitions.push({ ...d.transitions[0] });
    assert.ok(lifecycleDraftIssues(JSON.stringify(d)).includes('duplicates'));
    assert.deepEqual(simulateLifecycleDraft(JSON.stringify(d), 30), []);
  });
  test('first response completion and resolution from a different action are blocked locally', () => {
    const d = JSON.parse(validDraft());
    d.transitions[0].clocks.first_response = 'complete';
    assert.ok(lifecycleDraftIssues(JSON.stringify(d)).includes('clocks'));
    d.transitions[0].clocks.first_response = 'keep';
    d.transitions[0].action = 'close';
    assert.ok(lifecycleDraftIssues(JSON.stringify(d)).includes('clocks'));
  });
  test('not-applicable SLA never promises stopped or completed clocks', () => {
    const d = JSON.parse(validDraft());
    d.sla.mode = 'not_applicable';
    assert.ok(lifecycleDraftIssues(JSON.stringify(d)).includes('clocks'));
  });
  test('reopening without explicit contract fails local checks', () => {
    const d = JSON.parse(validDraft());
    d.reopen.allowed = true;
    assert.ok(lifecycleDraftIssues(JSON.stringify(d)).includes('reopen'));
  });
  test('integer editing rejects unsafe or coerced identities', () => {
    assert.equal(explicitInteger(''), null);
    assert.equal(explicitInteger('24'), 24);
    Array.from(['024', 0, -1, '1e3', '9007199254740993', true]).forEach(
      value => {
        assert.throws(() => explicitInteger(value));
      }
    );
  });
  test('human history uses matching authorized names and preserves raw event', () => {
    const e = event({
      status_id: '30',
      title: 'Visible',
      token: 'not a display field',
    });
    const initial = JSON.stringify(e);
    const rows = historyFields(e, ticket());
    assert.equal(rows.find(row => row.key === 'status_id').value, 'Working');
    assert.equal(
      rows.some(row => row.key === 'token'),
      false
    );
    assert.equal(JSON.stringify(e), initial);
  });
  test('historical reference is not replaced with the present status name', () => {
    assert.equal(
      historyFields(event({ status_id: '29' }), ticket())[0].value,
      '29'
    );
  });
  test('membership id is never mistaken for AccountUser identity', () => {
    assert.equal(
      historyFields(event({ assignee_membership_id: '7' }), ticket())[0].value,
      '7'
    );
  });
  Array.from(['account_id', 'unit_id', 'ticket_id']).forEach(field => {
    test(`history refuses foreign ${field}`, () => {
      const e = {
        ...event({ status_id: '30', changes: { title: ['A', 'B'] } }),
        [field]: '999',
      };
      assert.equal(sameHistoryScope(e, ticket()), false);
      assert.deepEqual(historyFields(e, ticket()), []);
      assert.deepEqual(historyChanges(e, ticket()), []);
    });
  });
  test('redacted fields are not inferred from current ticket and unknown changes remain hidden', () => {
    assert.deepEqual(historyFields(event({}), ticket()), []);
    assert.deepEqual(historyFields(event(null), ticket()), []);
    const e = event({
      changes: {
        title: ['A', 'B'],
        status: [null, 'open'],
        secret: ['old', 'new'],
        due_at: [{ secret: 1 }, 'later'],
      },
    });
    assert.deepEqual(
      historyChanges(e, ticket()).map(row => row.key),
      ['title', 'status']
    );
  });
}
