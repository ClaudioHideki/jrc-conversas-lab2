import { canonicalId } from './access';
import { ContractError } from './contracts';

export const communicationKinds = [
  'note',
  'event',
  'task',
  'approval',
  'message',
  'call',
  'delivery',
];
export const interactionAudiences = [
  'internal',
  'technical_team',
  'customer',
  'public_without_notification',
];
const fields = [
  'key',
  'kind',
  'id',
  'account_id',
  'unit_id',
  'ticket_id',
  'created_at',
  'source',
  'visibility',
  'author',
  'body',
  'title',
  'event_type',
  'data',
  'status',
  'private',
  'conversation_id',
  'message_type',
  'direction',
  'duration_seconds',
  'started_at',
  'ended_at',
  'due_at',
  'checklist',
  'comment',
  'decided_at',
  'state',
  'channel',
  'recipient',
  'reason',
  'provider_id',
  'attempt_number',
  'ticket_note_id',
  'ticket_event_id',
  'original_delivery_id',
  'template_version',
  'policy_version',
  'template',
  'content',
  'provider',
  'execution_account_user_id',
  'dispatch_started_at',
  'sent_at',
  'delivered_at',
  'read_at',
  'permissions',
  'attachments',
  'recordings',
];
const assert = value => {
  if (!value) throw new ContractError();
};
const object = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const text = value => {
  assert(typeof value === 'string');
  return value;
};
const identifier = value => {
  assert(canonicalId(value) === value);
  return value;
};
const scoped = (row, context, ticket) => {
  assert(
    object(row) &&
      row.account_id === context.account_id &&
      row.ticket_id === ticket.id &&
      row.unit_id === ticket.unit_id
  );
};

export function decodeTimeline(payload, context, ticket) {
  assert(
    object(payload) &&
      payload.contract_version === 1 &&
      payload.account_id === context.account_id
  );
  scoped(payload, context, ticket);
  const timeline = payload.timeline;
  assert(object(timeline) && Array.isArray(timeline.items));
  assert(
    timeline.next_cursor === null || typeof timeline.next_cursor === 'string'
  );
  const items = timeline.items.map(row => {
    scoped(row, context, ticket);
    assert(
      communicationKinds.includes(row.kind) &&
        row.key === `${row.kind}:${identifier(row.id)}`
    );
    assert(
      object(row.source) &&
        row.source.type === row.kind &&
        row.source.id === row.id &&
        Number.isFinite(Date.parse(row.created_at))
    );
    if (row.visibility !== undefined)
      assert(interactionAudiences.includes(row.visibility));
    if (row.body !== null && row.body !== undefined) text(row.body);
    if (row.kind === 'delivery')
      assert(
        [
          'blocked',
          'queued',
          'dispatching',
          'sent',
          'delivered',
          'read',
          'failed',
          'unknown',
        ].includes(row.state)
      );
    return Object.fromEntries(
      Object.entries(row).filter(([key]) => fields.includes(key))
    );
  });
  assert(new Set(items.map(row => row.key)).size === items.length);
  return { items, cursor: timeline.next_cursor };
}

export function decodeComposer(payload, context, ticket) {
  assert(
    object(payload) &&
      payload.contract_version === 1 &&
      payload.account_id === context.account_id
  );
  const row = payload.composer;
  scoped(row, context, ticket);
  assert(
    Array.isArray(row.audiences) &&
      row.audiences.every(value => interactionAudiences.includes(value))
  );
  assert(new Set(row.audiences).size === row.audiences.length);
  assert(
    row.recipient === null ||
      (object(row.recipient) &&
        identifier(row.recipient.id) &&
        typeof row.recipient.name === 'string')
  );
  assert(Array.isArray(row.channels) && row.channels.length === 2);
  row.channels.forEach(channel => {
    assert(
      ['email', 'whatsapp'].includes(channel.channel) &&
        typeof channel.available === 'boolean' &&
        Array.isArray(channel.destinations)
    );
    channel.destinations.forEach(destination => {
      identifier(destination.conversation_id);
      text(destination.recipient);
      assert(
        typeof destination.available === 'boolean' &&
          (destination.reason === null ||
            typeof destination.reason === 'string')
      );
    });
  });
  assert(new Set(row.channels.map(channel => channel.channel)).size === 2);
  return row;
}
