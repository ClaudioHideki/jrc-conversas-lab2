import { afterEach, describe, expect, it, vi } from 'vitest';
import { createServiceDeskSession } from '../session';
import { createOperationalSession } from '../operationalSession';
import {
  collection,
  contextPayload,
  deferred,
  httpError,
  identity,
} from '../../__tests__/fixtures';

const dashboardPayload = () => ({
  contract_version: 1,
  account_id: '1',
  dashboard: {
    total: 1,
    active: 1,
    phases: { open: 1, waiting: 0, resolved: 0, closed: 0, cancelled: 0 },
    by_status: [{ id: '1', name: 'Open fixture', phase: 'open', count: 1 }],
    filters: {},
    generated_at: '2026-10-26T12:00:00Z',
    supervision: {
      sla: null,
      by_agent: [
        {
          id: '4',
          account_user_id: '7',
          unit_id: '10',
          name: 'Synthetic operator',
          count: 1,
        },
      ],
      capacity: [
        {
          id: '4',
          unit_id: '10',
          name: 'Synthetic operator',
          availability: 'available',
          capacity: 3,
          active_tickets: 1,
        },
      ],
      evolution: [{ date: '2026-10-26', count: 1 }],
      top_categories: [{ id: null, name: null, count: 1 }],
      tasks: { open: 0, overdue: 0 },
      approvals: { pending: 0, overdue: 0 },
      timezone: 'UTC',
      raw_secret: 'must never reach the view model',
    },
  },
});

const supervisorContext = () => {
  const context = contextPayload();
  context.capabilities.reports = { index: true };
  context.effective_permissions = ['jrc_service_desk_tickets_view_all'];
  return context;
};

const sessions = [];
afterEach(() => {
  sessions.forEach(({ base, operations }) => {
    operations.clear();
    base.dispose();
  });
  sessions.length = 0;
});

async function openSession({
  context = supervisorContext(),
  payload = dashboardPayload(),
  dashboard = async () => payload,
} = {}) {
  const nativeClient = {
    context: vi.fn(async () => context),
    list: vi.fn(async () => collection()),
  };
  const base = createServiceDeskSession(nativeClient);
  await base.start(identity);
  await base.load('recent', 'tickets');
  expect(base.state.status).toBe('ready');
  expect(base.resource('recent').status).toBe('ready');
  const client = {
    dashboard: vi.fn(dashboard),
    report: vi.fn(),
  };
  const operations = createOperationalSession(client, base);
  const value = { base, client, nativeClient, operations };
  sessions.push(value);
  return value;
}

