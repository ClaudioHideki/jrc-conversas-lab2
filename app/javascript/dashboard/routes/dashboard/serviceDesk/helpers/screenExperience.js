// Presentation only: route metadata and labels never grant access.
import { normalizeQuery } from './query.js';
export const SCREEN_CATALOG = Object.freeze(
  [
    ['01', 'overview'],
    ['02', 'tickets'],
    ['03', 'mine'],
    ['04', 'new'],
    ['05', 'detail'],
    ['06', 'queues'],
    ['07', 'assignees'],
    ['08', 'sla'],
    ['09', 'catalog'],
    ['10', 'tasks'],
    ['11', 'approvals'],
    ['12', 'incidents'],
    ['13', 'problems'],
    ['14', 'changes'],
    ['15', 'assets'],
    ['16', 'contracts'],
    ['17', 'automations'],
    ['18', 'surveys'],
    ['19', 'reports'],
    ['20', 'settings'],
    ['21', 'portal'],
    ['22', 'history'],
  ].map(([id, key]) => Object.freeze({ id, key }))
);
export function ticketListQuery(screen, input = {}) {
  const query = { ...input };
  if (screen === 'mine') {
    if (query.assignment === 'unassigned') delete query.mine;
    else query.mine = 'true';
  }
  return query;
}
export function metricQuery(query, metric) {
  if (
    ![
      'total',
      'active',
      'open',
      'waiting',
      'resolved',
      'closed',
      'cancelled',
    ].includes(metric)
  )
    throw new TypeError('Unknown metric');
  const result = { ...normalizeQuery(query), page: 1 };
  delete result.status_id;
  delete result.phase;
  if (metric !== 'total') result.phase = metric;
  return result;
}
export function displayedScope(context, unitId) {
  const unit = context?.units?.find(row => row.id === unitId);
  return unit
    ? { name: unit.name, operator: unit.operator_company.name }
    : null;
}
export function dueState(row, observedAt) {
  if (
    !row?.due_at ||
    [
      'completed',
      'cancelled',
      'approved',
      'rejected',
      'returned',
      'resolved',
    ].includes(row.status)
  )
    return 'none';
  const due = Date.parse(row.due_at);
  const now = Date.parse(observedAt);
  if (!Number.isFinite(due) || !Number.isFinite(now)) return 'none';
  return due < now ? 'overdue' : 'scheduled';
}
export function namedReportValue(dimension, value, items, context, unitId) {
  if (value === null) return null;
  if (dimension === 'by_origin') return value;
  if (dimension === 'by_unit')
    return context.units.find(row => row.id === value)?.name || null;
  const field = {
    by_service: 'service',
    by_category: 'category',
    by_priority: 'priority',
    by_customer: 'company',
  }[dimension];
  if (!field) return null;
  return (
    items.find(
      row =>
        row.account_id === context.account_id &&
        row.unit_id === unitId &&
        row[field]?.id === value
    )?.[field]?.name || null
  );
}
