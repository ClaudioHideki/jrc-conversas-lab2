import { useI18n } from 'vue-i18n';

export const stages = [
  'request',
  'analysis',
  'documentation',
  'contract',
  'implementation',
  'provisioning',
  'finance',
  'issues',
  'approval',
  'completed',
];
export const statuses = [
  'pending',
  'in_progress',
  'waiting_customer',
  'blocked',
  'approved',
  'rejected',
  'canceled',
  'completed',
];
export const priorities = ['low', 'normal', 'high', 'critical'];
export const kinds = ['fulfillment', 'approval', 'change', 'cancellation'];

export function useBackofficePresentation() {
  const { t, te, locale } = useI18n();
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  const text = key => t(`CRM.BACKOFFICE_WORKSPACE.${key}`);
  const label = value => {
    const key = `CRM.BACKOFFICE_WORKSPACE.VALUES.${value}`;
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    return te(key) || te(key, 'en') ? t(key) : value || '—';
  };
  const date = value =>
    value
      ? new Date(value).toLocaleString(
          locale.value === 'en' ? 'pt-BR' : locale.value.replace('_', '-')
        )
      : text('NO_DEADLINE');
  const late = item =>
    item.sla?.state === 'overdue' ||
    (['pending', 'in_progress', 'waiting_customer', 'blocked'].includes(
      item.status
    ) &&
      item.due_at &&
      new Date(item.due_at) < new Date());
  const destination = id => ({
    name: 'crm_backoffice_request',
    params: { requestId: id },
  });
  const deadline = item =>
    [
      item.due_at,
      item.sla.total_due_at,
      item.sla.stage_due_at,
      !item.sla.first_action_at && item.sla.first_action_due_at,
    ]
      .filter(Boolean)
      .sort((a, b) => new Date(a) - new Date(b))[0];
  const slaLabel = sla =>
    [sla.total_due_at, sla.stage_due_at, sla.first_action_due_at].some(Boolean)
      ? label(sla.state)
      : text('NO_SLA');
  return { text, label, date, late, destination, deadline, slaLabel };
}
