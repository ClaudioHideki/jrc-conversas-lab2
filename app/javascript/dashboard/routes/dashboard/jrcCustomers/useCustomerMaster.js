import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
export function useCustomerMaster() {
  const { accountId, accountScopedRoute, currentAccount } = useAccount();
  const feature = useMapGetter('accounts/isFeatureEnabledonAccount');
  const role = useMapGetter('getCurrentRole');
  const user = useMapGetter('getCurrentUser');
  const enabled = computed(() =>
    Boolean(feature.value(accountId.value, FEATURE_FLAGS.JRC_CUSTOMER_MASTER))
  );
  const canAccess = computed(() => {
    if (!enabled.value) return false;
    const membership = (user.value?.accounts || []).find(
      item => Number(item.id) === accountId.value
    );
    if (!membership) return false;
    return (
      membership.role === 'administrator' ||
      !membership.custom_role_id ||
      membership.permissions?.includes('contact_manage')
    );
  });
  const canAdmin = computed(
    () => canAccess.value && role.value === 'administrator'
  );
  const date = value => {
    if (!value) return '\u2014';
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return '\u2014';
    const options = { dateStyle: 'short', timeStyle: 'short' };
    if (currentAccount.value?.reporting_timezone)
      options.timeZone = currentAccount.value.reporting_timezone;
    try {
      return new Intl.DateTimeFormat('pt-BR', options).format(parsed);
    } catch {
      return parsed.toLocaleString('pt-BR');
    }
  };
  return { accountId, enabled, canAccess, canAdmin, accountScopedRoute, date };
}
