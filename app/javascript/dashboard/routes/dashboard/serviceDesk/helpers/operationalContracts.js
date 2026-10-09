import { canonicalId } from './access.js';
import { sameSetting } from './v2Configuration';
import { ContractError } from './contracts.js';
import { normalizeQuery } from './query.js';
const assert = condition => {
  if (!condition) throw new ContractError();
};
const obj = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const id = value => {
  const parsed = canonicalId(value);
  assert(parsed !== null);
  return parsed;
};
const count = value => {
  assert(Number.isSafeInteger(value) && value >= 0);
  return value;
};
const stamp = value => {
  assert(typeof value === 'string' && Number.isFinite(Date.parse(value)));
  return value;
};
const maybeStamp = value => (value === null ? null : stamp(value));
const text = value => {
  assert(typeof value === 'string');
  return value;
};
const named = value => {
  if (value === null) return null;
  assert(obj(value));
  return { id: id(value.id), name: text(value.name) };
};
export function decodeAcknowledgement(
  payload,
  context,
  operation,
  ticketId = null
) {
  assert(
    obj(payload) &&
      payload.contract_version === 1 &&
      id(payload.account_id) === context.account_id
  );
  assert(payload.applied === true && payload.operation === operation);
  const result = id(payload.ticket_id);
  assert(ticketId === null || result === id(ticketId));
  return result;
}
export function decodeDashboard(payload, context, request = {}) {
  assert(
    obj(payload) &&
      payload.contract_version === 1 &&
      id(payload.account_id) === context.account_id
  );
  const d = payload.dashboard;
  assert(
    obj(d) && obj(d.phases) && Array.isArray(d.by_status) && obj(d.filters)
  );
  const phases = Object.fromEntries(
    ['open', 'waiting', 'resolved', 'closed', 'cancelled'].map(key => [
      key,
      count(d.phases[key]),
    ])
  );
  const total = count(d.total);
  assert(Object.values(phases).reduce((sum, n) => sum + n, 0) === total);
  const active = count(d.active);
  assert(active === phases.open + phases.waiting);
  const byStatus = d.by_status.map(row => {
    assert(obj(row) && Object.hasOwn(phases, row.phase));
    return {
      id: id(row.id),
      name: text(row.name),
      phase: row.phase,
      count: count(row.count),
    };
  });
  assert(new Set(byStatus.map(row => row.id)).size === byStatus.length);
  Object.keys(phases).forEach(phase =>
    assert(
      byStatus
        .filter(row => row.phase === phase)
        .reduce((sum, row) => sum + row.count, 0) === phases[phase]
    )
  );
  const normalized = normalizeQuery(request);
  const filters = Object.fromEntries(
    Object.entries(normalized).filter(
      ([k, value]) => !['page', 'per_page', 'sort'].includes(k) && value !== ''
    )
  );
  assert(Object.keys(filters).length === Object.keys(d.filters).length);
  Object.entries(filters).forEach(([k, value]) =>
    assert(String(d.filters[k]) === String(value))
  );
  return {
    total,
    active,
    phases,
    by_status: byStatus,
    generated_at: stamp(d.generated_at),
    filters,
  };
}
const EVENT_KEYS = {
  operational_rule_applied: [
    'kind',
    'rule_version_id',
    'rule_key',
    'rule_digest',
    'snapshot_id',
  ],
  clock_threshold_reached: [
    'clock_id',
    'clock_kind',
    'percent',
    'policy_digest',
    'elapsed_seconds',
    'budget_seconds',
    'due_at',
    'breached',
    'target_queue_id',
  ],
  clock_violated: [
    'clock_id',
    'clock_kind',
    'policy_digest',
    'elapsed_seconds',
    'budget_seconds',
    'due_at',
    'observed_at',
  ],
  approval_escalated: ['approval_id', 'history_index'],
  resource_linked: ['resource_id', 'resource_kind'],
  resource_updated: ['resource_id', 'resource_kind', 'history_index'],
  resource_archived: ['resource_id', 'resource_kind', 'history_index'],
  notification_resend_requested: [
    'original_delivery_id',
    'delivery_id',
    'reason',
  ],
  ticket_created: [
    'status_id',
    'priority_id',
    'queue_id',
    'assignee_membership_id',
  ],
  ticket_updated: [
    'title',
    'description',
    'priority_id',
    'category_id',
    'status_id',
    'company_id',
  ],
  ticket_assigned: ['assignee_membership_id', 'queue_id', 'team_id'],
  ticket_transferred: ['assignee_membership_id', 'queue_id', 'team_id'],
  note_added: ['note_id', 'notification_state'],
  conversation_linked: ['conversation_id', 'link_id'],
  interaction_republished: [
    'note_id',
    'previous_note_id',
    'notification_state',
  ],
  task_created: ['task_id', 'status'],
  task_updated: ['task_id', 'changes'],
  approval_requested: ['approval_id'],
  approval_decided: ['approval_id', 'changes'],
  incident_linked: ['incident_id', 'primary_ticket_id'],
  incident_updated: ['incident_id', 'changes'],
  ticket_claimed: ['assignee_membership_id'],
  ticket_auto_routed: ['assignee_membership_id', 'queue_id', 'mode'],
  notification_delivery_updated: ['note_id', 'delivery_id', 'channel', 'state'],
  first_response_recorded: [
    'message_id',
    'conversation_id',
    'clock_id',
    'cycle_id',
    'achieved_at',
    'snapshot_id',
  ],
  sla_snapshot_recorded: ['snapshot_id', 'version'],
  creation_context_recorded: [],
  lifecycle_policy_bound: ['policy_version_id', 'version', 'digest'],
  lifecycle_transitioned: [
    'transition_id',
    'action',
    'from_status_id',
    'to_status_id',
    'policy_version_id',
    'policy_version',
    'cycle_id',
  ],
};
export function decodeRelated(payload, context, ticket, kind, request) {
  assert(
    obj(payload) &&
      payload.contract_version === 1 &&
      id(payload.account_id) === context.account_id
  );
  assert(
    id(payload.ticket_id) === ticket.id &&
      payload.kind === kind &&
      Array.isArray(payload.items)
  );
  const meta = payload.meta;
  assert(obj(meta) && count(meta.total) >= payload.items.length);
  assert(
    meta.page === request.page &&
      meta.per_page === request.per_page &&
      meta.per_page >= 1 &&
      meta.per_page <= 100
  );
  assert(payload.items.length <= meta.per_page);
  const remaining = Math.max(0, meta.total - (meta.page - 1) * meta.per_page);
  assert(
    payload.items.length <= remaining &&
      !(remaining > 0 && payload.items.length === 0)
  );
  const items = payload.items.map(row => {
    assert(
      obj(row) &&
        id(row.account_id) === context.account_id &&
        id(row.unit_id) === ticket.unit_id
    );
    assert(context.units.some(unit => unit.id === ticket.unit_id));
    assert(obj(row.permissions) && row.permissions.show === true);
    const base = {
      id: id(row.id),
      unit_id: ticket.unit_id,
      account_id: context.account_id,
    };
    if (kind === 'status_options') return { ...base, name: text(row.name) };
    assert(id(row.ticket_id) === ticket.id);
    if (kind === 'sla') {
      assert(['first_response', 'resolution'].includes(row.kind));
      assert(
        typeof row.calculation_pending === 'boolean' &&
          (row.met === null || typeof row.met === 'boolean')
      );
      const due = maybeStamp(row.due_at),
        achieved = maybeStamp(row.achieved_at);
      assert(row.calculation_pending === (due === null));
      assert((due !== null && achieved !== null) || row.met === null);
      return {
        ...base,
        kind: row.kind,
        due_at: due,
        achieved_at: achieved,
        met: row.met,
        calculation_pending: row.calculation_pending,
        snapshot_version: count(row.snapshot_version),
      };
    }
    base.created_at = stamp(row.created_at);
    if (kind === 'notes') {
      assert(
        [
          'internal',
          'technical_team',
          'customer',
          'public_without_notification',
        ].includes(row.visibility)
      );
      let attachments;
      if (Object.hasOwn(row, 'attachments')) {
        assert(Array.isArray(row.attachments) && row.attachments.length <= 5);
        attachments = row.attachments.map(file => ({
          id: id(file.id),
          filename: text(file.filename),
          byte_size:
            file.byte_size === undefined ? null : count(file.byte_size),
          scan_state: text(file.scan_state),
        }));
        assert(
          new Set(attachments.map(file => file.id)).size === attachments.length
        );
      }
      return {
        ...base,
        body: text(row.body),
        visibility: row.visibility,
        author: named(row.author),
        ...(attachments ? { attachments } : {}),
      };
    }
    if (kind === 'events') {
      assert(Object.hasOwn(EVENT_KEYS, row.event_type) && obj(row.data));
      return {
        ...base,
        event_type: row.event_type,
        author: named(row.author),
        data: Object.fromEntries(
          Object.entries(row.data).filter(([key]) =>
            EVENT_KEYS[row.event_type].includes(key)
          )
        ),
      };
    }
    assert(kind === 'conversations');
    return {
      ...base,
      conversation_id: id(row.conversation_id),
      conversation_display_id: id(row.conversation_display_id),
    };
  });
  assert(new Set(items.map(row => row.id)).size === items.length);
  return {
    items,
    meta: { total: meta.total, page: meta.page, per_page: meta.per_page },
  };
}
export function verifyOpeningAttachments(note, payload) {
  assert(
    note.visibility === 'internal' &&
      note.body ===
        (payload.ticket.description?.trim()
          ? payload.ticket.description
          : payload.ticket.title)
  );
  assert(
    Array.isArray(note.attachments) &&
      note.attachments.length === payload.files.length
  );
  const identity = file =>
    JSON.stringify([file.filename ?? file.name, file.byte_size ?? file.size]);
  assert(
    sameSetting(
      note.attachments.map(identity).sort(),
      payload.files.map(identity).sort()
    )
  );
  return note;
}

