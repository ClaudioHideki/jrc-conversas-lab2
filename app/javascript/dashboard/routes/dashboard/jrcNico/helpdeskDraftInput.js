const id = value => Number.isSafeInteger(Number(value)) && Number(value) > 0;
const rows = (value, field) =>
  Array.isArray(value) &&
  value.every(row => row && id(row.id) && typeof row[field] === 'string');

export function helpdeskDraftChoices(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const result = {};
  if (value.campaign) {
    if (
      !rows(value.campaign.incidents, 'title') ||
      !rows(value.campaign.inboxes, 'name')
    )
      return null;
    result.campaign = value.campaign;
  }
  if (value.knowledge) {
    if (!rows(value.knowledge.closed_cases, 'title')) return null;
    result.knowledge = value.knowledge;
  }
  return result;
}

export function helpdeskDraftInput(input) {
  const result = {};
  if (input.campaign?.name?.trim()) {
    result.campaign = {
      incident_id: Number(input.campaign.incident_id),
      inbox_id: Number(input.campaign.inbox_id),
      name: input.campaign.name.trim(),
    };
  }
  if (input.knowledge?.title?.trim()) {
    result.knowledge = {
      closed_transition_id: Number(input.knowledge.closed_transition_id),
      title: input.knowledge.title.trim(),
      body: input.knowledge.body?.trim() || '',
      generalization_reviewed: input.knowledge.generalization_reviewed === true,
    };
  }
  return result;
}
