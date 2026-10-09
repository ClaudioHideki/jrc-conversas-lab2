import { canonicalId } from './access.js';
import { ContractError } from './contracts.js';
import { sameLifecycleDefinition } from './lifecycle.js';

export const snapshotSourceFields = [
  'source_system',
  'source_reference',
  'source_version',
  'policy_key',
  'policy_version',
  'calendar_key',
  'calendar_version',
];
export const snapshotConditionFields = [
  'contract_conditions',
  'policy_conditions',
  'calendar_conditions',
];
export const snapshotFields = [
  ...snapshotSourceFields,
  'calendar_scope',
  'timezone',
  'captured_at',
  ...snapshotConditionFields,
];
const object = value =>
  value && typeof value === 'object' && !Array.isArray(value);
const check = value => {
  if (!value) throw new ContractError();
};
const identifier = value => {
  const result = canonicalId(value);
  check(result);
  return result;
};
const timestamp = value => {
  check(
    typeof value === 'string' &&
      /(Z|[+-]\d{2}:\d{2})$/.test(value) &&
      Number.isFinite(Date.parse(value))
  );
  return value;
};
const jsonValue = value => {
  if (Array.isArray(value)) return value.map(jsonValue);
  if (object(value))
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => {
        check(
          !/password|secret|credential|access_token|refresh_token|api_key|authorization/i.test(
            key
          )
        );
        check(!['__proto__', 'constructor', 'prototype'].includes(key));
        return [key, jsonValue(item)];
      })
    );
  check(
    value === null ||
      ['string', 'boolean'].includes(typeof value) ||
      (typeof value === 'number' && Number.isFinite(value))
  );
  return value;
};
const jsonObject = value => {
  check(object(value));
  return jsonValue(value);
};
export function snapshotInput(value) {
  check(
    object(value) &&
      Object.keys(value).length === snapshotFields.length &&
      Object.keys(value).every(key => snapshotFields.includes(key))
  );
  const result = Object.fromEntries(
    snapshotSourceFields.map(key => {
      check(
        typeof value[key] === 'string' &&
          value[key].trim().length > 0 &&
          value[key].trim().length <= 255
      );
      return [key, value[key].trim()];
    })
  );
  check(['account', 'operator_company', 'unit'].includes(value.calendar_scope));
  check(
    typeof value.timezone === 'string' &&
      value.timezone.length > 0 &&
      value.timezone.length <= 100
  );
  try {
    new Intl.DateTimeFormat('en', { timeZone: value.timezone }).format();
  } catch {
    throw new ContractError();
  }
  return {
    ...result,
    calendar_scope: value.calendar_scope,
    timezone: value.timezone,
    captured_at: timestamp(value.captured_at),
    ...Object.fromEntries(
      snapshotConditionFields.map(key => [key, jsonObject(value[key])])
    ),
  };
}
export function decodeSnapshot(payload, context, ticket, receipt = false) {
  check(
    object(payload) &&
      payload.contract_version === 1 &&
      identifier(payload.account_id) === context.account_id
  );
  check(
    identifier(payload.ticket_id) === ticket.id &&
      identifier(payload.unit_id) === ticket.unit_id
  );
  check(
    context.available === true &&
      context.units.some(unit => unit.id === ticket.unit_id)
  );
  check(!receipt || payload.applied === true);
  const row = payload.snapshot;
  check(
    object(row) &&
      Number.isSafeInteger(row.version) &&
      row.version > 0 &&
      object(row.permissions) &&
      typeof row.permissions.show === 'boolean'
  );
  const result = {
    id: identifier(row.id),
    version: row.version,
    permissions: { show: row.permissions.show },
  };
  if (!row.permissions.show) {
    check(receipt);
    return result;
  }
  check(
    typeof row.payload_digest === 'string' &&
      /^[a-f0-9]{64}$/.test(row.payload_digest)
  );
  check(
    object(row.source) &&
      object(row.policy) &&
      object(row.calendar) &&
      object(row.conditions)
  );
  return {
    ...result,
    payload_digest: row.payload_digest,
    applied_at: timestamp(row.applied_at),
    input: snapshotInput({
      source_system: row.source.system,
      source_reference: row.source.reference,
      source_version: row.source.version,
      policy_key: row.policy.key,
      policy_version: row.policy.version,
      calendar_key: row.calendar.key,
      calendar_version: row.calendar.version,
      calendar_scope: row.calendar.scope,
      timezone: row.timezone,
      captured_at: row.captured_at,
      contract_conditions: row.conditions.contract,
      policy_conditions: row.conditions.policy,
      calendar_conditions: row.conditions.calendar,
    }),
  };
}
const sameInput = (actual, desired) =>
  Date.parse(actual.captured_at) === Date.parse(desired.captured_at) &&
  sameLifecycleDefinition(
    { ...actual, captured_at: null },
    { ...desired, captured_at: null }
  );
