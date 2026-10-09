import { canonicalId } from './access.js';
import { assertEnvelope, integer } from './operationalRules.mjs';
const assert = value => {
  if (!value) throw new TypeError('Invalid operational result');
};
const object = value =>
  value !== null && typeof value === 'object' && !Array.isArray(value);
const count = value => integer(value, 0);
const id = value => {
  const result = canonicalId(value);
  assert(result);
  return result;
};
const stamp = value => {
  assert(typeof value === 'string' && Number.isFinite(Date.parse(value)));
  return value;
};
export const reportDimensions = Object.freeze([
  'by_unit',
  'by_service',
  'by_origin',
  'by_category',
  'by_priority',
  'by_customer',
]);
export function decodeMetrics(value, context) {
  assert(
    object(value) &&
      value.cohort === 'authorized_tickets_opened_in_half_open_period'
  );
  const dimensions = {};
  reportDimensions.forEach(key => {
    if (value[key] === null) {
      dimensions[key] = null;
      return;
    }
    const data = value[key];
    assert(
      object(data) &&
        Array.isArray(data.items) &&
        data.items.length <= 100 &&
        typeof data.truncated === 'boolean'
    );
    dimensions[key] = {
      truncated: data.truncated,
      items: data.items.map(row => {
        assert(row.id === null || typeof row.id === 'string');
        if (row.id !== null && key !== 'by_origin') id(row.id);
        return { id: row.id, count: count(row.count) };
      }),
    };
  });
  const has = key =>
    context.effective_permissions?.includes(`jrc_service_desk_${key}`);
  if (!has('customers_view')) assert(dimensions.by_customer === null);
  let reopen = null;
  if (value.reopen !== null) {
    assert(has('history_view') && object(value.reopen));
    reopen = Object.fromEntries(
      ['events', 'tickets', 'cohort_ticket_count', 'closed_tickets'].map(
        key => [key, count(value.reopen[key])]
      )
    );
    const rate = value.reopen.cohort_reopen_percentage;
    assert(
      rate === null ||
        (typeof rate === 'number' &&
          Number.isFinite(rate) &&
          rate >= 0 &&
          rate <= 100)
    );
    reopen.cohort_reopen_percentage = rate;
  }
  let sla = null;
  if (value.sla !== null) {
    assert(has('sla_view') && object(value.sla));
    sla = Object.fromEntries(
      ['first_response', 'attendance', 'resolution'].map(kind => {
        const row = value.sla[kind];
        assert(object(row));
        const result = Object.fromEntries(
          [
            'observed',
            'completed',
            'completed_breached',
            'running_overdue',
          ].map(key => [key, count(row[key])])
        );
        const mean = row.mean_elapsed_seconds;
        assert(
          mean === null ||
            (typeof mean === 'number' && Number.isFinite(mean) && mean >= 0)
        );
        result.mean_elapsed_seconds = mean;
        return [kind, result];
      })
    );
  }
  let channels = null;
  if (value.by_channel !== null) {
    assert(
      has('conversations_view') &&
        Array.isArray(value.by_channel) &&
        value.by_channel.length <= 100
    );
    channels = value.by_channel.map(row => {
      assert(typeof row.channel_type === 'string');
      return { channel_type: row.channel_type, count: count(row.count) };
    });
  }
  assert(value.fcr?.value === null && value.quality?.value === null);
  return {
    observed_at: stamp(value.observed_at),
    total: count(value.total),
    ...dimensions,
    by_channel: channels,
    reopen,
    sla,
  };
}
export function decodeRecurrences(payload, context, unit) {
  assertEnvelope(payload, context, unit);
  const value = payload.recurrence;
  assert(
    object(value) &&
      typeof value.enabled === 'boolean' &&
      typeof value.truncated === 'boolean' &&
      Array.isArray(value.groups) &&
      value.groups.length <= 1000
  );
  const groups = value.groups.map(row => {
    assert(typeof row.key === 'string' && /^[a-f0-9]{64}$/.test(row.key));
    assert(Array.isArray(row.ticket_ids) && row.ticket_ids.length <= 2000);
    const tickets = row.ticket_ids.map(id);
    assert(
      new Set(tickets).size === tickets.length &&
        count(row.count) === tickets.length
    );
    assert(Array.isArray(row.unlinked_ticket_ids));
    const unlinked = row.unlinked_ticket_ids.map(id);
    assert(
      new Set(unlinked).size === unlinked.length &&
        unlinked.every(item => tickets.includes(item))
    );
    return {
      key: row.key,
      count: row.count,
      ticket_ids: tickets,
      unlinked_ticket_ids: unlinked,
    };
  });
  return { enabled: value.enabled, truncated: value.truncated, groups };
}
export function parseTicketIds(text) {
  assert(typeof text === 'string' && text.length <= 2200);
  const values = text
    .trim()
    .split(/[\s,;]+/)
    .filter(Boolean)
    .map(id);
  assert(
    values.length > 0 &&
      values.length <= 100 &&
      new Set(values).size === values.length
  );
  return values;
}
export function batchAttributes(action, tickets, body, visibility) {
  assert(
    ['link', 'note'].includes(action) &&
      Array.isArray(tickets) &&
      tickets.length > 0 &&
      tickets.length <= 100
  );
  const rows = tickets.map(ticket => ({
    id: id(ticket.id),
    lock_version: count(ticket.lock_version),
  }));
  assert(new Set(rows.map(row => row.id)).size === rows.length);
  if (action === 'link') return { action, tickets: rows };
  assert(['internal', 'public_without_notification'].includes(visibility));
  assert(
    typeof body === 'string' && body.trim().length > 0 && body.length <= 4000
  );
  return { action, tickets: rows, body, visibility };
}
export function decodeBatchPreview(payload, context, unit, batch) {
  assertEnvelope(payload, context, unit);
  const value = payload.preview;
  assert(
    object(value) &&
      typeof value.receipt === 'string' &&
      value.receipt.length > 0 &&
      value.action === batch.action
  );
  const requested = batch.tickets.map(row => id(row.id)).sort();
  assert(
    Array.isArray(value.ticket_ids) &&
      JSON.stringify(value.ticket_ids.map(id).sort()) ===
        JSON.stringify(requested)
  );
  assert(Array.isArray(value.notes));
  const notes = value.notes.map(row => {
    assert(
      batch.action === 'note' &&
        requested.includes(id(row.ticket_id)) &&
        row.body === batch.body &&
        row.visibility === batch.visibility
    );
    assert(typeof row.receipt === 'string' && row.receipt.length > 0);
    return {
      ticket_id: id(row.ticket_id),
      body: row.body,
      visibility: row.visibility,
      receipt: row.receipt,
    };
  });
  assert(
    batch.action === 'note'
      ? notes.length === requested.length &&
          new Set(notes.map(row => row.ticket_id)).size === requested.length
      : notes.length === 0
  );
  return {
    receipt: value.receipt,
    action: value.action,
    ticket_ids: requested,
    notes,
    expires_at: stamp(value.expires_at),
  };
}
