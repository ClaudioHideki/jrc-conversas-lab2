import { describe, expect, it } from 'vitest';
import {
  ticketListContext,
  ticketListReturn,
  ticketNavigationContext,
} from '../helpers/ticketNavigation';

describe('ticket list return context', () => {
  it('round-trips real filters, pagination and my queue', () => {
    const context = ticketListContext('mine', {
      q: 'PABX',
      page: '3',
      unit_id: '10',
      sort: 'updated_at_desc',
    });
    const restored = ticketListReturn(context);
    expect(restored.screen).toBe('mine');
    expect(restored.query).toMatchObject({
      q: 'PABX',
      page: 3,
      unit_id: '10',
      mine: 'true',
    });
    expect(ticketListReturn(ticketNavigationContext(context))).toEqual(
      restored
    );
  });
  it.each([
    '{}',
    '[]',
    'null',
    '{',
    '{"account_id":"2"}',
    '{"redirect":"https://example.com"}',
    '{"page":-1}',
  ])('rejects unsafe or malformed context %s', listQuery => {
    expect(
      ticketListReturn({
        list_screen: 'https://example.com',
        list_query: listQuery,
      })
    ).toEqual({
      screen: 'tickets',
      query: listQuery === '{}' ? { page: 1, per_page: 20 } : {},
    });
  });
  it('preserves unassigned scope without silently changing it to mine', () => {
    expect(
      ticketListReturn(
        ticketListContext('mine', { assignment: 'unassigned', page: 2 })
      ).query
    ).toMatchObject({ assignment: 'unassigned', page: 2 });
  });
});
