import { helpdeskDraftInput } from './helpdeskDraftInput';

export const helpdeskValue = (item, empty) =>
  item === null || item === undefined ? empty : String(item);

export const helpdeskRows = (payload, empty, prefix = '') =>
  Object.entries(payload || {}).flatMap(([key, item]) => {
    const field = prefix ? `${prefix}.${key}` : key;
    if (Array.isArray(item))
      return item.flatMap((entry, index) =>
        typeof entry === 'object' && entry !== null
          ? helpdeskRows(entry, empty, `${field}[${index}]`)
          : [
              {
                field: `${field}[${index}]`,
                value: helpdeskValue(entry, empty),
              },
            ]
      );
    if (item !== null && typeof item === 'object')
      return helpdeskRows(item, empty, field);
    return [{ field, value: helpdeskValue(item, empty) }];
  });

export const helpdeskMetricValue = (metric, empty) => {
  if (metric.state !== 'available' || !Number.isFinite(metric.value))
    return empty;
  return metric.unit === 'percent'
    ? `${metric.value.toFixed(1)}%`
    : String(metric.value);
};

export const helpdeskDate = (value, empty, timeZone) => {
  if (!value || !Number.isFinite(Date.parse(value))) return empty;
  try {
    return new Date(value).toLocaleString(
      undefined,
      timeZone ? { timeZone } : {}
    );
  } catch {
    return empty;
  }
};

export const HELPDESK_GROUPS = [
  'A1',
  'A2',
  'A3',
  'A4',
  'B1',
  'B2',
  'C1',
  'C2',
  'D1',
  'D2',
  'E',
];

export const helpdeskGroupDefaults = groups =>
  Object.fromEntries(
    HELPDESK_GROUPS.map(key => [
      key,
      { enabled: groups?.[key]?.enabled === true },
    ])
  );

export function helpdeskGroupInput(input) {
  const result = helpdeskDraftInput(input);
  if (input.query?.trim()) result.query = input.query.trim();
  if (input.summary?.trim()) result.summary = input.summary.trim();
  if (input.binding_id) result.binding_id = Number(input.binding_id);
  if (input.conversation_id)
    result.conversation_id = Number(input.conversation_id);
  if (input.activity?.title?.trim()) {
    result.activity = {
      title: input.activity.title.trim(),
      due_at: input.activity.due_at?.trim() || '',
    };
    if (input.activity.lead_id)
      result.activity.lead_id = Number(input.activity.lead_id);
    if (input.activity.deal_id)
      result.activity.deal_id = Number(input.activity.deal_id);
    if (input.activity.description?.trim())
      result.activity.description = input.activity.description.trim();
  }
  if (input.reply?.content?.trim())
    result.reply = {
      conversation_id: Number(input.reply.conversation_id),
      content: input.reply.content.trim(),
    };
  ['classification', 'handoff'].forEach(part => {
    const fields = Object.fromEntries(
      Object.entries(input[part] || {})
        .filter(([, item]) => item !== '' && item != null)
        .map(([key, item]) => [
          key,
          key === 'service_fields' ? item : Number(item),
        ])
    );
    if (Object.keys(fields).length) result[part] = fields;
  });
  return result;
}

export function helpdeskCurrentClassification(ticket, source, previous = {}) {
  if (
    !ticket ||
    ticket.unit_id !== String(source.unit_id) ||
    ticket.id !== String(source.ticket_id) ||
    (ticket.service?.id || null) !==
      (source.service_id ? String(source.service_id) : null)
  )
    throw new TypeError('Native ticket readback mismatch');
  const classification = { ...previous };
  ['ticket_type', 'category', 'subcategory', 'priority', 'contract'].forEach(
    field => {
      if (
        Object.hasOwn(ticket, field) &&
        !Object.hasOwn(classification, `${field}_id`)
      )
        classification[`${field}_id`] = ticket[field]?.id || '';
    }
  );
  if (
    Object.hasOwn(ticket, 'service_fields') &&
    !Object.hasOwn(classification, 'service_fields')
  )
    classification.service_fields = { ...ticket.service_fields };
  return classification;
}
