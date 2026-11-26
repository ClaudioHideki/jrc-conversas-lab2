const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);

const operations = {
  project_task: ['create_task'],
  crm: ['create_lead', 'create_activity'],
  service_desk: ['create_ticket', 'update_ticket'],
};
const targetKinds = {
  create_task: 'project_task',
  create_lead: 'crm_lead',
  create_activity: 'crm_activity',
  create_ticket: 'service_desk_ticket',
  update_ticket: 'service_desk_ticket',
};

// Public identities contain their immutable ledger, not an ambiguous numeric ID.
// A typed row may never be passed to the existing legacy pending-run endpoint.
export const validDestinationHistoryRow = row => {
  if (!['legacy', 'typed'].includes(row.ledger)) return false;
  if (!identifier(row.attempt_id)) return false;
  if (row.id !== `${row.ledger}:${row.attempt_id}`) return false;
  if (!operations[row.destination_kind]?.includes(row.operation)) return false;
  if (
    row.ledger === 'legacy' &&
    (row.destination_kind !== 'project_task' || row.operation !== 'create_task')
  )
    return false;
  if (row.ledger === 'typed') {
    if (row.can_reprocess_pending !== false) return false;
    if (typeof row.can_resume_pending !== 'boolean') return false;
    if (typeof row.can_retry_selected !== 'boolean') return false;
    if (row.can_resume_pending && row.outcome !== 'pending') return false;
    if (row.can_retry_selected && !['failed', 'blocked'].includes(row.outcome))
      return false;
    if (row.can_resume_pending || row.can_retry_selected) {
      if (!identifier(row.readiness_id)) return false;
      if (typeof row.rule_sha256 !== 'string') return false;
      if (!/^[a-f0-9]{64}$/.test(row.rule_sha256)) return false;
    } else if (row.readiness_id !== null || row.rule_sha256 !== null)
      return false;
  }
  if (row.target === null) return true;
  return (
    identifier(row.target?.id) &&
    row.target.kind === targetKinds[row.operation] &&
    (row.target.kind !== 'project_task' || identifier(row.target.project_id))
  );
};

export const destinationHistoryRoute = (target, accountId) => {
  if (!target || !identifier(String(accountId)) || !identifier(target.id))
    return null;
  const params = { accountId };
  switch (target.kind) {
    case 'project_task':
      return identifier(target.project_id)
        ? {
            name: 'jrc_projects_detail',
            params: { ...params, projectId: target.project_id },
            query: { tab: 'board', taskId: target.id },
          }
        : null;
    case 'crm_lead':
      return { name: 'crm_leads', params, query: { leadId: target.id } };
    case 'crm_activity':
      return {
        name: 'crm_activities',
        params,
        query: { activityId: target.id },
      };
    case 'service_desk_ticket':
      return {
        name: 'jrc_service_desk_detail',
        params: { ...params, ticketId: target.id },
      };
    default:
      return null;
  }
};
