import { reactive, watch } from 'vue';

export const statusTone = status =>
  ({
    planned:
      'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-200',
    active: 'bg-n-blue-3 text-n-blue-11',
    in_progress: 'bg-n-blue-3 text-n-blue-11',
    review:
      'bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-200',
    completed:
      'bg-emerald-50 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-200',
    blocked: 'bg-n-ruby-3 text-n-ruby-11',
    overdue: 'bg-n-ruby-3 text-n-ruby-11',
    on_hold:
      'bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-200',
  })[status] || 'bg-n-slate-3 text-n-slate-11';

export const priorityTone = priority =>
  ({
    urgent: 'bg-n-ruby-4 text-n-ruby-11',
    high: 'bg-n-ruby-3 text-n-ruby-11',
    medium:
      'bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-200',
    low: 'bg-n-blue-3 text-n-blue-11',
  })[priority] || 'bg-n-slate-3 text-n-slate-11';

export const initials = name =>
  String(name || '?')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map(part => part[0])
    .join('')
    .toLocaleUpperCase();

export function isOverdue(record, today) {
  return Boolean(
    record.due_on &&
      record.due_on < today &&
      !['completed', 'canceled'].includes(record.status)
  );
}

export function taskProgress(task) {
  if (!task.checklist_total) return 0;
  return Math.round((task.checklist_completed * 100) / task.checklist_total);
}

// Preferences are scoped to account, user and project; records are never cached.
export function useProjectPreferences(key, defaults) {
  const state = reactive({ ...defaults });
  let restoring = false;
  watch(
    key,
    value => {
      restoring = true;
      Object.assign(state, defaults);
      try {
        const saved = JSON.parse(window.localStorage.getItem(value) || '{}');
        Object.keys(defaults).forEach(field => {
          if (typeof saved[field] === typeof defaults[field]) {
            state[field] = saved[field];
          }
        });
      } catch {
        // Browser storage is optional; the current filters remain usable.
      }
      restoring = false;
    },
    { immediate: true, flush: 'sync' }
  );
  watch(
    state,
    () => {
      if (restoring) return;
      try {
        window.localStorage.setItem(key.value, JSON.stringify(state));
      } catch {
        // Restricted browser storage must not prevent normal project work.
      }
    },
    { deep: true, flush: 'sync' }
  );
  return state;
}
