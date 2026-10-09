import { describe, expect, it, vi } from 'vitest';
import { createOperationalSession } from '../operationalSession';
import { decodeContext } from '../contracts';
import {
  contextPayload,
  identity,
  detail,
  ticket,
} from '../../__tests__/fixtures';

const context = () => decodeContext(contextPayload(), identity);
const payload = () => ({
  unit_id: '10',
  ticket: { title: 'Opening issue', description: 'Evidence' },
  requestKey: 'same-opening-key',
  files: [{ name: 'evidence.txt', size: 4 }],
});
const response = change => ({
  contract_version: 1,
  account_id: '1',
  kind: 'notes',
  ticket_id: '20',
  item: {
    id: '5',
    account_id: '1',
    unit_id: '10',
    ticket_id: '20',
    created_at: '2026-10-08T12:00:00Z',
    permissions: { show: true },
    body: 'Evidence',
    visibility: 'internal',
    author: null,
    attachments: [
      {
        id: '6',
        filename: 'evidence.txt',
        byte_size: 4,
        scan_state: 'unavailable',
      },
    ],
    ...change,
  },
});
const setup = (change = {}, ackChange = {}) => {
  const order = [];
  const base = {
    state: { status: 'ready', context: context() },
    dispose() {
      this.state.context = null;
    },
  };
  const client = {
    create: vi.fn(async () => {
      order.push('POST ticket');
      return {
        contract_version: 1,
        account_id: '1',
        ticket_id: '20',
        operation: 'create',
        applied: true,
        opening_note_id: '5',
        ...ackChange,
      };
    }),
    ticket: vi.fn(async () => {
      order.push('GET ticket');
      return detail(
        ticket({ title: 'Opening issue', description: 'Evidence' })
      );
    }),
    relatedItem: vi.fn(async () => {
      order.push('GET note');
      return response(change);
    }),
  };
  return { client, order, operations: createOperationalSession(client, base) };
};
describe('R3 internal opening attachment persistence is independently read back', () => {
  it('confirms the scoped native internal note and exact uploaded count/name/size without claiming a clean scan', async () => {
    const { operations, client, order } = setup();
    expect(
      await operations.write('opening', 'create', payload())
    ).not.toBeNull();
    expect(order).toEqual(['POST ticket', 'GET ticket', 'GET note']);
    expect(client.relatedItem.mock.calls[0].slice(0, 4)).toEqual([
      '1',
      '20',
      'notes',
      '5',
    ]);
    expect(operations.mutation('opening').status).toBe('confirmed');
    operations.clear();
  });
  it('keeps outcome pending when the acknowledgement does not identify the actual opening note', async () => {
    const { operations, client } = setup({}, { opening_note_id: null });
    await operations.write('opening', 'create', payload());
    expect(operations.mutation('opening').status).toBe('readback_pending');
    expect(client.relatedItem).not.toHaveBeenCalled();
    operations.clear();
  });
  it.each([
    { body: 'Wrong body' },
    { visibility: 'customer' },
    { account_id: '2' },
    { unit_id: '11' },
    { attachments: [] },
    {
      attachments: [
        {
          id: '6',
          filename: 'different.txt',
          byte_size: 4,
          scan_state: 'clean',
        },
      ],
    },
    {
      attachments: [
        {
          id: '6',
          filename: 'evidence.txt',
          byte_size: 5,
          scan_state: 'clean',
        },
      ],
    },
  ])(
    'refuses a success-shaped mismatch instead of inventing a saved attachment: %j',
    async change => {
      const { operations } = setup(change);
      await operations.write('opening', 'create', payload());
      expect(operations.mutation('opening').status).toBe('readback_pending');
      operations.clear();
    }
  );
});
