import { ContractError } from '../helpers/contracts.js';
import { decodeRelated } from '../helpers/operationalContracts.js';
import { createOperationalSession } from '../helpers/operationalSession.js';
import {
  createServiceDeskSession,
  createSessionState,
} from '../helpers/session.js';
import { contextPayload, ticket, identity, httpError } from './fixtures.js';

// Native event payloads after Presenter/EventDataProjection. HTTP is controlled
// here; these tests are not a Rails, PostgreSQL or browser acceptance test.
const nativeEvents = {
  operational_rule_applied: {
    kind: 'sla_selection',
    rule_version_id: 1,
    rule_key: 'published-sla',
    rule_digest: 'a'.repeat(64),
    snapshot_id: 2,
  },
  clock_threshold_reached: {
    clock_id: 3,
    clock_kind: 'resolution',
    percent: 90,
    policy_digest: 'b'.repeat(64),
    elapsed_seconds: 540,
    budget_seconds: 600,
    due_at: '2026-10-09T11:00:00Z',
    breached: false,
    target_queue_id: 6,
  },
  clock_violated: {
    clock_id: 3,
    clock_kind: 'resolution',
    policy_digest: 'b'.repeat(64),
    elapsed_seconds: 601,
    budget_seconds: 600,
    due_at: '2026-10-09T11:00:00Z',
    observed_at: '2026-10-09T11:00:01Z',
  },
  approval_escalated: { approval_id: 4, history_index: 1 },
  resource_linked: { resource_id: 5, resource_kind: 'asset' },
  resource_updated: {
    resource_id: 5,
    resource_kind: 'asset',
    history_index: 1,
  },
  resource_archived: {
    resource_id: 5,
    resource_kind: 'asset',
    history_index: 2,
  },
  notification_resend_requested: {
    original_delivery_id: 7,
    delivery_id: 8,
    reason: 'Explicit reviewed retry',
  },
};

const row = (eventType, data = nativeEvents[eventType], extra = {}) => ({
  id: '300',
  account_id: '1',
  unit_id: '10',
  ticket_id: '20',
  event_type: eventType,
  data,
  permissions: { show: true },
  created_at: '2026-10-09T11:00:01Z',
  author: { id: '7', name: 'Synthetic operator' },
  ...extra,
});
const envelope = items => ({
  contract_version: 1,
  account_id: '1',
  ticket_id: '20',
  kind: 'events',
  items,
  meta: { page: 1, per_page: 20, total: items.length },
});
const request = { page: 1, per_page: 20 };
const decode = payload =>
  decodeRelated(payload, contextPayload(), ticket(), 'events', request);

