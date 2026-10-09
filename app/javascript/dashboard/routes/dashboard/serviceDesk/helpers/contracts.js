import { canonicalId } from './access.js';
import { decodeClockProjection } from './clockProjection';
import { catalogueFields, catalogueAnswers } from './catalogueFields';
export class ContractError extends Error {
  constructor(code = 'invalid_contract') {
    super(code);
    this.code = code;
  }
}
const object = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const requireValue = test => {
  if (!test) throw new ContractError();
};
const text = value => (typeof value === 'string' ? value : '');
const id = value => {
  const result = canonicalId(value);
  requireValue(result !== null);
  return result;
};
const permissions = value =>
  object(value)
    ? Object.fromEntries(
        Object.entries(value).filter(([, flag]) => typeof flag === 'boolean')
      )
    : {};
const named = value =>
  object(value) ? { id: id(value.id), name: text(value.name) } : null;
const stamp = value => {
  if (value === null || value === undefined) return null;
  requireValue(typeof value === 'string' && Number.isFinite(Date.parse(value)));
  return value;
};
// A proposed versioned CP4 contract. Unknown/raw fields (including financial
// snapshots, blob URLs and credentials) are never forwarded into the view model.
export function decodeContext(payload, identity) {
  requireValue(object(payload) && payload.contract_version === 1);
  requireValue(
    id(payload.account_id) === identity.accountId &&
      id(payload.user_id) === identity.userId
  );
  requireValue(typeof payload.available === 'boolean');
  requireValue(Array.isArray(payload.units) && object(payload.capabilities));
  const units = payload.units.map(unit => {
    requireValue(
      object(unit) &&
        id(unit.account_id) === identity.accountId &&
        unit.active === true
    );
    requireValue(
      object(unit.operator_company) &&
        id(unit.operator_company.account_id) === identity.accountId
    );
    return {
      id: id(unit.id),
      name: text(unit.name),
      operator_company: named(unit.operator_company),
      permissions: permissions(unit.permissions),
      ...(unit.initial_status
        ? { initial_status: named(unit.initial_status) }
        : {}),
    };
  });
  requireValue(new Set(units.map(unit => unit.id)).size === units.length);
  return {
    account_id: identity.accountId,
    user_id: identity.userId,
    available: payload.available,
    units,
    effective_permissions: Array.isArray(payload.effective_permissions)
      ? payload.effective_permissions.filter(
          value =>
            typeof value === 'string' && value.startsWith('jrc_service_desk_')
        )
      : [],
    capabilities: Object.fromEntries(
      Object.entries(payload.capabilities).map(([key, value]) => [
        key,
        permissions(value),
      ])
    ),
  };
}
const inScope = (row, context, resource) => {
  requireValue(object(row) && id(row.account_id) === context.account_id);
  const units = context.units;
  if (resource === 'operator_companies') {
    requireValue(units.some(unit => unit.operator_company.id === id(row.id)));
  } else if (resource === 'units') {
    const match = units.find(unit => unit.id === id(row.id));
    requireValue(
      match && match.operator_company.id === id(row.operator_company_id)
    );
  } else {
    requireValue(units.some(unit => unit.id === id(row.unit_id)));
  }
};
export function decodeRecord(row, context, resource) {
  inScope(row, context, resource);
  requireValue(object(row.permissions) && row.permissions.show === true);
  const record = {
    id: id(row.id),
    account_id: context.account_id,
    resource,
    unit_id: row.unit_id === undefined ? null : id(row.unit_id),
    name: text(row.name),
    code: text(row.code),
    description: text(row.description),
    permissions: permissions(row.permissions),
    active: typeof row.active === 'boolean' ? row.active : null,
    created_at: stamp(row.created_at),
    updated_at: stamp(row.updated_at),
  };
  if (resource === 'tickets') {
    return {
      ...record,
      title: text(row.title),
      number: text(row.number),
      ...(Object.hasOwn(row, 'impact_code')
        ? {
            impact_code: row.impact_code == null ? null : text(row.impact_code),
            urgency_code:
              row.urgency_code == null ? null : text(row.urgency_code),
          }
        : {}),
      service: named(row.service),
      status: named(row.status),
      priority: named(row.priority),
      category: named(row.category),
      ticket_type: named(row.ticket_type),
      subcategory: named(row.subcategory),
      ...(Object.hasOwn(row, 'contract')
        ? { contract: named(row.contract) }
        : {}),
      ...(Object.hasOwn(row, 'catalogue_form_fields')
        ? {
            catalogue_form_fields: catalogueFields(row.catalogue_form_fields),
            service_fields: catalogueAnswers(
              catalogueFields(row.catalogue_form_fields),
              row.service_fields
            ),
          }
        : {}),
      ...(Object.hasOwn(row, 'company') ? { company: named(row.company) } : {}),
      requester: named(row.requester),
      assignee: named(row.assignee),
      team: named(row.team),
      queue: named(row.queue),
      source: text(row.source),
      lock_version: Number.isInteger(row.lock_version)
        ? row.lock_version
        : null,
      // No client clock, synthetic countdown or 'met' inference.
      sla: object(row.sla)
        ? {
            first_response_due_at: stamp(row.sla.first_response_due_at),
            resolution_due_at: stamp(row.sla.resolution_due_at),
            attendance_due_at: stamp(row.sla.attendance_due_at),
            clocks: Array.isArray(row.sla.clocks)
              ? row.sla.clocks.map(decodeClockProjection)
              : [],
            state: text(row.sla.state),
          }
        : null,
    };
  }
  return {
    ...record,
    operator_company_id: row.operator_company_id
      ? id(row.operator_company_id)
      : null,
    team: named(row.team),
    account_user_id: row.account_user_id ? id(row.account_user_id) : null,
    phase: ['open', 'waiting', 'resolved', 'closed', 'cancelled'].includes(
      row.phase
    )
      ? row.phase
      : null,
    initial: typeof row.initial === 'boolean' ? row.initial : null,
    position:
      Number.isSafeInteger(row.position) && row.position >= 0
        ? row.position
        : null,
    ...(['categories', 'ticket_types'].includes(resource)
      ? {
          form_fields: catalogueFields(row.form_fields || []),
          ...(resource === 'categories'
            ? { parent_id: row.parent_id == null ? null : id(row.parent_id) }
            : {}),
        }
      : {}),
    ...(resource === 'assignees' && row.membership_id
      ? { membership_id: id(row.membership_id) }
      : {}),
    ...(resource === 'contracts'
      ? {
          contact_id: row.contact_id == null ? null : id(row.contact_id),
          company_id: row.company_id == null ? null : id(row.company_id),
        }
      : {}),
  };
}
export function decodeCollection(payload, context, resource, request) {
  requireValue(object(payload) && payload.contract_version === 1);
  requireValue(
    id(payload.account_id) === context.account_id &&
      Array.isArray(payload.items)
  );
  const meta = payload.meta;
  requireValue(object(meta) && Number.isInteger(meta.total) && meta.total >= 0);
  requireValue(Number.isInteger(meta.page) && meta.page === request.page);
  requireValue(
    Number.isInteger(meta.per_page) && meta.per_page === request.per_page
  );
  requireValue(meta.per_page >= 1 && meta.per_page <= 100 && meta.page >= 1);
  requireValue(
    payload.items.length <= meta.per_page && payload.items.length <= meta.total
  );
  const remaining = Math.max(0, meta.total - (meta.page - 1) * meta.per_page);
  requireValue(payload.items.length <= remaining);
  requireValue(meta.total === 0 || payload.items.length > 0 || remaining === 0);
  const items = payload.items.map(row => decodeRecord(row, context, resource));
  requireValue(new Set(items.map(row => row.id)).size === items.length);
  if (request.unit_id) {
    const selected = context.units.find(unit => unit.id === request.unit_id);
    requireValue(!!selected);
    requireValue(
      items.every(row =>
        resource === 'operator_companies'
          ? row.id === selected.operator_company.id
          : (resource === 'units' ? row.id : row.unit_id) === request.unit_id
      )
    );
  }
  if (request.operator_company_id) {
    const allowed = context.units
      .filter(unit => unit.operator_company.id === request.operator_company_id)
      .map(unit => unit.id);
    requireValue(
      items.every(row =>
        resource === 'operator_companies'
          ? row.id === request.operator_company_id
          : allowed.includes(resource === 'units' ? row.id : row.unit_id)
      )
    );
  }
  return {
    items,
    meta: { total: meta.total, page: meta.page, per_page: meta.per_page },
  };
}
export function decodeTicket(payload, context, ticketId) {
  requireValue(
    object(payload) &&
      payload.contract_version === 1 &&
      id(payload.account_id) === context.account_id
  );
  const ticket = decodeRecord(payload.ticket, context, 'tickets');
  requireValue(ticket.id === ticketId);
  // Related protected collections are fetched/authorized independently in CP4.
  return ticket;
}
