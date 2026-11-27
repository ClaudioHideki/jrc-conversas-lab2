<script setup>
import {
  computed,
  defineAsyncComponent,
  onBeforeUnmount,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import CustomerAPI from 'dashboard/api/jrcCustomers';
import CallCenterAPI from 'dashboard/api/jrcContactCenter';
import { useCustomerMaster } from '../../jrcCustomers/useCustomerMaster';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  contactId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  enabled: { type: Boolean, default: false },
});
// Reuse native lists, navigation, pagination and signed timeline cursors.
// These components are loaded only after native source and directory checks.
const RecordsPanel = defineAsyncComponent(
  () => import('../../jrcCustomers/components/RecordsPanel.vue')
);
const TimelinePanel = defineAsyncComponent(
  () => import('../../jrcCustomers/components/TimelinePanel.vue')
);
const { t } = useI18n();
const {
  accountId: currentAccountId,
  identity,
  canAccess,
} = useCustomerMaster();
const authority = computed(() =>
  JSON.stringify([
    identity.value,
    props.accountId,
    props.contactId,
    props.callSessionId,
    props.callId,
    props.enabled,
  ])
);
const allowed = computed(
  () =>
    props.enabled &&
    canAccess.value &&
    String(currentAccountId.value) === String(props.accountId)
);
const loading = ref(false);
const error = ref('');
const capabilities = ref(null);
const selected = ref('');
let generation = 0;
let controller;
const tabLabels = computed(() => ({
  deals: t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.DEALS'),
  contracts: t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.CONTRACTS'),
  activities: t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.ACTIVITIES'),
  tickets: t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.TICKETS'),
  projects: t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.PROJECTS'),
  history: t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.HISTORY'),
}));
const tabs = computed(() => {
  if (!capabilities.value) return [];
  return [
    ...(capabilities.value.crm === true
      ? ['deals', 'contracts', 'activities']
      : []),
    ...(capabilities.value.service_desk === true ? ['tickets'] : []),
    ...(capabilities.value.projects === true ? ['projects'] : []),
    'history',
  ].map(key => ({
    key,
    label: tabLabels.value[key],
  }));
});
const clear = () => {
  generation += 1;
  controller?.abort();
  controller = null;
  loading.value = false;
  capabilities.value = null;
  selected.value = '';
  error.value = '';
};
async function open() {
  if (!allowed.value || loading.value) return;
  clear();
  const own = generation;
  const context = authority.value;
  loading.value = true;
  controller = new AbortController();
  try {
    const account = String(props.accountId);
    const contact = String(props.contactId);
    const { data: source } = await CallCenterAPI.call(
      account,
      props.callSessionId
    );
    if (own !== generation || context !== authority.value || !allowed.value)
      return;
    const call = source.item;
    const customer = call?.customer;
    if (
      String(source.account_id) !== account ||
      String(call?.id) !== String(props.callSessionId) ||
      call?.external_session_id !== props.callId ||
      String(call.contact_id) !== contact ||
      customer?.status !== 'identified' ||
      customer.ambiguous !== false ||
      customer.contacts?.length !== 1 ||
      String(customer.contacts[0].id) !== contact ||
      String(customer.directory?.contact_id) !== contact
    )
      throw new Error('native_source_identity_mismatch');
    const { data } = await CustomerAPI.contactOverview(contact, {
      accountId: account,
      signal: controller.signal,
    });
    if (own !== generation || context !== authority.value || !allowed.value)
      return;
    const rights = data.capabilities;
    if (
      !rights ||
      !['conversations', 'crm', 'service_desk', 'projects'].every(
        key => typeof rights[key] === 'boolean'
      )
    )
      throw new Error('native_customer_capabilities_invalid');
    capabilities.value = Object.fromEntries(
      ['crm', 'service_desk', 'projects'].map(key => [key, rights[key]])
    );
    selected.value = tabs.value[0].key;
  } catch (failure) {
    if (own !== generation || context !== authority.value) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? 'DENIED'
      : 'ERROR';
    capabilities.value = null;
    selected.value = '';
  } finally {
    if (own === generation && context === authority.value)
      loading.value = false;
  }
}
watch([authority, allowed], clear, { flush: 'sync' });
onBeforeUnmount(clear);
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 p-3 text-n-slate-12"
    data-recording-customer-records
  >
    <header class="flex min-w-0 flex-wrap items-center justify-between gap-2">
      <h3 class="font-semibold">
        {{ t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.TITLE') }}
      </h3>
      <Button
        v-if="allowed"
        data-load-customer-records
        :disabled="loading"
        :is-loading="loading"
        :label="t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.LOAD')"
        @click="open"
      />
    </header>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.SCOPE') }}
    </p>
    <p v-if="!allowed" role="status">
      {{ t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.DENIED') }}
    </p>
    <p v-else-if="loading" role="status">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p v-else-if="error" role="alert" class="break-words text-n-ruby-11">
      {{
        error === 'DENIED'
          ? t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.DENIED')
          : t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.ERROR')
      }}
    </p>
    <template v-else-if="capabilities && allowed">
      <nav
        class="flex min-w-0 flex-wrap gap-2"
        :aria-label="t('JRC_CONTACT_CENTER.CUSTOMER_RECORDS.TITLE')"
      >
        <button
          v-for="tab in tabs"
          :key="tab.key"
          type="button"
          :data-customer-records-tab="tab.key"
          class="rounded-lg border px-3 py-2 text-sm"
          :class="
            selected === tab.key
              ? 'border-n-blue-8 bg-n-blue-3 text-n-blue-12'
              : 'border-n-weak'
          "
          :aria-current="selected === tab.key ? 'page' : undefined"
          @click="selected = tab.key"
        >
          {{ tab.label }}
        </button>
      </nav>
      <div
        class="min-w-0 [&_article]:min-w-0 [&_article>div]:min-w-0 [&_a]:break-words"
        data-native-customer-records
      >
        <TimelinePanel
          v-if="selected === 'history'"
          :key="`${authority}-history`"
          :resource-id="String(contactId)"
          resource-type="contacts"
        />
        <RecordsPanel
          v-else-if="tabs.some(tab => tab.key === selected)"
          :key="`${authority}-${selected}`"
          :contact-id="String(contactId)"
          :kind="selected"
        />
      </div>
    </template>
  </section>
</template>
