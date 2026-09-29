// Date-only values remain calendar dates; timed values use the account timezone.
export function formatAgendaDue(entry, timeZone) {
  if (entry.due_type === 'date')
    return entry.due.split('-').reverse().join('/');
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(entry.due));
}

export function agendaTarget(entry, accountId) {
  const params = { accountId };
  if (entry.kind === 'project_task')
    return {
      name: 'jrc_projects_detail',
      params: { ...params, projectId: entry.project_id },
      query: { taskId: entry.task_id },
    };
  return {
    name: 'crm_activities',
    params,
    query:
      entry.kind === 'crm_follow_up'
        ? { followUpId: entry.follow_up_id }
        : { activityId: entry.activity_id },
  };
}
