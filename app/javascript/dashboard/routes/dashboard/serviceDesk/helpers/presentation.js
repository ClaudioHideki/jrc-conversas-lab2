export const CATALOG_COLUMNS = Object.freeze({
  queues: ['name', 'code', 'unit', 'team', 'active'],
  priorities: ['name', 'code', 'unit', 'active'],
  categories: ['name', 'code', 'unit', 'active'],
  statuses: ['name', 'code', 'unit', 'active'],
  units: ['name', 'code', 'operator_company', 'active'],
  operator_companies: ['name', 'code', 'active'],
  assignees: ['name', 'unit', 'active'],
});
export const PLANNED_SCREENS = Object.freeze({
  sla: { columns: ['name', 'service', 'priority', 'calendar', 'version'], sections: ['first_response', 'resolution', 'calendar'], actions: ['start', 'view_calendar'] },
  catalog: { columns: ['name', 'category', 'queue', 'sla'], sections: ['description', 'coverage', 'team'], actions: ['start'] },
  knowledge: { columns: ['title', 'category', 'status', 'updated_at'], sections: ['description', 'owner', 'version'], actions: ['start', 'publish'] },
  approvals: { columns: ['title', 'requester', 'status', 'due_at'], sections: ['description', 'assignee', 'history'], actions: ['approve', 'reject'] },
  problems: { columns: ['title', 'priority', 'status', 'assignee'], sections: ['description', 'related', 'solution'], actions: ['start'] },
  changes: { columns: ['title', 'type', 'status', 'schedule'], sections: ['description', 'approvals', 'history'], actions: ['start', 'approve', 'view_calendar'] },
  assets: { columns: ['name', 'type', 'status', 'unit'], sections: ['description', 'contract', 'history'], actions: ['start', 'import'] },
  contracts: { columns: ['code', 'name', 'service', 'version'], sections: ['coverage', 'sla', 'history'], actions: [] },
  automations: { columns: ['name', 'trigger', 'active', 'updated_at'], sections: ['description', 'rules', 'history'], actions: ['start', 'simulate', 'activate'] },
  surveys: { columns: ['name', 'type', 'status', 'rating'], sections: ['description', 'measurements', 'history'], actions: ['start', 'survey_send'] },
  reports: { columns: ['title', 'type', 'updated_at'], sections: ['sla', 'category', 'source'], actions: [] },
});
export function formatTimestamp(value, locale) {
  if (!value)
    return null;
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()))
    return null;
  return new Intl.DateTimeFormat(locale.replace('_', '-'), { dateStyle: 'short', timeStyle: 'short' }).format(date);
}
export function catalogValue(record, field, context) {
  const unit = context?.units.find(item => item.id === (record.unit_id || record.id));
  if (field === 'unit')
    return unit?.name || '';
  if (field === 'operator_company')
    return unit?.operator_company?.name || '';
  if (field === 'team')
    return record.team?.name || '';
  return record[field] ?? '';
}
