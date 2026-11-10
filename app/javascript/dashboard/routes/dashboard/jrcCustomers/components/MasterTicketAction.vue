<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/serviceDesk';
import { canonicalId } from '../../serviceDesk/helpers/access';
import { useCustomerMaster } from '../useCustomerMaster';
const props = defineProps({
  companyId: { type: [String, Number], default: null },
  contactId: { type: [String, Number], default: null },
});
const { t } = useI18n();
const { accountId, identity, canAccess, accountScopedRoute } =
  useCustomerMaster();
const userId = useMapGetter('getCurrentUserID');
const allowed = ref(false);
let controller;
watch(
  [identity, () => props.companyId, () => props.contactId, canAccess],
  async (_, __, cleanup) => {
    allowed.value = false;
    controller?.abort();
    controller = new AbortController();
    const request = controller;
    cleanup(() => request.abort());
    if (!canAccess.value || (!props.companyId && !props.contactId)) return;
    const account = canonicalId(accountId.value);
    const user = canonicalId(userId.value);
    try {
      const data = await API.context(account, request.signal);
      if (!request.signal.aborted)
        allowed.value =
          data.available === true &&
          canonicalId(data.account_id) === account &&
          canonicalId(data.user_id) === user &&
          data.effective_permissions?.includes(
            'jrc_service_desk_customers_view'
          ) &&
          data.units.some(unit => unit.permissions.create_ticket === true);
    } catch {
      if (!request.signal.aborted) allowed.value = false;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => controller?.abort());
const target = computed(() =>
  accountScopedRoute(
    'jrc_service_desk_new',
    {},
    {
      master_company_id: props.companyId || undefined,
      master_contact_id: props.contactId || undefined,
    }
  )
);
</script>

<template>
  <RouterLink
    v-if="allowed"
    :to="target"
    class="inline-flex items-center gap-2 rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm font-semibold text-n-blue-12"
  >
    <span
      class="i-lucide-ticket-plus size-4"
      aria-hidden="true"
    />
    {{ t('CRM.CUSTOMER_MASTER_360.NEW_TICKET') }}
  </RouterLink>
</template>
