import { canonicalId } from './access';
import { ContractError, decodeCollection } from './contracts';
import { decodeDashboard } from './operationalContracts';
import { decodeIncident } from './incidentContract';
const check = value => {
  if (!value) throw new ContractError();
};
const object = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const id = value => {
  const result = canonicalId(value);
  check(result);
  return result;
};
const count = value => {
  check(Number.isSafeInteger(value) && value >= 0);
  return value;
};
const number = value => {
  check(Number.isFinite(value) && value >= 0);
  return value;
};
const text = value => {
  check(typeof value === 'string');
  return value;
};
const unit = (value, context) => {
  const result = id(value);
  check(context.units.some(row => row.id === result));
  return result;
};
const scoped = (row, context) => {
  check(
    object(row) &&
      id(row.account_id) === context.account_id &&
      row.permissions?.show === true
  );
  return { id: id(row.id), unit_id: unit(row.unit_id, context) };
};
export function decodeBoard(payload, context, kind, query) {
  check(
    object(payload) &&
      payload.contract_version === 1 &&
      id(payload.account_id) === context.account_id &&
      payload.kind === kind
  );
  check(
    ['tasks', 'approvals', 'incidents', 'problems'].includes(kind) &&
      Array.isArray(payload.items)
  );
  const meta = payload.meta;
  check(
    object(meta) &&
      meta.page === query.page &&
      meta.per_page === query.per_page &&
      count(meta.total) >= payload.items.length
  );
  check(
    payload.items.length <= meta.per_page &&
      payload.items.length <=
        Math.max(0, meta.total - (meta.page - 1) * meta.per_page)
  );
  const items = payload.items.map(row => {
    const base = scoped(row, context);
    check(!query.unit_id || query.unit_id === base.unit_id);
    const states = {
      tasks: ['open', 'in_progress', 'completed', 'cancelled'],
      approvals: ['pending', 'approved', 'rejected', 'returned'],
      incidents: ['open', 'investigating', 'monitoring', 'resolved'],
      problems: ['open', 'investigating', 'monitoring', 'resolved'],
    }[kind];
    const relatedTicket = ['incidents', 'problems'].includes(kind)
      ? row.primary_ticket_id || row.ticket_ids[0]
      : row.ticket_id;
    check(states.includes(row.status));
    return {
      ...base,
      title: text(row.title),
      status: row.status,
      ticket_id: relatedTicket ? id(relatedTicket) : null,
      due_at: row.due_at || null,
      visibility: typeof row.visibility === 'string' ? row.visibility : null,
      ...(['incidents', 'problems'].includes(kind) &&
      (kind === 'problems' || Object.hasOwn(row, 'resource_kind'))
        ? {
            incident: decodeIncident(
              row,
              context,
              base.unit_id,
              kind === 'problems' ? 'problem' : 'incident'
            ),
          }
        : {}),
    };
  });
  check(new Set(items.map(row => row.id)).size === items.length);
  return {
    items,
    meta: { page: meta.page, per_page: meta.per_page, total: meta.total },
  };
}
export function decodeSupervision(value, context) {
  if (value === null || value === undefined) return null;
  check(
    object(value) &&
      context.effective_permissions?.includes(
        'jrc_service_desk_tickets_view_all'
      ) &&
      value.timezone === 'UTC'
  );
  const rows = (name, decode) => {
    check(Array.isArray(value[name]));
    return value[name].map(decode);
  };
  const sla =
    value.sla === null
      ? null
      : (() => {
          check(
            object(value.sla) &&
              context.effective_permissions?.includes(
                'jrc_service_desk_sla_view'
              )
          );
          return {
            ...Object.fromEntries(
              [
                'observed_cycles',
                'running_breached',
                'completed_met',
                'completed_breached',
              ].map(key => [key, count(value.sla[key])])
            ),
            ...Object.fromEntries(
              [
                'first_response_average_seconds',
                ...(Object.hasOwn(value.sla, 'attendance_average_seconds')
                  ? ['attendance_average_seconds']
                  : []),
                'resolution_average_seconds',
              ].map(key => [
                key,
                value.sla[key] === null ? null : number(value.sla[key]),
              ])
            ),
          };
        })();
  return {
    sla,
    by_agent: rows('by_agent', row => ({
      id: row.id === null ? null : id(row.id),
      name: row.name === null ? null : text(row.name),
      count: count(row.count),
    })),
    capacity: rows('capacity', row => {
      check(['available', 'unavailable', 'paused'].includes(row.availability));
      return {
        id: id(row.id),
        unit_id: unit(row.unit_id, context),
        name: text(row.name),
        availability: row.availability,
        capacity: row.capacity === null ? null : count(row.capacity),
        active_tickets: count(row.active_tickets),
      };
    }),
    evolution: rows('evolution', row => {
      check(/^\d{4}-\d{2}-\d{2}$/.test(row.date));
      return { date: row.date, count: count(row.count) };
    }),
    top_categories: rows('top_categories', row => ({
      id: row.id === null ? null : id(row.id),
      name: row.name === null ? null : text(row.name),
      count: count(row.count),
    })),
    tasks:
      value.tasks === null
        ? null
        : {
            open: count(value.tasks.open),
            overdue: count(value.tasks.overdue),
          },
    approvals:
      value.approvals === null
        ? null
        : {
            pending: count(value.approvals.pending),
            overdue: count(value.approvals.overdue),
          },
  };
}
export function decodeReport(payload, context, query) {
  check(payload.projection === 'authorized_service_desk_report_v2');
  return {
    ...decodeCollection(payload, context, 'tickets', query),
    dashboard: decodeDashboard(payload, context, query),
    supervision: decodeSupervision(payload.dashboard.supervision, context),
  };
}
