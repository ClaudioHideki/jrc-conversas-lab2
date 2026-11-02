import { savedFilterKey } from './savedFilters';
import { normalizeQuery } from './query';

const positions = new Map();
const key = (identity, screen, query) => {
  const filters = normalizeQuery(query);
  const normalized = Object.fromEntries(
    Object.keys(filters)
      .sort()
      .map(field => [field, filters[field]])
  );
  return `${savedFilterKey(...identity)}:${screen}:${JSON.stringify(normalized)}`;
};
export function rememberTicketListPosition(identity, screen, query, top) {
  if (!identity.every(Boolean) || !Number.isFinite(top) || top < 0) return;
  if (positions.size >= 20) positions.delete(positions.keys().next().value);
  positions.set(key(identity, screen, query), top);
}
export function consumeTicketListPosition(identity, screen, query) {
  if (!identity.every(Boolean)) return null;
  const id = key(identity, screen, query);
  const top = positions.get(id) ?? null;
  positions.delete(id);
  return top;
}
