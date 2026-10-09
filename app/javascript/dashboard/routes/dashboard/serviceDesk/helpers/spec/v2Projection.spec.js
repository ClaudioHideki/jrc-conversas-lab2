import { describe, expect, it } from 'vitest';
import { decodeBoard, decodeSupervision } from '../v2Projection';
import { catalogueFields, catalogueAnswers } from '../catalogueFields';
const context = {
  account_id: '1',
  units: [{ id: '2' }],
  effective_permissions: [
    'jrc_service_desk_tickets_view_all',
    'jrc_service_desk_sla_view',
  ],
};
const query = { page: 1, per_page: 20 };
const board = () => ({
  contract_version: 1,
  account_id: '1',
  kind: 'tasks',
  meta: { page: 1, per_page: 20, total: 1 },
  items: [
    {
      id: '4',
      account_id: '1',
      unit_id: '2',
      ticket_id: '3',
      permissions: { show: true },
      title: 'Task',
      status: 'open',
    },
  ],
});
const supervision = () => ({
  sla: null,
  by_agent: [],
  capacity: [],
  evolution: [],
  top_categories: [],
  tasks: null,
  approvals: null,
  timezone: 'UTC',
});
describe('Service Desk V2 operational projections', () => {
  it('rejects a foreign unit or hidden row before rendering a board', () => {
    const payload = board();
    payload.items[0].unit_id = '9';
    expect(() => decodeBoard(payload, context, 'tasks', query)).toThrow();
    payload.items[0].unit_id = '2';
    payload.items[0].permissions.show = false;
    expect(() => decodeBoard(payload, context, 'tasks', query)).toThrow();
  });
  it('keeps only authorized board navigation fields', () => {
    const payload = board();
    payload.items[0].raw_secret = 'discarded';
    expect(
      decodeBoard(payload, context, 'tasks', query).items[0].ticket_id
    ).toBe('3');
    expect(
      JSON.stringify(decodeBoard(payload, context, 'tasks', query))
    ).not.toContain('discarded');
  });
  it('requires the fresh supervision grant and scopes every capacity record', () => {
    expect(() =>
      decodeSupervision(supervision(), {
        ...context,
        effective_permissions: [],
      })
    ).toThrow();
    const value = supervision();
    value.capacity = [
      {
        id: '7',
        unit_id: '9',
        name: 'Foreign',
        availability: 'available',
        capacity: 3,
        active_tickets: 1,
      },
    ];
    expect(() => decodeSupervision(value, context)).toThrow();
  });
  it('preserves false as an explicit required boolean answer and rejects missing or unknown answers', () => {
    const fields = catalogueFields([
      { key: 'restored', label: 'Restored?', type: 'boolean', required: true },
    ]);
    expect(catalogueAnswers(fields, { restored: false })).toEqual({
      restored: false,
    });
    expect(() => catalogueAnswers(fields, {})).toThrow();
    expect(() =>
      catalogueAnswers(fields, { restored: true, arbitrary: 'secret' })
    ).toThrow();
    expect(() =>
      catalogueFields([
        { key: '__proto__', label: 'Reserved', type: 'text', required: false },
      ])
    ).toThrow();
  });
});
