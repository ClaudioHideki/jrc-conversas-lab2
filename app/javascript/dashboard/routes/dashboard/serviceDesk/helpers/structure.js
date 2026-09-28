import { canonicalId } from './access.js';
export const STRUCTURE_RESOURCES = Object.freeze([
  'operator_companies',
  'units',
  'unit_memberships',
]);
const requireValue = value => {
  if (!value) throw new TypeError('Invalid structural contract');
};
export const structureId = value => {
  const id = canonicalId(value);
  requireValue(id);
  return id;
};
export function structureContext(payload, identity) {
  requireValue(payload?.contract_version === 1 && payload.available === true);
  requireValue(
    structureId(payload.account_id) === structureId(identity.accountId) &&
      structureId(payload.user_id) === structureId(identity.userId)
  );
  const capabilities = {};
  STRUCTURE_RESOURCES.forEach(resource => {
    requireValue(typeof payload.capabilities?.[resource] === 'boolean');
    capabilities[resource] = payload.capabilities[resource];
  });
  return {
    account_id: structureId(payload.account_id),
    user_id: structureId(payload.user_id),
    account_user_id: structureId(payload.account_user_id),
    available: true,
    capabilities,
  };
}
export function structureFields(resource, creating) {
  requireValue(STRUCTURE_RESOURCES.includes(resource));
  if (!creating)
    return resource === 'unit_memberships' ? ['active'] : ['name', 'active'];
  return resource === 'unit_memberships'
    ? ['unit_id', 'account_user_id', 'active']
    : [
        'code',
        'name',
        'active',
        ...(resource === 'units' ? ['operator_company_id'] : []),
      ];
}
export function structureAttributes(resource, attrs, creating) {
  const fields = structureFields(resource, creating);
  requireValue(attrs && typeof attrs === 'object' && !Array.isArray(attrs));
  requireValue(
    Object.keys(attrs).length > 0 &&
      Object.keys(attrs).every(key => fields.includes(key))
  );
  requireValue(!creating || fields.every(key => Object.hasOwn(attrs, key)));
  return Object.fromEntries(
    Object.entries(attrs).map(([key, value]) => {
      if (key.endsWith('_id')) value = structureId(value);
      else if (key === 'active') requireValue(typeof value === 'boolean');
      else
        requireValue(
          typeof value === 'string' &&
            value.trim().length > 0 &&
            value.length <= (key === 'code' ? 80 : 255)
        );
      return [key, value];
    })
  );
}
const envelope = (payload, ctx) => {
  requireValue(
    ctx?.available === true &&
      payload?.contract_version === 1 &&
      structureId(payload.account_id) === ctx.account_id
  );
};
export function structureRecord(payload, ctx, resource) {
  envelope(payload, ctx);
  requireValue(
    payload.resource === resource && STRUCTURE_RESOURCES.includes(resource)
  );
  const row = payload.record;
  requireValue(
    row &&
      structureId(row.account_id) === ctx.account_id &&
      /^[a-f0-9]{64}$/.test(row.revision)
  );
  return {
    ...structureAttributes(
      resource,
      Object.fromEntries(structureFields(resource, true).map(k => [k, row[k]])),
      true
    ),
    id: structureId(row.id),
    account_id: ctx.account_id,
    revision: row.revision,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}
export function structurePage(payload, ctx, resource, page) {
  envelope(payload, ctx);
  const meta = payload.meta;
  requireValue(
    Array.isArray(payload.items) &&
      Number.isSafeInteger(meta?.total) &&
      meta.total >= 0 &&
      meta.page === page &&
      meta.per_page === 25
  );
  requireValue(
    payload.items.length ===
      Math.min(25, Math.max(0, meta.total - (page - 1) * 25))
  );
  let items;
  if (resource === 'members')
    items = payload.items.map(row => {
      requireValue(typeof row.name === 'string');
      return {
        id: structureId(row.id),
        user_id: structureId(row.user_id),
        name: row.name,
      };
    });
  else
    items = payload.items.map(row =>
      structureRecord({ ...payload, record: row }, ctx, resource)
    );
  requireValue(new Set(items.map(row => row.id)).size === items.length);
  return { items, meta: { ...meta } };
}
export function membershipPage(payload, ctx, page, unitId) {
  const result = structurePage(payload, ctx, 'members', page);
  const read = (resource, record) =>
    structureRecord({ ...payload, resource, record }, ctx, resource);
  const unit = read('units', payload.unit);
  const operator = read('operator_companies', payload.operator_company);
  requireValue(
    unit.id === structureId(unitId) && unit.operator_company_id === operator.id
  );
  const items = result.items.map((member, index) => {
    const row = payload.items[index];
    requireValue(
      ['agent', 'administrator'].includes(row.role) &&
        Array.isArray(row.capabilities)
    );
    requireValue(row.capabilities.every(value => typeof value === 'string'));
    const membership =
      row.membership === null ? null : read('unit_memberships', row.membership);
    requireValue(
      !membership ||
        (membership.unit_id === unit.id &&
          membership.account_user_id === member.id)
    );
    requireValue(
      row.custom_role === null ||
        (structureId(row.custom_role.id) &&
          typeof row.custom_role.name === 'string')
    );
    return {
      ...member,
      role: row.role,
      custom_role: row.custom_role,
      capabilities: row.capabilities,
      membership,
    };
  });
  return { ...result, items, unit, operator };
}
export function confirmStructure(ack, receiptPayload, fresh, ctx, intent) {
  requireValue(ctx.capabilities[intent.resource] === true);
  const written = structureRecord(ack, ctx, intent.resource);
  const record = structureRecord(fresh, ctx, intent.resource);
  envelope(receiptPayload, ctx);
  const receipt = receiptPayload.receipt;
  requireValue(
    receipt &&
      receipt.namespace === 'jrc_service_desk_structure_v1' &&
      receipt.action === intent.action &&
      typeof receipt.fingerprint === 'string' &&
      /^[a-f0-9]{64}$/.test(receipt.fingerprint) &&
      Object.hasOwn(receipt, 'before') &&
      receipt.after &&
      typeof receipt.after === 'object' &&
      structureId(receipt.after.account_id) === ctx.account_id &&
      structureId(receipt.id) === structureId(ack.audit_id) &&
      structureId(receipt.account_id) === ctx.account_id &&
      structureId(receipt.author_user_id) === ctx.user_id &&
      structureId(receipt.author_account_user_id) === ctx.account_user_id &&
      receipt.resource === intent.resource &&
      structureId(receipt.record_id) === record.id &&
      written.id === record.id &&
      typeof receipt.occurred_at === 'string' &&
      !Number.isNaN(Date.parse(receipt.occurred_at)) &&
      receipt.reason === intent.reason.trim()
  );
  requireValue(
    intent.action === 'create'
      ? receipt.before === null
      : structureId(intent.recordId) === record.id && receipt.before !== null
  );
  Object.entries(intent.attributes).forEach(([field, value]) => {
    const auditValue = field.endsWith('_id')
      ? structureId(receipt.after?.[field])
      : receipt.after?.[field];
    requireValue(auditValue === value && record[field] === value);
  });
  return record;
}
export function createStructureAccess(api, state = {}) {
  let epoch = 0;
  let controller;
  const clear = status => {
    epoch += 1;
    controller?.abort();
    Object.assign(state, { visible: false, context: null, status });
  };
  const refresh = async identity => {
    if (
      identity.enabled !== true ||
      !canonicalId(identity.accountId) ||
      !canonicalId(identity.userId)
    ) {
      clear('disabled');
      return;
    }
    const sameIdentity =
      state.context?.account_id === structureId(identity.accountId) &&
      state.context?.user_id === structureId(identity.userId);
    if (!sameIdentity) clear('loading');
    else {
      epoch += 1;
      controller?.abort();
    }
    const turn = epoch;
    controller = new AbortController();
    try {
      const payload = await api.context(
        structureId(identity.accountId),
        controller.signal
      );
      if (turn !== epoch) return;
      const next = structureContext(payload, identity);
      // Preserve a draft only while an independent revalidation confirms the SAME authority.
      // Replaced identity/capabilities trigger the view watcher and discard protected state.
      if (JSON.stringify(next) !== JSON.stringify(state.context))
        state.context = next;
      state.visible = true;
      state.status = 'ready';
    } catch (error) {
      if (turn === epoch)
        clear(
          [401, 403].includes(error?.response?.status) ? 'denied' : 'error'
        );
    }
  };
  return { state, refresh, clear, dispose: () => clear('idle') };
}
