export const homeTones = {
  blue: 'border-n-blue-6 bg-n-blue-2 text-n-blue-11',
  teal: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
  amber: 'border-n-amber-6 bg-n-amber-2 text-n-amber-11',
  ruby: 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11',
  violet: 'border-n-violet-6 bg-n-violet-2 text-n-violet-11',
  neutral: 'border-n-weak bg-n-slate-2 text-n-slate-11',
};

export const metricValue = value =>
  typeof value === 'number' && Number.isFinite(value) ? value : null;

// Display only: consume the existing Cockpit projection, never infer missing counts.
export const homeMetrics = (summary, crmAllowed) => [
  {
    key: 'WAITING',
    value: metricValue(summary.conversations_waiting),
    tone: 'blue',
    icon: 'i-lucide-messages-square',
  },
  {
    key: 'MISSED',
    value: metricValue(summary.missed_calls),
    tone: summary.missed_calls > 0 ? 'ruby' : 'teal',
    icon: 'i-lucide-phone-missed',
  },
  {
    key: 'SLA',
    value: metricValue(summary.sla_risk_count),
    tone: summary.sla_risk_count > 0 ? 'amber' : 'teal',
    icon: 'i-lucide-timer',
  },
  ...(crmAllowed
    ? [
        {
          key: 'TASKS',
          value: metricValue(summary.pending_tasks),
          tone: 'violet',
          icon: 'i-lucide-list-checks',
        },
      ]
    : []),
];
