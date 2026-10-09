import { canonicalId } from './access.js';
export class QueryError extends Error {
}
const idFields = ['unit_id', 'operator_company_id', 'status_id', 'priority_id', 'category_id', 'queue_id', 'assignee_id'];
const fields = new Set([
  'q',
  'page',
  'per_page',
  'mine',
  'source',
  'sort',
  'phase',
  'assignment',
  ...idFields,
]);
const scalar = value => typeof value === 'string' || typeof value === 'number';
export function normalizeQuery(query = {}) {
  const result = { page: 1, per_page: 20 };
  Object.entries(query).forEach(([key, value]) => {
    if (!fields.has(key))
      throw new QueryError('Unknown filter');
    if (value === '' || value === undefined || value === null)
      return;
    if (!scalar(value))
      throw new QueryError('Invalid filter');
    if (idFields.includes(key)) {
      const parsed = canonicalId(value);
      if (!parsed)
        throw new QueryError('Invalid identifier');
      result[key] = parsed;
    }
    else if (['page', 'per_page'].includes(key)) {
      if (!/^[1-9]\d*$/.test(String(value)))
        throw new QueryError('Invalid pagination');
      const number = Number(value);
      if (!Number.isSafeInteger(number) || number > (key === 'per_page' ? 100 : 1000000))
        throw new QueryError('Invalid pagination');
      result[key] = number;
    }
    else if (key === 'mine') {
      if (String(value) !== 'true')
        throw new QueryError('Invalid personal filter');
      result.mine = 'true';
    }
    else if (key === 'phase') {
      if (
        ![
          'active',
          'open',
          'waiting',
          'resolved',
          'closed',
          'cancelled',
        ].includes(value)
      )
        throw new QueryError('Invalid phase');
      result.phase = value;
    }
    else if (key === 'assignment') {
      if (value !== 'unassigned') throw new QueryError('Invalid assignment');
      result.assignment = value;
    } else if (key === 'sort') {
      if (!['updated_at_desc', 'created_at_desc', 'created_at_asc'].includes(value))
        throw new QueryError('Invalid order');
      result.sort = value;
    } else {
      if (String(value).length > (key === 'q' ? 200 : 40))
        throw new QueryError('Filter too long');
      result[key] = String(value).trim();
    }
  });
  if (result.mine && result.assignment)
    throw new QueryError('Incompatible personal filter');
  return result;
}
export function queryWithinContext(query, context) {
  const units = context?.units || [];
  if (query.unit_id && !units.some(unit => unit.id === query.unit_id))
    return false;
  if (query.operator_company_id && !units.some(unit => unit.operator_company.id === query.operator_company_id))
    return false;
  if (query.unit_id && query.operator_company_id && !units.some(unit => unit.id === query.unit_id && unit.operator_company.id === query.operator_company_id))
    return false;
  return true;
}
export function routeQuery(query) {
  return Object.fromEntries(Object.entries(normalizeQuery(query)).filter(([, value]) => value !== ''));
}