describe('one authorized overview dashboard response', () => {
  it.each([undefined, false])(
    'preserves the original KPI contract when includeSupervision is %s',
    async includeSupervision => {
      const { base, client, operations } = await openSession();
      const result = await operations.read('kpis', 'dashboard', {
        includeSupervision,
      });

      expect(result.total).toBe(1);
      expect(result).not.toHaveProperty('supervision');
      expect(client.dashboard).toHaveBeenCalledTimes(1);
      expect(client.report).not.toHaveBeenCalled();
      expect(base.resource('recent').items).toHaveLength(1);
    }
  );

  it('decodes counts and supervision from exactly one dashboard request', async () => {
    const { base, client, operations } = await openSession();
    const result = await operations.read('overview', 'dashboard', {
      includeSupervision: true,
    });

    expect(client.dashboard).toHaveBeenCalledTimes(1);
    expect(client.dashboard).toHaveBeenCalledWith(
      '1',
      { page: 1, per_page: 20 },
      expect.any(AbortSignal)
    );
    expect(client.report).not.toHaveBeenCalled();
    expect(result.total).toBe(1);
    expect(result.supervision.status).toBe('ready');
    expect(result.supervision.data.capacity[0]).toMatchObject({
      unit_id: '10',
      active_tickets: 1,
      capacity: 3,
    });
    expect(JSON.stringify(result)).not.toContain('raw_secret');
    expect(JSON.stringify(result)).not.toContain('must never reach');
    expect(base.state.status).toBe('ready');
  });

  it('does not expose supervision when the fresh reports capability is denied', async () => {
    const context = supervisorContext();
    context.capabilities.reports.index = false;
    const { base, operations } = await openSession({ context });
    const result = await operations.read('overview', 'dashboard', {
      includeSupervision: true,
    });

    expect(result.supervision).toEqual({ status: 'denied', data: null });
    expect(result.total).toBe(1);
    expect(JSON.stringify(result)).not.toContain('Synthetic operator');
    expect(base.state.status).toBe('ready');
    expect(base.resource('recent').items).toHaveLength(1);
  });

  it('preserves an explicitly unavailable supervision result without inventing observations', async () => {
    const payload = dashboardPayload();
    payload.dashboard.supervision = null;
    const { base, operations } = await openSession({ payload });
    const result = await operations.read('overview', 'dashboard', {
      includeSupervision: true,
    });

    expect(result.supervision).toEqual({ status: 'ready', data: null });
    expect(result.total).toBe(1);
    expect(base.state.status).toBe('ready');
  });

  it.each([
    [
      'invalid timezone',
      value => {
        value.timezone = 'invalid';
      },
    ],
    [
      'foreign capacity unit',
      value => {
        value.capacity[0].unit_id = '99';
      },
    ],
    [
      'foreign agent unit',
      value => {
        value.by_agent[0].unit_id = '99';
      },
    ],
    [
      'invalid aggregate count',
      value => {
        value.tasks.open = -1;
      },
    ],
  ])(
    'isolates %s in optional supervision while retaining authorized counts and recent tickets',
    async (_scenario, change) => {
      const payload = dashboardPayload();
      change(payload.dashboard.supervision);
      const { base, operations } = await openSession({ payload });
      const recent = base.resource('recent');
      const result = await operations.read('overview', 'dashboard', {
        includeSupervision: true,
      });

      expect(result.supervision).toEqual({
        status: 'invalid_contract',
        data: null,
      });
      expect(result.total).toBe(1);
      expect(operations.resource('overview').status).toBe('ready');
      expect(base.state.status).toBe('ready');
      expect(base.state.context.account_id).toBe('1');
      expect(base.resource('recent')).toBe(recent);
      expect(base.resource('recent').items).toHaveLength(1);
    }
  );

  it('retains the existing supervision grant requirement without revoking independent authorized reads', async () => {
    const context = supervisorContext();
    context.effective_permissions = ['jrc_service_desk_dashboard_view'];
    const { base, operations } = await openSession({ context });
    const result = await operations.read('overview', 'dashboard', {
      includeSupervision: true,
    });

    expect(result.supervision).toEqual({
      status: 'invalid_contract',
      data: null,
    });
    expect(result.total).toBe(1);
    expect(JSON.stringify(result)).not.toContain('Synthetic operator');
    expect(base.state.status).toBe('ready');
    expect(base.resource('recent').status).toBe('ready');
  });

  it.each([
    [
      'foreign Account',
      value => {
        value.account_id = '2';
      },
    ],
    [
      'different filter echo',
      value => {
        value.dashboard.filters.q = 'another query';
      },
    ],
    [
      'inconsistent total',
      value => {
        value.dashboard.total = 2;
      },
    ],
    [
      'inconsistent status counts',
      value => {
        value.dashboard.by_status[0].count = 2;
      },
    ],
  ])(
    'still revokes all stored reads when the main dashboard has %s',
    async (_scenario, change) => {
      const payload = dashboardPayload();
      change(payload);
      const { base, operations } = await openSession({ payload });
      const result = await operations.read('overview', 'dashboard', {
        includeSupervision: true,
      });

      expect(result).toBeNull();
      expect(base.state.status).toBe('invalid_contract');
      expect(base.state.context).toBeNull();
      expect(base.state.resources).toEqual({});
      expect(operations.state.reads).toEqual({});
    }
  );

  it.each([
    [403, 'denied'],
    [401, 'unauthenticated'],
  ])('still clears data after HTTP %s', async (status, expected) => {
    const { base, operations } = await openSession({
      dashboard: async () => {
        throw httpError(status);
      },
    });
    const result = await operations.read('overview', 'dashboard', {
      includeSupervision: true,
    });

    expect(result).toBeNull();
    expect(base.state.status).toBe(expected);
    expect(base.state.context).toBeNull();
    expect(base.state.resources).toEqual({});
    expect(operations.state.reads).toEqual({});
  });

  it('aborts the old request and does not publish a late response after an Account change', async () => {
    const pending = deferred();
    const { base, client, nativeClient, operations } = await openSession({
      dashboard: () => pending.promise,
    });
    const oldRead = operations.read('overview', 'dashboard', {
      includeSupervision: true,
    });
    const oldSignal = client.dashboard.mock.calls[0][2];
    const nextContext = supervisorContext();
    nextContext.account_id = '2';
    nextContext.units.forEach(unit => {
      unit.account_id = '2';
      unit.operator_company.account_id = '2';
    });
    nativeClient.context.mockResolvedValue(nextContext);

    // Mirrors the provider's context-change boundary: clear before starting it.
    operations.clear();
    await base.start({ ...identity, accountId: '2' });
    pending.resolve(dashboardPayload());

    expect(await oldRead).toBeNull();
    expect(oldSignal.aborted).toBe(true);
    expect(base.state.status).toBe('ready');
    expect(base.state.context.account_id).toBe('2');
    expect(base.state.resources).toEqual({});
    expect(operations.state.reads).toEqual({});
  });

  it('does not replace a newer filtered dashboard with an aborted stale response', async () => {
    const pending = deferred();
    const { base, client, operations } = await openSession({
      dashboard: () => pending.promise,
    });
    const oldRead = operations.read('overview', 'dashboard', {
      includeSupervision: true,
    });
    const oldSignal = client.dashboard.mock.calls[0][2];
    const latest = dashboardPayload();
    latest.dashboard.filters = { unit_id: '10', q: 'current' };
    client.dashboard.mockResolvedValue(latest);
    const result = await operations.read('overview', 'dashboard', {
      query: { unit_id: '10', q: 'current' },
      includeSupervision: true,
    });
    pending.resolve(dashboardPayload());

    expect(await oldRead).toBeNull();
    expect(oldSignal.aborted).toBe(true);
    expect(operations.resource('overview').data).toBe(result);
    expect(result.filters).toEqual({ unit_id: '10', q: 'current' });
    expect(result.supervision.status).toBe('ready');
    expect(base.state.status).toBe('ready');
  });
});
