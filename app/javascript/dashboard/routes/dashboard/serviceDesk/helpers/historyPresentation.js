// No lookup, mutation or reconstruction of fields redacted by the backend.
const LABEL_FIELDS = Object.freeze({
  status_id: 'status',
  from_status_id: 'status',
  to_status_id: 'status',
  priority_id: 'priority',
  category_id: 'category',
  queue_id: 'queue',
  target_queue_id: 'queue',
  team_id: 'team',
  company_id: 'company',
});
const VISIBLE_FIELDS = Object.freeze([
  'title',
  'status_id',
  'from_status_id',
  'to_status_id',
  'priority_id',
  'category_id',
  'queue_id',
  'target_queue_id',
  'team_id',
  'company_id',
  'assignee_membership_id',
  'status',
  'action',
  'mode',
  'kind',
  'clock_kind',
  'percent',
  'due_at',
  'observed_at',
  'achieved_at',
  'budget_seconds',
  'elapsed_seconds',
  'version',
  'policy_version',
  'resource_kind',
  'notification_state',
  'channel',
  'state',
]);
const scalar = value =>
  typeof value === 'string' ||
  typeof value === 'number' ||
  typeof value === 'boolean';
export function sameHistoryScope(event, ticket) {
  return !!(
    event &&
    ticket &&
    event.account_id != null &&
    event.unit_id != null &&
    event.ticket_id != null &&
    String(event.account_id) === String(ticket.account_id) &&
    String(event.unit_id) === String(ticket.unit_id) &&
    String(event.ticket_id) === String(ticket.id)
  );
}
export function historyFields(event, ticket) {
  if (!sameHistoryScope(event, ticket)) return [];
  const data = event.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) return [];
  return VISIBLE_FIELDS.filter(
    key => Object.hasOwn(data, key) && scalar(data[key])
  ).map(key => {
    const value = data[key];
    const field = LABEL_FIELDS[key];
    const candidate = field && ticket[field];
    const name =
      candidate &&
      String(candidate.id) === String(value) &&
      typeof candidate.name === 'string'
        ? candidate.name
        : null;
    return { key, value: name || String(value), named: !!name };
  });
}
export function historyChanges(event, ticket) {
  if (!sameHistoryScope(event, ticket)) return [];
  const changes = event?.data?.changes;
  if (!changes || typeof changes !== 'object' || Array.isArray(changes))
    return [];
  return Object.entries(changes)
    .filter(
      ([key, value]) =>
        [
          'status',
          'title',
          'due_at',
          'priority',
          'assignee_account_user_id',
          'owner_account_user_id',
          'severity',
        ].includes(key) &&
        Array.isArray(value) &&
        value.length === 2 &&
        value.every(item => item === null || scalar(item))
    )
    .map(([key, values]) => ({ key, before: values[0], after: values[1] }));
}