export const createSnapshotState = () => ({ status: 'idle', snapshot: null });
export function createSnapshotSession(api, getContext, getTicket, state) {
  let epoch = 0;
  let controller;
  let pending;
  const permitted = () => {
    const context = getContext();
    const ticket = getTicket();
    return (
      context?.available === true &&
      ticket?.permissions?.record_sla_snapshot === true &&
      canonicalId(ticket.account_id) === context.account_id &&
      context.units.some(unit => unit.id === ticket.unit_id)
    );
  };
  const clear = () => {
    epoch += 1;
    controller?.abort();
    pending = null;
    state.status = 'idle';
    state.snapshot = null;
  };
  const same = run =>
    run.epoch === epoch &&
    run.context === getContext() &&
    permitted() &&
    getTicket().id === run.ticket.id &&
    getTicket().unit_id === run.ticket.unit_id;
  const execute = async input => {
    if (!permitted()) {
      clear();
      return null;
    }
    if (state.status === 'saving') return null;
    epoch += 1;
    const run = { epoch, context: getContext(), ticket: getTicket() };
    controller?.abort();
    controller = new AbortController();
    state.status = 'saving';
    state.snapshot = null;
    let attempted = false;
    try {
      const desired = pending?.input || snapshotInput(input);
      pending ||= { input: desired, receipt: null };
      attempted = true;
      if (!pending.receipt) {
        const payload = await api.recordSnapshot(
          run.context.account_id,
          run.ticket.id,
          desired,
          controller.signal
        );
        if (!same(run)) return null;
        pending.receipt = decodeSnapshot(
          payload,
          run.context,
          run.ticket,
          true
        );
      }
      const ack = pending.receipt;
      if (!ack.permissions.show) {
        state.snapshot = ack;
        state.status = 'recorded_restricted';
        pending = null;
        return ack;
      }
      const payload = await api.snapshot(
        run.context.account_id,
        run.ticket.id,
        ack.id,
        controller.signal
      );
      if (!same(run)) return null;
      const confirmed = decodeSnapshot(payload, run.context, run.ticket);
      check(
        confirmed.id === ack.id &&
          confirmed.version === ack.version &&
          confirmed.payload_digest === ack.payload_digest &&
          confirmed.applied_at === ack.applied_at &&
          sameInput(confirmed.input, desired)
      );
      state.snapshot = confirmed;
      state.status = 'confirmed';
      pending = null;
      return confirmed;
    } catch (error) {
      if (!same(run)) return null;
      const status = error.response?.status;
      state.status = attempted ? 'readback_pending' : 'invalid_input';
      if ([401, 403, 404].includes(status)) state.status = 'denied';
      if (status === 422) state.status = 'invalid_input';
      if (status === 409) state.status = 'conflict';
      if (['denied', 'invalid_input', 'conflict'].includes(state.status))
        pending = null;
      return null;
    }
  };
  return Object.freeze({
    clear,
    apply: execute,
    recover: () => (pending ? execute(pending.input) : Promise.resolve(null)),
  });
}
