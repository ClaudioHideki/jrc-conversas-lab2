export const stageTones = {
  request: 'blue',
  analysis: 'blue',
  documentation: 'amber',
  contract: 'cyan',
  implementation: 'teal',
  provisioning: 'violet',
  finance: 'amber',
  issues: 'rose',
  approval: 'violet',
  completed: 'teal',
};
export const stageIcons = {
  request: 'i-lucide-inbox',
  analysis: 'i-lucide-search',
  documentation: 'i-lucide-files',
  contract: 'i-lucide-file-signature',
  implementation: 'i-lucide-list-checks',
  provisioning: 'i-lucide-server',
  finance: 'i-lucide-wallet',
  issues: 'i-lucide-triangle-alert',
  approval: 'i-lucide-check-check',
  completed: 'i-lucide-circle-check',
};
export const statusStrokes = {
  pending: 'stroke-blue-500',
  in_progress: 'stroke-cyan-500',
  waiting_customer: 'stroke-amber-500',
  blocked: 'stroke-rose-500',
  approved: 'stroke-violet-500',
  rejected: 'stroke-red-700',
  canceled: 'stroke-slate-500',
  completed: 'stroke-teal-500',
};
export const statusDots = {
  pending: 'bg-blue-500',
  in_progress: 'bg-cyan-500',
  waiting_customer: 'bg-amber-500',
  blocked: 'bg-rose-500',
  approved: 'bg-violet-500',
  rejected: 'bg-red-700',
  canceled: 'bg-slate-500',
  completed: 'bg-teal-500',
};
export const money = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    (Number(value) || 0) / 100
  );
