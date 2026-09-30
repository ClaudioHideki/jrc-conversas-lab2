import { useI18n } from 'vue-i18n';

// Presentation only: keep API values and customer-defined labels unchanged.
export function useCommercialLabels() {
  const { t, te } = useI18n();
  const label = (group, value) => {
    const key = `CRM.${group}.${String(value || '').toUpperCase()}`;
    // Only translate catalogued enum labels; never rewrite customer-defined text.
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    return te(key) ? t(key) : value || '—';
  };
  return {
    statusLabel: value => label('STATUS', value),
    issueTypeLabel: value => label('ISSUE_TYPE', value),
  };
}
