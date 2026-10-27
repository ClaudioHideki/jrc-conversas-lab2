import { describe, expect, it, vi } from 'vitest';
import { createServiceDeskSession } from '../session';
import { createOperationalSession } from '../operationalSession';
import {
  collection,
  deferred,
  detail,
  fakeClient,
  httpError,
  identity,
  ticket,
} from '../../__tests__/fixtures';

const dashboard = (total = 1, filters = {}) => ({
  contract_version: 1,
  account_id: '1',
  dashboard: {
    total,
    active: total,
    phases: { open: total, waiting: 0, resolved: 0, closed: 0, cancelled: 0 },
    by_status: [{ id: '1', name: 'Open fixture', phase: 'open', count: total }],
    filters,
    generated_at: '2026-10-26T12:00:00Z',
  },
});

describe('authorized background refresh', () => {
  it('keeps confirmed list rows while pending and replaces them on success', async () => {
    const response = deferred();
    const client = fakeClient({ list: vi.fn(async () => collection()) });
    const session = createServiceDeskSession(client);
    await session.start(identity);
    await session.load('list', 'tickets');
    const previous = session.resource('list');
    client.list.mockReturnValueOnce(response.promise);

    const refresh = session.load('list', 'tickets', {}, null, {
      background: true,
    });
    expect(session.resource('list').status).toBe('ready');
    expect(session.resource('list').items).toEqual(previous.items);
    response.resolve(collection([ticket({ title: 'Updated ticket' })]));
    await refresh;
    expect(session.resource('list').items[0].title).toBe('Updated ticket');
  });

  it('keeps a confirmed empty list while a background refresh is pending', async () => {
    const response = deferred();
    const client = fakeClient({ list: vi.fn(async () => collection([])) });
    const session = createServiceDeskSession(client);
    await session.start(identity);
    await session.load('list', 'tickets');
    client.list.mockReturnValueOnce(response.promise);
    const refresh = session.load('list', 'tickets', {}, null, {
      background: true,
    });
    expect(session.resource('list').status).toBe('empty');
    response.resolve(collection());
    await refresh;
    expect(session.resource('list').status).toBe('ready');
  });

  it.each([false, true])(
    'clears old filters for a new query even with background=%s',
    async background => {
      const response = deferred();
      const client = fakeClient({ list: vi.fn(async () => collection()) });
      const session = createServiceDeskSession(client);
      await session.start(identity);
      await session.load('list', 'tickets');
      client.list.mockReturnValueOnce(response.promise);
      const refresh = session.load(
        'list',
        'tickets',
        { q: 'different' },
        null,
        { background }
      );
      expect(session.resource('list').status).toBe('loading');
      expect(session.resource('list').items).toEqual([]);
      response.resolve(collection());
      await refresh;
    }
  );

  it.each([401, 403])(
    'clears retained rows after authoritative HTTP %s',
    async code => {
      const response = deferred();
      const client = fakeClient({ list: vi.fn(async () => collection()) });
      const session = createServiceDeskSession(client);
      await session.start(identity);
      await session.load('list', 'tickets');
      client.list.mockReturnValueOnce(response.promise);
      const refresh = session.load('list', 'tickets', {}, null, {
        background: true,
      });
      response.reject(httpError(code));
      await refresh;
      expect(session.state.context).toBeNull();
      expect(session.state.resources).toEqual({});
    }
  );

  it('does not retain the selected ticket while another ticket is requested', async () => {
    const response = deferred();
    const client = fakeClient({ ticket: vi.fn(async () => detail()) });
    const session = createServiceDeskSession(client);
    await session.start(identity);
    await session.load('preview', 'tickets', {}, '20');
    client.ticket.mockReturnValueOnce(response.promise);
    const refresh = session.load('preview', 'tickets', {}, '21', {
      background: true,
    });
    expect(session.resource('preview').record).toBeNull();
    response.resolve(detail(ticket({ id: '21' })));
    await refresh;
    expect(session.resource('preview').record.id).toBe('21');
  });

  it('clears on identity change and rejects a late retained-list response', async () => {
    const response = deferred();
    const client = fakeClient({ list: vi.fn(async () => collection()) });
    const session = createServiceDeskSession(client);
    await session.start(identity);
    await session.load('list', 'tickets');
    client.list.mockReturnValueOnce(response.promise);
    const refresh = session.load('list', 'tickets', {}, null, {
      background: true,
    });
    await session.start({ ...identity, enabled: false });
    expect(session.state.resources).toEqual({});
    response.resolve(collection());
    await refresh;
    expect(session.state.resources).toEqual({});
    expect(session.state.status).toBe('disabled');
  });

  it('keeps the completed dashboard visible through a same-scope refresh', async () => {
    const response = deferred();
    const base = createServiceDeskSession(fakeClient());
    await base.start(identity);
    const client = { dashboard: vi.fn(async () => dashboard()) };
    const operations = createOperationalSession(client, base);
    await operations.read('kpis', 'dashboard');
    client.dashboard.mockReturnValueOnce(response.promise);
    const refresh = operations.read('kpis', 'dashboard', { background: true });
    expect(operations.resource('kpis').status).toBe('ready');
    expect(operations.resource('kpis').data.total).toBe(1);
    response.resolve(dashboard(2));
    await refresh;
    expect(operations.resource('kpis').data.total).toBe(2);
  });

  it('invalidates dashboard content on authoritative denial', async () => {
    const response = deferred();
    const base = createServiceDeskSession(fakeClient());
    await base.start(identity);
    const client = { dashboard: vi.fn(async () => dashboard()) };
    const operations = createOperationalSession(client, base);
    await operations.read('kpis', 'dashboard');
    client.dashboard.mockReturnValueOnce(response.promise);
    const refresh = operations.read('kpis', 'dashboard', { background: true });
    response.reject(httpError(403));
    await refresh;
    expect(base.state.context).toBeNull();
    expect(operations.resource('kpis').data).toBeNull();
  });

  it('does not keep dashboard counts from a different filter', async () => {
    const response = deferred();
    const base = createServiceDeskSession(fakeClient());
    await base.start(identity);
    const client = { dashboard: vi.fn(async () => dashboard()) };
    const operations = createOperationalSession(client, base);
    await operations.read('kpis', 'dashboard');
    client.dashboard.mockReturnValueOnce(response.promise);
    const refresh = operations.read('kpis', 'dashboard', {
      query: { unit_id: '10' },
      background: true,
    });
    expect(operations.resource('kpis').status).toBe('loading');
    expect(operations.resource('kpis').data).toBeNull();
    response.resolve(dashboard(2, { unit_id: '10' }));
    await refresh;
  });
});
