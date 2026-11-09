// Page the already authorized, ordered appointments, retaining their day headers.
export const paginateCalendarDays = (days, requestedPage, pageSize = 25) => {
  const activities = days.flatMap(day => day.activities);
  const total = activities.length;
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const page = Math.max(1, Math.min(requestedPage, pages));
  const start = (page - 1) * pageSize;
  const visibleIds = new Set(
    activities.slice(start, start + pageSize).map(activity => activity.id)
  );
  return {
    total,
    pages,
    page,
    days: days
      .map(day => ({
        ...day,
        activities: day.activities.filter(activity => visibleIds.has(activity.id)),
      }))
      .filter(day => day.activities.length),
  };
};
