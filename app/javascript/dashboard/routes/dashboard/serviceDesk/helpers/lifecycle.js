import { canonicalId } from './access.js';
import { ContractError, decodeTicket } from './contracts.js';
const check = ok => { if (!ok) throw new ContractError(); };
const object = val => val && typeof val === 'object' && !Array.isArray(val);
const id = val => { const result = canonicalId(val); check(result); return result; };
const integer = val => { check(Number.isSafeInteger(val) && val >= 0); return val; };
const string = val => { check(typeof val === 'string'); return val; };
const stamp = val => { check(typeof val === 'string' && Number.isFinite(Date.parse(val))); return val; };
const optionalStamp = val => val === null ? null : stamp(val);
const actions = ['pause', 'resume', 'resolve', 'close', 'cancel', 'reopen', 'work_status'];
const clockKinds = ['first_response', 'resolution'];
function scope(payload, context, ticket) {
  check(object(payload) && payload.contract_version === 1 && id(payload.account_id) === context.account_id);
  check(id(payload.ticket_id) === ticket.id && id(payload.unit_id) === ticket.unit_id);
  check(context.available === true && context.units.some(unit => unit.id === ticket.unit_id));
}
function requirements(value) {
  check(object(value) && object(value.fields));
  ['note', 'solution', 'evidence', 'classification'].forEach(key => check(typeof value[key] === 'boolean'));
  const fields = Object.fromEntries(Object.entries(value.fields).map(([key, spec]) => {
    check(/^[A-Za-z0-9_.-]{1,80}$/.test(key) && !['__proto__', 'constructor', 'prototype'].includes(key));
    check(object(spec) && ['text', 'integer', 'boolean'].includes(spec.type) && typeof spec.required === 'boolean');
    return [key, { label: string(spec.label), type: spec.type, required: spec.required, ...(Object.hasOwn(spec, 'equals') ? { equals: spec.equals } : {}) }];
  }));
  return { note: value.note, solution: value.solution, evidence: value.evidence, classification: value.classification, fields };
}
export function decodeLifecycle(payload, context, ticket) {
  scope(payload, context, ticket);
  let policy = null;
  if (payload.policy !== null) {
    check(object(payload.policy) && /^[a-f0-9]{64}$/.test(payload.policy.digest) && typeof payload.policy.pinned === 'boolean');
    policy = { id: id(payload.policy.id), version: integer(payload.policy.version), digest: payload.policy.digest, pinned: payload.policy.pinned };
  }
  check(Array.isArray(payload.options) && (policy || payload.options.length === 0));
  const options = payload.options.map(row => {
    check(object(row) && actions.includes(row.action) && Array.isArray(row.reasons));
    return { key: string(row.key), action: row.action, to_status_id: id(row.to_status_id), to_status_name: string(row.to_status_name),
      requirements: requirements(row.requirements), reasons: row.reasons.map(reason => {
        check(Array.isArray(reason.clocks) && reason.clocks.every(clock => clockKinds.includes(clock)));
        return { code: string(reason.code), name: string(reason.name), clocks: [...reason.clocks] };
      }) };
  });
  check(new Set(options.map(r => r.key)).size === options.length);
  const pause = payload.pause === null ? null : { id: id(payload.pause.id), reason_code: string(payload.pause.reason_code), started_at: stamp(payload.pause.started_at), clocks: payload.pause.clocks.map(string) };
  let cycle = null;
  if (payload.cycle !== null) {
    const c = payload.cycle;
    check(object(c) && Array.isArray(c.clocks));
    cycle = { id: id(c.id), number: integer(c.number), snapshot_version: integer(c.snapshot_version), timezone: string(c.timezone), clocks: c.clocks.map(row => {
      check(clockKinds.includes(row.kind) && ['running', 'paused', 'completed', 'stopped'].includes(row.state));
      check(Number.isFinite(row.elapsed_seconds) && row.elapsed_seconds >= 0 && (row.met === null || typeof row.met === 'boolean'));
      return { id: id(row.id), kind: row.kind, state: row.state, due_at: stamp(row.due_at), achieved_at: optionalStamp(row.achieved_at),
        budget_seconds: integer(row.budget_seconds), elapsed_seconds: row.elapsed_seconds, anchor_at: stamp(row.anchor_at), met: row.met };
    }) };
  }
  check(Array.isArray(payload.history) && object(payload.meta) && payload.meta.per_page === 20);
  const meta = { page: integer(payload.meta.page), per_page: 20, total: integer(payload.meta.total) };
  check(meta.page > 0 && payload.history.length <= 20 && payload.history.length <= Math.max(0, meta.total - (meta.page - 1) * 20));
  return { account_id: context.account_id, unit_id: ticket.unit_id, ticket_id: ticket.id,
    lock_version: integer(payload.lock_version), service_id: payload.service_id === null ? null : id(payload.service_id),
    policy, reopening: payload.reopening == null ? null : decodeReopening(payload.reopening), unavailable_reason: payload.unavailable_reason === null ? null : string(payload.unavailable_reason), options, pause, cycle,
    history: payload.history.map(row => decodeLifecycleTransition(row, context, ticket)), meta };
}
function decodeReopening(row) {
  check(object(row) && ['deny', 'require_new_ticket'].includes(row.expired_behavior) && ['continue_cycle', 'new_cycle'].includes(row.sla_cycle));
  return { window_seconds: integer(row.window_seconds), expired_behavior: row.expired_behavior, sla_cycle: row.sla_cycle, expires_at: optionalStamp(row.expires_at) };
}
export function decodeLifecycleTransition(row, context, ticket) {
  check(object(row) && id(row.account_id) === context.account_id && id(row.unit_id) === ticket.unit_id && id(row.ticket_id) === ticket.id);
  check(actions.includes(row.action) && object(row.payload) && object(row.author));
  const p = row.payload;
  // Display only user-entered text and provenance; no raw financial/calendar payload is forwarded.
  return { id: id(row.id), policy_version_id: id(row.policy_version_id), policy_version: integer(row.policy_version),
    action: row.action, rule_key: string(row.rule_key), request_key: string(row.request_key),
    from_status_id: id(row.from_status_id), to_status_id: id(row.to_status_id), occurred_at: stamp(row.occurred_at),
    author: { account_user_id: id(row.author.account_user_id), name: string(row.author.name) },
    note: p.note == null ? '' : string(p.note), solution: p.solution == null ? '' : string(p.solution), reason_code: p.reason_code == null ? '' : string(p.reason_code),
    evidence_note_ids: Array.isArray(p.evidence_note_ids) ? p.evidence_note_ids.map(id) : [],
    fields: object(p.fields) ? Object.fromEntries(Object.entries(p.fields).filter(([key, value]) => !['__proto__', 'constructor', 'prototype'].includes(key) && ['string', 'number', 'boolean'].includes(typeof value))) : {},
    cycle_id: p.sla?.cycle_id == null ? null : id(p.sla.cycle_id), cycle_rule: p.sla?.reopening?.sla_cycle || null };
}
export function decodeConfigurationList(payload, context, unit, kind) {
  check(object(payload) && payload.contract_version === 1 && id(payload.account_id) === context.account_id && id(payload.unit_id) === id(unit));
  check(context.units.some(u => u.id === id(unit)) && Array.isArray(payload.items) && object(payload.meta));
  const items = payload.items.map(row => decodeConfiguration(row, context, unit, kind));
  const meta = { page: integer(payload.meta.page), total: integer(payload.meta.total), per_page: integer(payload.meta.per_page) };
  check(meta.page > 0 && meta.per_page === 20 && items.length <= 20 && items.length <= Math.max(0, meta.total - (meta.page - 1) * 20));
  return { items, meta };
}
export function decodeConfiguration(row, context, unit, kind) {
  check(object(row) && id(row.account_id) === context.account_id && id(row.unit_id) === id(unit));
  const base = { id: id(row.id), unit_id: id(unit), name: string(row.name) };
  if (kind === 'services') { check(typeof row.active === 'boolean'); return { ...base, code: string(row.code), active: row.active }; }
  check(kind === 'policies' && typeof row.enabled === 'boolean' && object(row.definition));
  return { ...base, service_id: row.service_id === null ? null : id(row.service_id), enabled: row.enabled,
    version_id: id(row.version_id), version: integer(row.version), digest: (check(/^[a-f0-9]{64}$/.test(row.digest)), row.digest), definition: JSON.parse(JSON.stringify(row.definition)) };
}
const canonicalValue = value => Array.isArray(value) ? value.map(canonicalValue) : object(value) ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonicalValue(value[key])])) : value;
export const sameLifecycleDefinition = (a, b) => JSON.stringify(canonicalValue(a)) === JSON.stringify(canonicalValue(b));
export function verifyLifecycleIntent(transition, command) {
  check(transition.note === (command.note || '') && transition.solution === (command.solution || '') && transition.reason_code === (command.reason_code || ''));
  check(sameLifecycleDefinition(transition.fields, command.fields || {}));
  check(sameLifecycleDefinition(transition.evidence_note_ids, (command.evidence_note_ids || []).map(id)));
  return true;
}
export const createLifecycleState = () => ({ status: 'idle', data: null, writeStatus: 'idle' });
export function createLifecycleSession(client, contextProvider, state = createLifecycleState()) {
  let epoch = 0, controller = null, intent = null;
  const clear = () => { epoch += 1; controller?.abort(); controller = null; intent = null; state.status = 'idle'; state.data = null; state.writeStatus = 'idle'; };
  const begin = () => { epoch += 1; controller?.abort(); controller = new AbortController(); return { turn: epoch, signal: controller.signal, context: contextProvider() }; };
  const valid = ctx => ctx && ctx.available === true && Array.isArray(ctx.units);
  const matches = run => run.turn === epoch && contextProvider() === run.context;
  const load = async (ticket, page = 1) => {
    const run = begin(); state.status = 'loading'; state.data = null;
    try {
      check(valid(run.context));
      const payload = await client.read(run.context.account_id, ticket.id, page, run.signal);
      if (!matches(run)) return null;
      state.data = decodeLifecycle(payload, run.context, ticket); state.status = 'ready'; return state.data;
    } catch (error) {
      if (!matches(run)) return null;
      state.status = [401, 403].includes(error.response?.status) ? 'denied' : 'error'; state.data = null; return null;
    }
  };
  const apply = async (ticket, command, requestKey) => {
    if (state.writeStatus === 'saving') return null;
    const signature = JSON.stringify({ ticket: ticket.id, command, requestKey });
    const permitted = state.data?.options.some(rule => rule.key === command.rule_key) || intent === signature;
    const run = begin(); let acknowledged = false;
    state.writeStatus = 'saving';
    try {
      check(valid(run.context) && permitted && state.data.ticket_id === ticket.id && state.data.account_id === run.context.account_id && state.data.unit_id === ticket.unit_id && run.context.units.some(unit => unit.id === ticket.unit_id));
      check(state.data.policy?.id === id(command.expected_policy_version_id));
      if (intent && signature !== intent) throw new TypeError('Confirm previous outcome before a new intent');
      intent = signature;
      const ack = await client.apply(run.context.account_id, ticket.id, command, requestKey, run.signal);
      if (!matches(run)) return null;
      check(ack.contract_version === 1 && ack.applied === true && ack.operation === 'lifecycle' && id(ack.account_id) === run.context.account_id && id(ack.ticket_id) === ticket.id);
      acknowledged = true;
      const detail = await client.transition(run.context.account_id, ticket.id, id(ack.result_id), run.signal);
      if (!matches(run)) return null;
      check(detail.contract_version === 1 && id(detail.account_id) === run.context.account_id);
      const transition = decodeLifecycleTransition(detail.transition, run.context, ticket);
      check(transition.id === id(ack.result_id) && transition.request_key === requestKey && transition.rule_key === command.rule_key && transition.policy_version_id === id(command.expected_policy_version_id));
      verifyLifecycleIntent(transition, command);
      const persisted = await client.ticket(run.context.account_id, ticket.id, run.signal);
      if (!matches(run)) return null;
      const confirmed = decodeTicket(persisted, run.context, ticket.id);
      check(confirmed.status.id === transition.to_status_id);
      const reread = await client.read(run.context.account_id, ticket.id, 1, run.signal);
      if (!matches(run)) return null;
      const data = decodeLifecycle(reread, run.context, confirmed);
      check(data.policy?.id === transition.policy_version_id);
      state.data = data; state.status = 'ready'; state.writeStatus = 'confirmed'; intent = null;
      return confirmed;
    } catch (error) {
      if (!matches(run)) return null;
      const code = error.response?.status;
      state.writeStatus = acknowledged ? 'readback_pending' : code === 409 ? 'conflict' : code === 422 ? (error.response?.data?.code === 'lifecycle_dependency' ? 'dependency' : 'invalid_input') : code === 403 || code === 401 ? 'denied' : 'error';
      if (!acknowledged && [409, 422].includes(code)) intent = null;
      if ([401, 403, 404].includes(code)) { state.data = null; state.status = 'denied'; }
      return null;
    }
  };
  return { state, clear, load, apply };
}
