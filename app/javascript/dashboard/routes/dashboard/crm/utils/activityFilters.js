// Only filter the records already authorized and returned by the CRM API.
export const filterActivities = (activities, filters) => {
  const search = filters.search.trim().toLocaleLowerCase();
  return activities.filter(activity => {
    const completed =
      Boolean(activity.completed_at) || activity.status === 'completed';
    const canceled = ['canceled', 'cancelled'].includes(activity.status);
    const searchable = [
      activity.title,
      activity.related_label,
      activity.deal?.title,
      activity.lead?.name,
    ]
      .filter(Boolean)
      .join(' ')
      .toLocaleLowerCase();
    if (search && !searchable.includes(search)) return false;
    if (filters.type && activity.activity_type !== filters.type) return false;
    if (filters.owner && String(activity.user?.id) !== String(filters.owner))
      return false;
    if (filters.status === 'open') return !completed && !canceled;
    if (filters.status === 'overdue')
      return !completed && !canceled && activity.overdue;
    if (filters.status === 'completed') return completed;
    return true;
  });
};
