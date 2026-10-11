import { routeQuery } from './query';
import { ticketListQuery } from './screenExperience';

// Only list filters travel between routes; never accept a redirect URL or Account.
export function ticketListContext(screen, query) {
  return {
    list_screen: screen === 'mine' ? 'mine' : 'tickets',
    list_query: JSON.stringify(routeQuery(ticketListQuery(screen, query))),
  };
}

export function ticketListReturn(query = {}) {
  const screen = query.list_screen === 'mine' ? 'mine' : 'tickets';
  try {
    if (typeof query.list_query !== 'string' || query.list_query.length > 4000)
      return { screen, query: {} };
    const filters = JSON.parse(query.list_query);
    if (!filters || Array.isArray(filters) || typeof filters !== 'object')
      return { screen, query: {} };
    return { screen, query: routeQuery(ticketListQuery(screen, filters)) };
  } catch {
    return { screen, query: {} };
  }
}

export function ticketNavigationContext(query) {
  const restored = ticketListReturn(query);
  return ticketListContext(restored.screen, restored.query);
}
