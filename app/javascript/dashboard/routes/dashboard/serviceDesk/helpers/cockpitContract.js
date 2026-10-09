import { canonicalId } from './access';
import { ContractError } from './contracts';
import { decodeClockProjection } from './clockProjection';
const assert = condition => {
  if (!condition) throw new ContractError();
};
const object = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const id = value => {
  const result = canonicalId(value);
  assert(result !== null);
  return result;
};
const text = value => {
  assert(typeof value === 'string');
  return value;
};
const audiences = [
  'internal',
  'technical_team',
  'customer',
  'public_without_notification',
];
export function decodeCockpit(payload, context, ticket) {
  assert(
    object(payload) &&
      payload.contract_version === 1 &&
      id(payload.account_id) === context.account_id
  );
  assert(
    object(payload.ticket) &&
      id(payload.ticket.id) === ticket.id &&
      id(payload.ticket.unit_id) === ticket.unit_id
  );
  assert(context.units.some(unit => unit.id === ticket.unit_id));
  const data = payload.cockpit;
  assert(object(data));
  const scoped = row => {
    assert(
      object(row) &&
        id(row.account_id) === context.account_id &&
        id(row.unit_id) === ticket.unit_id &&
        id(row.ticket_id) === ticket.id
    );
    assert(object(row.permissions) && row.permissions.show === true);
    return id(row.id);
  };
  const list = (values, decode) => {
    assert(Array.isArray(values));
    const rows = values.map(decode);
    assert(new Set(rows.map(row => row.id)).size === rows.length);
    return rows;
  };
  const notes = list(data.notes, row => {
    const recordId = scoped(row);
    assert(audiences.includes(row.visibility));
    return {
      id: recordId,
      body: text(row.body),
      visibility: row.visibility,
      created_at: row.created_at,
      author: row.author && { name: text(row.author.name) },
      notification_state: row.notification_state,
      deliveries: (row.deliveries || []).map(delivery => {
        assert(
          ['email', 'whatsapp'].includes(delivery.channel) &&
            [
              'blocked',
              'queued',
              'dispatching',
              'sent',
              'delivered',
              'read',
              'failed',
              'unknown',
            ].includes(delivery.state)
        );
        return { channel: delivery.channel, state: delivery.state };
      }),
      attachments: list(row.attachments, file => ({
        id: id(file.id),
        filename: text(file.filename),
        scan_state: text(file.scan_state),
      })),
    };
  });
  const tasks = list(data.tasks, row => {
    const recordId = scoped(row);
    assert(
      audiences.includes(row.visibility) &&
        ['open', 'in_progress', 'completed', 'cancelled'].includes(row.status)
    );
    assert(
      Number.isSafeInteger(row.lock_version) &&
        row.lock_version >= 0 &&
        Array.isArray(row.checklist)
    );
    const checklist = row.checklist.map(item => {
      assert(object(item) && typeof item.done === 'boolean');
      return { title: text(item.title), done: item.done };
    });
    return {
      id: recordId,
      title: text(row.title),
      description: row.description,
      visibility: row.visibility,
      status: row.status,
      due_at: row.due_at,
      priority: row.priority,
      assignee_account_user_id: row.assignee_account_user_id || null,
      parent_task_id: row.parent_task_id || null,
      completion_policy: object(row.completion_policy)
        ? row.completion_policy
        : {},
      pending_children: Number.isSafeInteger(row.pending_children)
        ? row.pending_children
        : 0,
      checklist,
      lock_version: row.lock_version,
      permissions: { update: row.permissions.update === true },
    };
  });
  const approvals = list(data.approvals, row => {
    const recordId = scoped(row);
    assert(
      ['pending', 'approved', 'rejected', 'returned'].includes(row.status)
    );
    assert(Number.isSafeInteger(row.lock_version) && row.lock_version >= 0);
    return {
      id: recordId,
      title: text(row.title),
      status: row.status,
      comment: row.comment,
      due_at: row.due_at,
      lock_version: row.lock_version,
      history: Array.isArray(row.history) ? row.history : [],
      approver_account_user_id: row.approver_account_user_id || null,
      approver_team_id: row.approver_team_id || null,
      approver_role: row.approver_role || null,
      approver_custom_role_id: row.approver_custom_role_id || null,
      permissions: {
        decide: row.permissions.decide === true,
        escalate: row.permissions.escalate === true,
      },
    };
  });
  const events = list(data.events, row => ({
    id: scoped(row),
    event_type: text(row.event_type),
    created_at: row.created_at,
    author: row.author && { name: text(row.author.name) },
  }));
  const conversations = list(data.conversations, row => ({
    id: id(row.id),
    display_id: id(row.display_id),
    channel: ['email', 'whatsapp'].includes(row.channel) ? row.channel : null,
    customer_recipient: row.customer_recipient === true,
  }));
  const incident =
    data.incident === null
      ? null
      : (() => {
          assert(
            object(data.incident) &&
              id(data.incident.unit_id) === ticket.unit_id
          );
          return {
            id: id(data.incident.id),
            title: text(data.incident.title),
            status: text(data.incident.status),
            severity: text(data.incident.severity),
          };
        })();
  const approvers = list(data.approvers, row => ({
    id: id(row.id),
    name: text(row.name),
  }));
  return {
    notes,
    tasks,
    approvals,
    events,
    conversations,
    incident,
    approvers,
    ola: Array.isArray(data.ola) ? data.ola.map(decodeClockProjection) : [],
  };
}
