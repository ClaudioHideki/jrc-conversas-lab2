import { describe, expect, it, vi } from 'vitest';
import { normalizeQuery, QueryError } from '../helpers/query';
import {
  savedFilterKey,
  readSavedFilters,
  writeSavedFilters,
} from '../helpers/savedFilters';
import {
  rememberTicketListPosition,
  consumeTicketListPosition,
} from '../helpers/ticketListPosition';
import { createServiceDeskClient } from 'dashboard/api/serviceDeskClient';
const context = { units: [{ id: '10', operator_company: { id: '3' } }] };

describe('Service Desk list filters and navigation', () => {
  it('accepts inclusive ISO date filters and canonical team IDs', () => {
    expect(
      normalizeQuery({
        created_from: '2026-10-01',
        created_to: '2026-10-23',
        team_id: '9223372036854775807',
      })
    ).toMatchObject({
      created_from: '2026-10-01',
      created_to: '2026-10-23',
      team_id: '9223372036854775807',
    });
  });
  it.each([
    { created_from: '2026-02-31' },
    { created_from: '23/10/2026' },
    { created_from: '2026-10-24', created_to: '2026-10-23' },
    { team_id: '01' },
  ])('rejects malformed or inverted filters %j', query => {
    expect(() => normalizeQuery(query)).toThrow();
  });
  it('sends team filters to the authorized assignee lookup without allowing them for unrelated catalogs', async () => {
    const get = vi.fn().mockResolvedValue({ data: { items: [] } });
    const api = createServiceDeskClient({ get });
    await api.list('1', 'assignees', { unit_id: '10', team_id: '4' });
    expect(get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_service_desk/assignees',
      expect.objectContaining({
        params: expect.objectContaining({ unit_id: '10', team_id: '4' }),
      })
    );
    expect(() =>
      api.list('1', 'categories', { unit_id: '10', team_id: '4' })
    ).toThrow(QueryError);
    expect(get).toHaveBeenCalledTimes(1);
  });
  it('stores filters per user and Account without pinning an old results page', () => {
    const data = new Map();
    const storage = {
      getItem: key => data.get(key),
      setItem: (key, value) => data.set(key, value),
    };
    writeSavedFilters(storage, '1', '2', [
      { name: 'PABX', query: { q: 'PABX', unit_id: '10', page: 7 } },
    ]);
    expect(readSavedFilters(storage, '1', '2', context)).toEqual([
      { name: 'PABX', query: { q: 'PABX', unit_id: '10' } },
    ]);
    expect(readSavedFilters(storage, '2', '2', context)).toEqual([]);
    expect(readSavedFilters(storage, '1', '3', context)).toEqual([]);
    expect(readSavedFilters(storage, '1', '2', { units: [] })).toEqual([]);
  });
  it('does not replay injected or malformed query fields from stored filters', () => {
    const storage = {
      getItem: () =>
        JSON.stringify([
          { name: 'Invalid', query: { account_id: '9' } },
          { name: 'Valid', query: { q: 'Teste' } },
        ]),
    };
    expect(readSavedFilters(storage, '1', '2', context)).toEqual([
      { name: 'Valid', query: { q: 'Teste' } },
    ]);
    expect(() => savedFilterKey('../2', '2')).toThrow();
  });
  it('restores scroll only for the exact user, screen and normalized filter set', () => {
    rememberTicketListPosition(
      ['1', '2'],
      'mine',
      { unit_id: '10', page: '3' },
      560
    );
    expect(
      consumeTicketListPosition(['1', '3'], 'mine', { unit_id: '10', page: 3 })
    ).toBeNull();
    expect(
      consumeTicketListPosition(['1', '2'], 'tickets', {
        unit_id: '10',
        page: 3,
      })
    ).toBeNull();
    expect(
      consumeTicketListPosition(['1', '2'], 'mine', { page: 3, unit_id: '10' })
    ).toBe(560);
    expect(
      consumeTicketListPosition(['1', '2'], 'mine', { page: 3, unit_id: '10' })
    ).toBeNull();
  });
});
