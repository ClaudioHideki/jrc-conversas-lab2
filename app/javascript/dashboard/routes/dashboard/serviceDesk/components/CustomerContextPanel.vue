<script setup>
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
const props = defineProps({ ticket: { type: Object, required: true } });
const { enabled: hasCustomerMaster, accountScopedRoute: masterRoute } = useCustomerMaster();
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskNative';
import State from './ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeCustomerContext } from '../helpers/nativeIntegration';
import { errorStatus } from '../helpers/session';
const { t } = useI18n(); const session = useServiceDesk();
const value = ref(null); const status = ref('idle');
const allowed = computed(() => props.ticket.permissions.view_customer === true && session.state.status === 'ready');
let epoch = 0; let controller;
const load = async () => {
  const turn = ++epoch; controller?.abort(); value.value = null;
  if (!allowed.value) { status.value = 'denied'; return; }
  const context = session.state.context, ticket = props.ticket;
  controller = new AbortController();
  status.value = 'loading';
  try {
    const payload = await API.customer(context.account_id, ticket.id, controller.signal);
    if (turn !== epoch || context !== session.state.context || !allowed.value) return;
    value.value = decodeCustomerContext(payload, context, ticket); status.value = 'ready';
  } catch (error) {
    if (turn !== epoch || context !== session.state.context) return;
    status.value = errorStatus(error, true);
    if ([401, 403].includes(error?.response?.status)) { session.dispose(); session.state.status = status.value; }
  }
};
watch([() => props.ticket.id, allowed, () => session.state.context], load, { immediate: true });
onBeforeUnmount(() => { epoch += 1; controller?.abort(); value.value = null; });
</script>
<template>
  <section class="border-t border-n-weak mt-4 pt-4">
    <h3 class="text-sm font-semibold">{{ t('JRC_SERVICE_DESK.NATIVE.customer_context') }}</h3>
    <dl v-if="status === 'ready'" class="sd-detail-list">
      <dt>{{ t('JRC_SERVICE_DESK.FIELDS.requester') }}</dt><dd>{{ value.contact.name }}</dd>
      <dt>{{ t('JRC_SERVICE_DESK.COMMON.client_company') }}</dt>
      <dd>
        <RouterLink
          v-if="hasCustomerMaster && value.company"
          class="text-n-brand underline"
          :to="
            masterRoute('jrc_customer_company', { companyId: value.company.id })
          "
          >{{ value.company.name }}</RouterLink
        ><template v-else>{{
          value.company?.name ||
          t(`JRC_SERVICE_DESK.NATIVE.${value.company_state}`)
        }}</template>
      </dd>
    </dl>
    <State v-else :status="status" compact retry @retry="load" />
  </section>
</template>
