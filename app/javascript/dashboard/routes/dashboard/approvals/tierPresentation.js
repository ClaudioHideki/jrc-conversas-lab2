/* global BigInt */
// Names come only from the native options already authorized for this editor.
export const approvalStageLabel = (step, options, fallback) => {
  const names = (step?.assignees || [])
    .map(rule => {
      const source = {
        account_user: 'account_users',
        team: 'teams',
        custom_role: 'custom_roles',
      }[rule.type];
      return (options[source] || []).find(row => row.id === rule.id)?.name;
    })
    .filter(Boolean);
  return names.join(', ') || fallback;
};

export const minorAmountFields = [
  'total_cents',
  'gratuity_total_cents',
  'below_minimum_total_cents',
];
export const minorAmountText = value => {
  if (!Number.isSafeInteger(value))
    return typeof value === 'number' ? '—' : String(value ?? '');
  const cents = BigInt(value);
  const absolute = cents < 0n ? -cents : cents;
  return `${cents < 0n ? '-' : ''}${absolute / 100n}.${String(absolute % 100n).padStart(2, '0')}`;
};
