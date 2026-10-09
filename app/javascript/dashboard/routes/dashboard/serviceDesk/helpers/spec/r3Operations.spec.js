import { describe, expect, it } from 'vitest';
import { decodeClockProjection } from '../clockProjection';
import { decodeResource, decodeResources } from '../resourceContract';
import { decodeIncident } from '../incidentContract';
import { decodeBoard } from '../v2Projection';
const context = { account_id: '1', units: [{ id: '2' }] };
const clock = {
  id: '4',
  kind: 'attendance',
  state: 'paused',
  budget_seconds: 3600,
  elapsed_seconds: 1800,
  remaining_seconds: 1800,
  consumed_percent: 50,
  breached: false,
  due_at: '2026-10-08T15:00:00Z',
  observed_at: '2026-10-08T14:00:00Z',
};
const asset = {
  id: '8',
  account_id: '1',
  unit_id: '2',
  resource_kind: 'asset',
  name: 'Router LAB',
  state: 'active',
  priority: 'normal',
  lock_version: 0,
  history: [],
  details: { serial: 'LOCAL' },
  ticket_ids: ['9'],
  permissions: { show: true, update: true, destroy: true },
};
const problem = {
  id: '3',
  account_id: '1',
  unit_id: '2',
  resource_kind: 'problem',
  title: 'Repeated fault',
  status: 'investigating',
  severity: 'high',
  lock_version: 1,
  ticket_ids: ['9'],
  cause: 'Local circuit',
  workaround: 'Alternate local circuit',
  permissions: { show: true, update: true },
};
describe('R3 current native scoped operations', () => {
  it('renders backend attendance consumption without manufacturing a running timer or mutation', () => {
    const decoded = decodeClockProjection(clock);
    expect(decoded).toMatchObject({
      kind: 'attendance',
      state: 'paused',
      remaining_seconds: 1800,
      consumed_percent: 50,
    });
    expect(clock.elapsed_seconds).toBe(1800);
    expect(() =>
      decodeClockProjection({ ...clock, consumed_percent: NaN })
    ).toThrow();
  });
  it('requires current unit grants, the exact resource kind and unique ticket links', () => {
    expect(decodeResource(asset, context, '2', 'asset').ticket_ids).toEqual([
      '9',
    ]);
    expect(() =>
      decodeResource(asset, { ...context, units: [] }, '2', 'asset')
    ).toThrow();
    expect(() => decodeResource(asset, context, '2', 'change')).toThrow();
    expect(() =>
      decodeResource(
        { ...asset, ticket_ids: ['9', '9'] },
        context,
        '2',
        'asset'
      )
    ).toThrow();
  });
  it('does not accept a response from another account or impossible paging metadata', () => {
    const payload = {
      contract_version: 1,
      account_id: '1',
      items: [asset],
      meta: { page: 2, per_page: 20, total: 21 },
    };
    expect(
      decodeResources(payload, context, '2', 'asset', 2).items
    ).toHaveLength(1);
    expect(() =>
      decodeResources({ ...payload, account_id: '6' }, context, '2', 'asset', 2)
    ).toThrow();
    expect(() =>
      decodeResources(
        { ...payload, meta: { ...payload.meta, total: 20 } },
        context,
        '2',
        'asset',
        2
      )
    ).toThrow();
  });
  it('keeps problem identity and native root-cause content separate from incidents', () => {
    expect(decodeIncident(problem, context, '2', 'problem')).toMatchObject({
      cause: 'Local circuit',
      workaround: 'Alternate local circuit',
    });
    expect(() => decodeIncident(problem, context, '2', 'incident')).toThrow();
    const payload = {
      contract_version: 1,
      account_id: '1',
      kind: 'problems',
      items: [problem],
      meta: { page: 1, per_page: 20, total: 1 },
    };
    expect(
      decodeBoard(payload, context, 'problems', {
        page: 1,
        per_page: 20,
        unit_id: '2',
      }).items[0].incident.resource_kind
    ).toBe('problem');
  });
});
