import { catalogueFields } from '../../dashboard/routes/dashboard/serviceDesk/helpers/catalogueFields';
const check = value => {
  if (!value) throw new TypeError('Invalid customer portal projection');
};
const id = value => {
  check(/^[1-9]\d{0,18}$/.test(String(value)));
  return String(value);
};
const text = value => {
  check(typeof value === 'string');
  return value;
};
const list = (value, decode) => {
  check(Array.isArray(value));
  return value.map(decode);
};
const finite = (value, minimum = 0) => {
  check(
    typeof value === 'number' && Number.isFinite(value) && value >= minimum
  );
  return value;
};
const timestamp = value => {
  check(typeof value === 'string' && Number.isFinite(Date.parse(value)));
  return value;
};
const optionalTime = value => (value == null ? null : timestamp(value));
const timezone = value => {
  const zone = text(value);
  new Intl.DateTimeFormat('en', { timeZone: zone }).format();
  return zone;
};
const nativePath = (value, prefix) => {
  check(
    typeof value === 'string' &&
      value.startsWith(prefix) &&
      !value.includes('\\')
  );
  const decoded = decodeURIComponent(value);
  check(!decoded.split('/').includes('..') && !decoded.includes('\\'));
  const url = new URL(value, 'https://customer-portal.invalid');
  check(
    url.origin === 'https://customer-portal.invalid' &&
      url.pathname.startsWith(prefix) &&
      !url.search &&
      !url.hash
  );
  return value;
};
const file = row => ({
  id: id(row.id),
  filename: text(row.filename),
  scan_state: text(row.scan_state),
});
export function portalServices(payload) {
  return list(payload.services, row => {
    check(/^[a-f0-9]{64}$/.test(row.revision));
    check(
      row.contract_required == null ||
        typeof row.contract_required === 'boolean'
    );
    return {
      id: id(row.id),
      name: text(row.name),
      description: row.description == null ? '' : text(row.description),
      revision: row.revision,
      form_fields: catalogueFields(row.form_fields),
      contract_required: row.contract_required === true,
      contracts: list(row.contracts ?? [], contract => ({
        id: id(contract.id),
        name: text(contract.name),
      })),
    };
  });
}
export function portalKnowledge(payload) {
  return list(payload.articles, row => ({
    id: id(row.id),
    title: text(row.title),
    description: row.description == null ? '' : text(row.description),
    path: nativePath(row.path, '/hc/'),
  }));
}
export function portalTicket(row) {
  check(
    row &&
      ['open', 'waiting', 'resolved', 'closed', 'cancelled'].includes(
        row.status?.phase
      )
  );
  return {
    id: id(row.id),
    title: text(row.title),
    description: row.description == null ? '' : text(row.description),
    status: text(row.status.name),
    service_id: row.service_id == null ? null : id(row.service_id),
    contract_id: row.contract_id == null ? null : id(row.contract_id),
  };
}
export function portalDetail(payload, ticketId) {
  const ticket = portalTicket(payload.ticket);
  check(ticket.id === ticketId);
  const notes = list(payload.notes, row => {
    check(['customer', 'public_without_notification'].includes(row.visibility));
    return {
      id: id(row.id),
      body: text(row.body),
      attachments: list(row.attachments, file),
    };
  });
  const replies = list(payload.replies, row => ({
    id: id(row.id),
    body: text(row.body),
    attachments: list(row.attachments, file),
  }));
  return {
    ticket,
    notes,
    replies,
    conversations: list(payload.conversations, id),
    tasks: list(payload.tasks, row => ({
      id: id(row.id),
      title: text(row.title),
      status: text(row.status),
    })),
    sla: list(payload.sla ?? [], row => {
      check(
        ['first_response', 'attendance', 'resolution', 'ola'].includes(row.kind)
      );
      check(['running', 'paused', 'completed', 'stopped'].includes(row.state));
      check(['business', 'calendar'].includes(row.time_basis));
      check(typeof row.breached === 'boolean');
      return {
        kind: row.kind,
        state: row.state,
        budget_seconds: finite(row.budget_seconds, 1),
        elapsed_seconds: finite(row.elapsed_seconds),
        remaining_seconds: finite(row.remaining_seconds),
        consumed_percent: finite(row.consumed_percent),
        breached: row.breached,
        due_at: timestamp(row.due_at),
        observed_at: timestamp(row.observed_at),
        achieved_at: optionalTime(row.achieved_at),
        timezone: timezone(row.timezone),
        time_basis: row.time_basis,
      };
    }),
    notification_history: list(payload.notification_history ?? [], row => {
      check(['email', 'whatsapp'].includes(row.channel));
      check(
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
      check(Number.isSafeInteger(row.attempt_number) && row.attempt_number > 0);
      if (row.visibility != null)
        check(
          ['customer', 'public_without_notification'].includes(row.visibility)
        );
      return {
        id: id(row.id),
        channel: row.channel,
        state: row.state,
        attempt_number: row.attempt_number,
        created_at: timestamp(row.created_at),
        updated_at: timestamp(row.updated_at),
        sent_at: optionalTime(row.sent_at),
        delivered_at: optionalTime(row.delivered_at),
        body: row.body == null ? null : text(row.body),
      };
    }),
    surveys: list(payload.surveys ?? [], row => {
      check(['nps', 'csat', 'ces', 'custom'].includes(row.kind));
      return {
        id: id(row.id),
        kind: row.kind,
        expires_at: timestamp(row.expires_at),
        path: nativePath(row.path, '/jrc/relacionamento/pesquisas/'),
      };
    }),
  };
}
