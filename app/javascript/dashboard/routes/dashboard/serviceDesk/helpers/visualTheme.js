// Presentation metadata only. Permissions and lifecycle options come from the API.
export const tones = Object.freeze({
  blue: {
    text: 'text-n-blue-11',
    soft: 'bg-n-blue-3 text-n-blue-11',
    gradient:
      'from-sky-100 via-blue-200 to-sky-300 dark:from-n-blue-3 dark:via-n-blue-3 dark:to-n-blue-4',
    solid: 'bg-blue-700 text-white',
    accent: 'accent-blue-700',
  },
  teal: {
    text: 'text-n-teal-11',
    soft: 'bg-n-teal-3 text-n-teal-11',
    gradient:
      'from-emerald-100 via-emerald-200 to-emerald-300 dark:from-n-teal-3 dark:via-n-teal-3 dark:to-n-teal-4',
    solid: 'bg-teal-700 text-white',
    accent: 'accent-teal-700',
  },
  iris: {
    text: 'text-n-iris-11',
    soft: 'bg-n-iris-3 text-n-iris-11',
    gradient:
      'from-violet-100 via-violet-200 to-violet-300 dark:from-n-iris-3 dark:via-n-iris-3 dark:to-n-iris-4',
    solid: 'bg-indigo-700 text-white',
    accent: 'accent-indigo-700',
  },
  amber: {
    text: 'text-n-amber-11',
    soft: 'bg-n-amber-3 text-n-amber-11',
    gradient:
      'from-amber-100 via-amber-200 to-amber-300 dark:from-n-amber-3 dark:via-n-amber-3 dark:to-n-amber-4',
    solid: 'bg-amber-800 text-white',
    accent: 'accent-amber-700',
  },
  ruby: {
    text: 'text-n-ruby-11',
    soft: 'bg-n-ruby-3 text-n-ruby-11',
    gradient:
      'from-rose-100 via-rose-200 to-rose-300 dark:from-n-ruby-3 dark:via-n-ruby-3 dark:to-n-ruby-4',
    solid: 'bg-rose-700 text-white',
    accent: 'accent-rose-700',
  },
});
export const screenTones = Object.freeze({
  overview: 'blue',
  tickets: 'blue',
  mine: 'teal',
  new: 'blue',
  queues: 'iris',
  assignees: 'teal',
  sla: 'amber',
  catalog: 'blue',
  knowledge: 'iris',
  tasks: 'blue',
  approvals: 'teal',
  incidents: 'ruby',
  problems: 'amber',
  changes: 'iris',
  assets: 'teal',
  contracts: 'iris',
  automations: 'iris',
  surveys: 'teal',
  reports: 'blue',
  settings: 'iris',
});
export const metricTones = Object.freeze({
  total: 'blue',
  active: 'iris',
  open: 'blue',
  waiting: 'amber',
  resolved: 'teal',
  closed: 'teal',
  cancelled: 'ruby',
  observed_cycles: 'blue',
  running_breached: 'ruby',
  completed_met: 'teal',
  completed_breached: 'ruby',
});
export const metricIcons = Object.freeze({
  total: 'i-lucide-ticket',
  active: 'i-lucide-activity',
  open: 'i-lucide-headset',
  waiting: 'i-lucide-clock',
  resolved: 'i-lucide-circle-check',
  closed: 'i-lucide-lock-keyhole',
  cancelled: 'i-lucide-circle-x',
});
