import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import '../jrc_customers/service_desk_node_harness.mjs';
const { registerTicketHistoryCases } = await import(
  '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/ticketHistoryCases.js'
);
const { decodeRelated } = await import(
  '../../app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/operationalContracts.js'
);
const { contextPayload, ticket } = await import(
  '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/fixtures.js'
);
registerTicketHistoryCases(test, assert);

// Read the current, literal Ruby contract. No Rails, database or eval is used.
const readSource = path =>
  readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const presenter = readSource('app/serializers/jrc_service_desk/presenter.rb');
const types = readSource('app/models/jrc_service_desk/ticket_event.rb')
  .match(/TYPES = %w\[([\s\S]+?)\]\.freeze/)[1]
  .trim()
  .split(/\s+/);
const fields = Object.fromEntries(
  [
    ...presenter
      .match(/EVENT_FIELDS = \{([\s\S]+?)\n {2}\}\.freeze/)[1]
      .matchAll(/'([a-z_]+)'\s*=>\s*(?:%w\[([^\]]*)\]|(\[\]))/g),
  ].map(([, name, keys]) => [
    name,
    keys?.trim() ? keys.trim().split(/\s+/) : [],
  ])
);
const labels = JSON.parse(
  readSource('app/javascript/dashboard/i18n/locale/en/jrcServiceDesk.json')
).JRC_SERVICE_DESK.OPS.EVENTS;

test('every native event has a matching literal Presenter contract', () => {
  assert.equal(types.length, 29);
  assert.deepEqual(Object.keys(fields).sort(), [...types].sort());
});

test('history accepts precisely the native Presenter fields', () => {
  Object.entries(fields).forEach(([name, keys]) => {
    const data = Object.fromEntries(keys.map(key => [key, `synthetic-${key}`]));
    const payload = {
      contract_version: 1,
      account_id: '1',
      ticket_id: '20',
      kind: 'events',
      items: [
        {
          id: '300',
          account_id: '1',
          unit_id: '10',
          ticket_id: '20',
          created_at: '2026-10-09T11:00:01Z',
          author: null,
          permissions: { show: true },
          event_type: name,
          data: { ...data, not_in_native_contract: 'must-not-be-returned' },
        },
      ],
      meta: { total: 1, page: 1, per_page: 20 },
    };
    const result = decodeRelated(
      payload,
      contextPayload(),
      ticket(),
      'events',
      { page: 1, per_page: 20 }
    );
    assert.deepEqual(result.items[0].data, data, name);
  });
});

test('all native history events have a nonempty English label', () => {
  types.forEach(name => {
    assert.equal(typeof labels[name], 'string', name);
    assert.ok(labels[name].trim(), name);
  });
});
