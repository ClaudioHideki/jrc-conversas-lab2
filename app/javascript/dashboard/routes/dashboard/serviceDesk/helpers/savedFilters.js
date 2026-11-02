import { canonicalId } from './access.js';
import { normalizeQuery, queryWithinContext } from './query.js';

// Personal views only. The API reauthorizes the selected filters on every read.
export function savedFilterKey(accountId, userId) {
  const account = canonicalId(accountId);
  const user = canonicalId(userId);
  if (!account || !user) throw new TypeError('Invalid filter owner');
  return `jrc:service-desk:filters:v1:${account}:${user}`;
}

export function savedFilterQuery(input) {
  const query = normalizeQuery(input);
  delete query.page;
  delete query.per_page;
  return query;
}

export function readSavedFilters(storage, accountId, userId, context) {
  const raw = storage.getItem(savedFilterKey(accountId, userId));
  if (!raw) return [];
  const rows = JSON.parse(raw);
  if (!Array.isArray(rows) || rows.length > 20)
    throw new TypeError('Invalid saved filters');
  return rows.flatMap(row => {
    if (
      !row ||
      typeof row.name !== 'string' ||
      !row.name.trim() ||
      row.name.length > 60 ||
      !row.query ||
      Array.isArray(row.query) ||
      typeof row.query !== 'object'
    )
      return [];
    try {
      const query = savedFilterQuery(row.query);
      return queryWithinContext(query, context)
        ? [{ name: row.name.trim(), query }]
        : [];
    } catch {
      return [];
    }
  });
}

export function writeSavedFilters(storage, accountId, userId, rows) {
  if (!Array.isArray(rows) || rows.length > 20)
    throw new TypeError('Too many saved filters');
  const normalized = rows.map(row => {
    const name = String(row.name || '').trim();
    if (!name || name.length > 60) throw new TypeError('Invalid filter name');
    return { name, query: savedFilterQuery(row.query) };
  });
  storage.setItem(
    savedFilterKey(accountId, userId),
    JSON.stringify(normalized)
  );
  return normalized;
}