export function registerTicketHistoryCases(test, assert) {
  Object.entries(nativeEvents).forEach(([eventType, data]) => {
    test(`history accepts the native ${eventType} projection`, () => {
      const original = envelope([row(eventType)]);
      const decoded = decode(original);
      assert.equal(decoded.items[0].event_type, eventType);
      assert.deepEqual(decoded.items[0].data, data);
      assert.equal(decoded.items[0].id, '300');
    });

    test(`history keeps redacted ${eventType} data empty`, () => {
      const decoded = decode(envelope([row(eventType, {}, { author: null })]));
      assert.deepEqual(decoded.items[0].data, {});
      assert.equal(decoded.items[0].author, null);
    });

    test(`history filters extra ${eventType} fields immutably`, () => {
      const supplied = {
        ...data,
        internal_body: 'synthetic protected field',
        notification_fields: { recipient: 'synthetic-only' },
      };
      const original = envelope([row(eventType, supplied)]);
      const decoded = decode(original);
      assert.deepEqual(decoded.items[0].data, data);
      assert.equal(
        original.items[0].data.internal_body,
        'synthetic protected field'
      );
      assert.deepEqual(original.items[0].data.notification_fields, {
        recipient: 'synthetic-only',
      });
    });
  });

  test('history accepts old and current native events together', () => {
    const rows = [row('ticket_created', { status_id: 1 })];
    Object.entries(nativeEvents).forEach(([eventType, data], index) => {
      rows.push(row(eventType, data, { id: String(301 + index) }));
    });
    const decoded = decode(envelope(rows));
    assert.deepEqual(
      decoded.items.map(item => item.event_type),
      rows.map(item => item.event_type)
    );
    assert.deepEqual(decoded.meta, { page: 1, per_page: 20, total: 9 });
  });

  test('unknown event types are still rejected, not silently accepted', () => {
    assert.throws(
      () => decode(envelope([row('unknown_future_event', {})])),
      ContractError
    );
  });

  [
    { account_id: '2' },
    { unit_id: '99' },
    { ticket_id: '21' },
    { permissions: { show: false } },
    { permissions: {} },
    { data: null },
    { data: [] },
  ].forEach(change => {
    test(`history rejects ${JSON.stringify(change)}`, () => {
      assert.throws(
        () =>
          decode(
            envelope([row('operational_rule_applied', undefined, change)])
          ),
        ContractError
      );
    });
  });

  test('a foreign account envelope remains invalid', () => {
    assert.throws(
      () =>
        decode({
          ...envelope([row('operational_rule_applied')]),
          account_id: '2',
        }),
      ContractError
    );
  });

  test('duplicate history IDs remain invalid', () => {
    assert.throws(
      () =>
        decode(
          envelope([row('operational_rule_applied'), row('clock_violated')])
        ),
      ContractError
    );
  });

  test('native SLA history preserves the active session', async () => {
    const base = createServiceDeskSession(
      { context: async () => contextPayload() },
      createSessionState()
    );
    await base.start(identity);
    const context = base.state.context;
    let reads = 0;
    const operations = createOperationalSession(
      {
        related: async (accountId, ticketId, kind, query) => {
          reads += 1;
          assert.equal(accountId, '1');
          assert.equal(ticketId, '20');
          assert.equal(kind, 'events');
          assert.equal(query.page, 1);
          return envelope([row('operational_rule_applied')]);
        },
      },
      base
    );
    const key = 'ticket:activity:20:events';
    const result = await operations.read(key, 'events', {
      ticket: ticket(),
      query: request,
    });
    assert.equal(base.state.status, 'ready');
    assert.equal(base.state.context, context);
    assert.equal(operations.resource(key).status, 'ready');
    assert.equal(result.items[0].event_type, 'operational_rule_applied');
    assert.equal(reads, 1);
    assert.equal(operations.state.revision, 0);
    assert.deepEqual(operations.state.writes, {});
  });

  test('missing history permission still prevents the API read', async () => {
    const base = createServiceDeskSession(
      { context: async () => contextPayload() },
      createSessionState()
    );
    await base.start(identity);
    let reads = 0;
    const operations = createOperationalSession(
      {
        related: async () => {
          reads += 1;
          return envelope([]);
        },
      },
      base
    );
    const record = ticket();
    record.permissions.view_history = false;
    const result = await operations.read('history', 'events', {
      ticket: record,
      query: request,
    });
    assert.equal(result, null);
    assert.equal(reads, 0);
    assert.equal(operations.resource('history').status, 'denied');
  });

  [401, 403].forEach(status => {
    test(`server ${status} still clears protected context`, async () => {
      const base = createServiceDeskSession(
        { context: async () => contextPayload() },
        createSessionState()
      );
      await base.start(identity);
      const operations = createOperationalSession(
        {
          related: async () => {
            throw httpError(status);
          },
        },
        base
      );
      const result = await operations.read('history', 'events', {
        ticket: ticket(),
        query: request,
      });
      assert.equal(result, null);
      assert.equal(base.state.context, null);
      assert.equal(
        base.state.status,
        status === 401 ? 'unauthenticated' : 'denied'
      );
    });
  });
}
