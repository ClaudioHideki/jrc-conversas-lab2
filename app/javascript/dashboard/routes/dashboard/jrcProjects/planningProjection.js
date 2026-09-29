// Read-only projection of existing records; no independent schedule state.
const day = value =>
  value ? Date.parse(`${value}T12:00:00Z`) / 86400000 : null;

export function projectTimeline(project, tasks, milestones) {
  const taskById = new Map(tasks.map(task => [task.id, task]));
  const rows = [
    {
      key: `project-${project.id}`,
      kind: 'project',
      record: project,
      title: project.name,
    },
    ...tasks.map(task => ({
      key: `task-${task.id}`,
      kind: task.parent_id ? 'subtask' : 'task',
      record: task,
      title: task.title,
      parent: taskById.get(task.parent_id) || null,
    })),
    ...milestones.map(milestone => ({
      key: `milestone-${milestone.id}`,
      kind: 'milestone',
      record: milestone,
      title: milestone.name,
    })),
  ].map(row => ({
    ...row,
    start: day(row.record.starts_on || row.record.due_on),
    end: day(row.record.due_on || row.record.starts_on),
  }));
  const days = rows
    .flatMap(row => [row.start, row.end])
    .filter(value => value !== null);
  const range = days.length
    ? { start: Math.min(...days), end: Math.max(...days) }
    : null;
  return { rows, range };
}

export function timelineBar(row, range) {
  if (!range || row.start === null || row.end === null) return null;
  const span = range.end - range.start + 1;
  return {
    x: ((row.start - range.start) / span) * 1000,
    width: Math.max(1, ((row.end - row.start + 1) / span) * 1000),
  };
}
