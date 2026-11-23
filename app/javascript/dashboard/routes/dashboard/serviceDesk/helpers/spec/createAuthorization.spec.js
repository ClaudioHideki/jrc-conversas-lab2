import { describe, expect, it, vi } from 'vitest';
import { createServiceDeskSession } from '../session';
import { createOperationalSession } from '../operationalSession';
import {
  contextPayload,
  deferred,
  detail,
  fakeClient,
  httpError,
  identity,
  ticket,
} from '../../__tests__/fixtures';

describe('ticket creation authorization outcomes', () => {
  it.each([403, 422])(
    'keeps the module context after a rejected POST %s',
    async status => {
      const base = createServiceDeskSession(fakeClient());
      await base.start(identity);
      const context = base.state.context;
      const client = {
        create: vi.fn().mockRejectedValue(httpError(status)),
        ticket: vi.fn(),
      };
      const operations = createOperationalSession(client, base);
      const payload = {
        unit_id: '10',
        ticket: { title: 'Draft', description: 'Preserved' },
        requestKey: 'original-intent',
      };

      expect(await operations.write('opening', 'create', payload)).toBeNull();
      expect(base.state.status).toBe('ready');
      expect(base.state.context).toBe(context);
      expect(operations.mutation('opening').status).toBe(
        status === 403 ? 'forbidden' : 'invalid_input'
      );
      expect(payload.ticket).toEqual({
        title: 'Draft',
        description: 'Preserved',
      });
      expect(client.ticket).not.toHaveBeenCalled();
      operations.clear();
    }
  );

  it('expires the whole session on HTTP 401', async () => {
    const base = createServiceDeskSession(fakeClient());
    await base.start(identity);
    const operations = createOperationalSession(
      { create: vi.fn().mockRejectedValue(httpError(401)) },
      base
    );
    await operations.write('opening', 'create', {
      unit_id: '10',
      ticket: {},
      requestKey: 'expired',
    });
    expect(base.state.status).toBe('unauthenticated');
    expect(base.state.context).toBeNull();
    operations.clear();
  });

  it('never confirms a server readback that silently substitutes the legacy default for the selected recipient', async () => {
    const payload = contextPayload();
    payload.units[0].internal_intake = {
      requester: { name: 'Self', email: 'self@example.test' },
      primary: { id: '9', name: 'Legacy default' },
      observer: null,
      queue: { id: '6', name: 'Legacy queue' },
      assignees: [
        { id: '7', name: 'Selected recipient' },
        { id: '9', name: 'Legacy default' },
      ],
    };
    const base = createServiceDeskSession(
      fakeClient({ context: async () => payload })
    );
    await base.start(identity);
    const operations = createOperationalSession(
      {
        create: vi.fn(async () => ({
          contract_version: 1,
          account_id: '1',
          ticket_id: '20',
          operation: 'create',
          applied: true,
        })),
        ticket: vi.fn(async () =>
          detail(
            ticket({
              title: 'Draft',
              description: 'Preserved',
              assignee: { id: '9', name: 'Legacy default' },
            })
          )
        ),
      },
      base
    );
    expect(
      await operations.write('opening', 'create', {
        unit_id: '10',
        internal_request: true,
        requestKey: 'chosen-recipient',
        ticket: {
          title: 'Draft',
          description: 'Preserved',
          assignee_account_user_id: '7',
        },
      })
    ).toBeNull();
    expect(operations.mutation('opening').status).toBe('readback_pending');
    expect(operations.mutation('opening').ticket).toBeNull();
    expect(operations.state.revision).toBe(0);
    operations.clear();
  });

  it.each([null, { id: '90', name: 'Recipient queue' }])(
    'confirms an explicit internal recipient with their own queue %j',
    async queue => {
      const payload = contextPayload();
      payload.units[0].internal_intake = {
        requester: { id: '33', name: 'Self' },
        primary: null,
        observer: null,
        queue: { id: '6', name: 'Legacy queue' },
        assignees: [{ id: '7', name: 'Recipient' }],
      };
      const base = createServiceDeskSession(
        fakeClient({ context: async () => payload })
      );
      await base.start(identity);
      const pending = deferred();
      const client = {
        create: vi.fn(() => pending.promise),
        ticket: vi.fn(async () =>
          detail(
            ticket({
              title: 'Draft',
              description: 'Preserved',
              assignee: { id: '7', name: 'Recipient' },
              queue,
            })
          )
        ),
      };
      const operations = createOperationalSession(client, base);
      const input = {
        unit_id: '10',
        internal_request: true,
        ticket: {
          title: 'Draft',
          description: 'Preserved',
          assignee_account_user_id: '7',
        },
        requestKey: 'single-create',
      };
      const first = operations.write('opening', 'create', input);
      expect(await operations.write('opening', 'create', input)).toBeNull();
      expect(client.create).toHaveBeenCalledTimes(1);
      pending.resolve({
        contract_version: 1,
        account_id: '1',
        ticket_id: '20',
        applied: true,
        operation: 'create',
      });
      expect((await first)?.id).toBe('20');
      expect(operations.mutation('opening').status).toBe('confirmed');
      operations.clear();
    }
  );
});
