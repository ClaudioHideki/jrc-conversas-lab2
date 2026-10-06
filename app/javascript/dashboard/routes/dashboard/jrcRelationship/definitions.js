export const SCREENS = [
  'overview',
  'portfolio',
  'actions',
  'health',
  'risks',
  'plans',
  'qbrs',
  'renewals',
  'expansion',
  'surveys',
  'playbooks',
  'reports',
  'settings',
];
export const STATES = {
  actions: ['open', 'in_progress', 'waiting_customer', 'completed', 'dismissed'],
  risks: [
    'detected',
    'analyzing',
    'planned',
    'negotiating',
    'retained',
    'churn',
    'no_action',
  ],
  plans: ['active', 'completed', 'paused', 'canceled'],
  qbrs: ['scheduled', 'completed', 'canceled'],
  renewals: ['open', 'negotiating', 'won', 'lost'],
  expansion: ['suggested', 'approved', 'rejected', 'converted'],
};
export const FIELDS = {
  actions: ['reason', 'status', 'priority', 'due_at', 'result', 'owner_id'],
  risks: ['reason', 'kind', 'severity', 'status', 'due_at', 'outcome', 'owner_id'],
  plans: ['title', 'status', 'target_on', 'project_id', 'owner_id'],
  qbrs: ['title', 'status', 'scheduled_at', 'agenda', 'summary', 'owner_id'],
  renewals: ['status', 'proposed_mrr_cents'],
  expansion: ['title', 'status', 'expansion_kind', 'potential_cents', 'product_id', 'evidence'],
  surveys: ['kind'],
};
export const inputClass =
  'w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12';
export const buttonClass =
  'inline-flex items-center justify-center gap-2 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50';
export const money = (value, formatting = {}) =>
  value === null || value === undefined
    ? '—'
    : new Intl.NumberFormat(formatting?.locale || 'pt-BR', {
        style: 'currency',
        currency: formatting?.currency || 'BRL',
      }).format(Number(value) / 100);
export const date = (value, formatting = {}) =>
  value
    ? new Intl.DateTimeFormat(formatting?.locale || 'pt-BR', {
        dateStyle: 'short',
        ...(value.length === 10 ? { timeZone: 'UTC' } : { timeStyle: 'short', timeZone: formatting?.timeZone }),
      }).format(new Date(value.length === 10 ? `${value}T12:00:00Z` : value))
    : '—';
export const message = error =>
  error.response?.data?.errors?.join?.('. ') ||
  error.response?.data?.error ||
  error.message;