export function decodeRelatedItem(payload, context, ticket, kind, recordId) {
  assert(
    obj(payload) && obj(payload.item) && id(payload.item.id) === id(recordId)
  );
  return decodeRelated(
    {
      ...payload,
      items: [payload.item],
      meta: { page: 1, per_page: 20, total: 1 },
    },
    context,
    ticket,
    kind,
    { page: 1, per_page: 20 }
  ).items[0];
}
export function verifyWrittenFields(action, payload, ticket) {
  const equalId = (actual, expected) =>
    (actual?.id || null) === (expected === null ? null : id(expected));
  if (action === 'create' || action === 'update') {
    const input = payload.ticket;
    ['impact_code', 'urgency_code'].forEach(key => {
      if (Object.hasOwn(input, key)) assert(ticket[key] === input[key]);
    });
    ['title', 'description'].forEach(key => {
      if (Object.hasOwn(input, key)) assert(ticket[key] === (input[key] || ''));
    });
    const associations = {
      company_id: 'company',
      requester_id: 'requester',
      status_id: 'status',
      priority_id: 'priority',
      category_id: 'category',
      ticket_type_id: 'ticket_type',
      subcategory_id: 'subcategory',
      contract_id: 'contract',
      queue_id: 'queue',
      team_id: 'team',
      assignee_account_user_id: 'assignee',
    };
    Object.entries(associations).forEach(([key, name]) => {
      if (Object.hasOwn(input, key)) assert(equalId(ticket[name], input[key]));
    });
    if (Object.hasOwn(input, 'service_fields'))
      assert(sameSetting(ticket.service_fields, input.service_fields));
    if (action === 'create') {
      assert(ticket.unit_id === id(payload.unit_id));
      if (payload.service_id)
        assert(equalId(ticket.service, payload.service_id));
    }
  } else if (['assign', 'transfer'].includes(action)) {
    Object.entries({
      assignee_account_user_id: 'assignee',
      team_id: 'team',
      queue_id: 'queue',
    }).forEach(([key, name]) => {
      if (Object.hasOwn(payload.assignment, key))
        assert(equalId(ticket[name], payload.assignment[key]));
    });
  } else if (action === 'work_status')
    assert(equalId(ticket.status, payload.status_id));
  return ticket;
}
