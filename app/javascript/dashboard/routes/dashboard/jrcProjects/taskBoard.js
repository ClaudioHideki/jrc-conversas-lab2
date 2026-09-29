/* global AggregateError */
export const projectTaskStatuses = {
  backlog: 'A fazer',
  in_progress: 'Em andamento',
  review: 'Em validação',
  completed: 'Concluído',
  blocked: 'Bloqueado',
  canceled: 'Cancelado',
};

// Both board and list consume the same filtered references, never task copies.
export function filterProjectTasks(tasks, filters, today) {
  const query = String(filters.q || '')
    .trim()
    .toLocaleLowerCase();
  const label = String(filters.label || '')
    .trim()
    .toLocaleLowerCase();
  const weekEnd = new Date(`${today}T12:00:00Z`);
  weekEnd.setUTCDate(weekEnd.getUTCDate() + 6);
  const lastDay = weekEnd.toISOString().slice(0, 10);
  return tasks.filter(task => {
    if (query && !task.title.toLocaleLowerCase().includes(query)) return false;
    if (
      filters.assignee &&
      String(task.assignee_id) !== String(filters.assignee)
    )
      return false;
    if (filters.status && task.status !== filters.status) return false;
    if (filters.priority && task.priority !== filters.priority) return false;
    if (
      label &&
      !(task.labels || []).some(value => value.toLocaleLowerCase() === label)
    )
      return false;
    if (filters.due === 'none') return !task.due_on;
    if (filters.due && !task.due_on) return false;
    if (filters.due === 'overdue')
      return (
        task.due_on < today && !['completed', 'canceled'].includes(task.status)
      );
    if (filters.due === 'today') return task.due_on === today;
    if (filters.due === 'week')
      return task.due_on >= today && task.due_on <= lastDay;
    return true;
  });
}

// Reload persisted state after every request, including rejection. The caller
// keeps interaction disabled if refreshing also fails; nothing is moved locally.
export async function persistTaskMove(sendMove, reload) {
  let moveError;
  try {
    await sendMove();
  } catch (error) {
    moveError = error;
  }
  try {
    await reload();
  } catch (refreshError) {
    if (moveError)
      throw new AggregateError(
        [moveError, refreshError],
        'Move and refresh failed'
      );
    throw refreshError;
  }
  if (moveError) throw moveError;
}
