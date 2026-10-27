<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CustomerAPI from 'dashboard/api/jrcCustomers';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { WORKSPACE_APPEARANCE } from './inboxAppearance';

const props = defineProps({
  accountId: { type: Number, required: true },
  contactId: { type: Number, required: true },
  contact: { type: Object, default: null },
  enabled: { type: Boolean, default: false },
  crm: { type: Object, default: null },
  crmEnabled: { type: Boolean, default: false },
  conversationId: { type: Number, default: null },
});
const { t, tm, rt } = useI18n();
const overview = ref(null);
const loading = ref(false);
const failed = ref(false);
const retry = ref(0);
const overviewLabels = computed(() =>
  tm('JRC_CONTACT_CENTER.INBOX_360.MODULE_OVERVIEW')
);
const text = key => rt(overviewLabels.value[key]);

watch(
  [() => props.accountId, () => props.contactId, () => props.enabled, retry],
  async (_, __, cleanup) => {
    let current = true;
    cleanup(() => {
      current = false;
    });
    overview.value = null;
    failed.value = false;
    loading.value = false;
    if (
      !props.enabled ||
      Number(CustomerAPI.accountIdFromRoute) !== props.accountId
    )
      return;
    loading.value = true;
    try {
      const { data } = await CustomerAPI.contactOverview(props.contactId);
      if (current) overview.value = data;
    } catch {
      if (current) failed.value = true;
    } finally {
      if (current) loading.value = false;
    }
  },
  { immediate: true }
);

const metrics = computed(() => overview.value || {});
const capabilities = computed(() => metrics.value.capabilities || {});
const cards = computed(() => [
  {
    key: 'CONVERSATIONS',
    capability: 'conversations',
    icon: 'i-lucide-messages-square',
    tone: 'CONVERSATION',
    values: ['conversations_open'],
  },
  {
    key: 'CRM',
    capability: 'crm',
    icon: 'i-lucide-chart-no-axes-combined',
    tone: 'ORDERS',
    values: ['opportunities', 'leads', 'proposals'],
  },
  {
    key: 'SERVICE_DESK',
    capability: 'service_desk',
    icon: 'i-lucide-headset',
    tone: 'CASES',
    values: ['tickets_open', 'sla_breached'],
  },
  {
    key: 'PROJECTS',
    capability: 'projects',
    icon: 'i-lucide-folders',
    tone: 'TASKS',
    values: ['projects_active'],
  },
  {
    key: 'CONTRACTS',
    capability: 'contracts',
    icon: 'i-lucide-file-check',
    tone: 'CUSTOMER_DATA',
    values: ['contracts_active'],
  },
  {
    key: 'ACTIVITIES',
    capability: 'crm',
    icon: 'i-lucide-calendar-check',
    tone: 'HISTORY',
    values: ['pending_activities'],
  },
  {
    key: 'CAMPAIGNS',
    capability: 'campaigns',
    icon: 'i-lucide-megaphone',
    tone: 'SCRIPT',
    values: ['campaigns_sent'],
  },
  {
    key: 'VOICE',
    capability: 'calls',
    icon: 'i-lucide-phone-call',
    tone: 'CONVERSATION',
    values: ['calls'],
  },
  {
    key: 'RELATIONSHIP',
    capability: 'relationship',
    icon: 'i-lucide-heart-handshake',
    tone: 'OVERVIEW',
    values: [],
  },
]);
const route360 = computed(() => ({
  name: 'crm_customer_360',
  params: { accountId: props.accountId, customerId: props.contactId },
  query: props.conversationId ? { conversationId: props.conversationId } : {},
}));
</script>

<template>
  <section
    class="min-h-0 flex-1 overflow-y-auto bg-n-slate-2 p-4"
    data-testid="inbox-customer-overview"
  >
    <header
      class="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-teal-6 bg-n-teal-2 p-4"
    >
      <div>
        <h3
          class="m-0 flex items-center gap-2 text-base font-semibold text-n-teal-11"
        >
          <span class="i-lucide-layout-dashboard size-5" />
          {{ t('JRC_CONTACT_CENTER.INBOX_360.OVERVIEW') }}
        </h3>
        <p
          v-if="contact"
          class="mb-0 mt-2 text-sm font-semibold text-n-slate-12"
        >
          {{ contact.name }}
        </p>
        <p class="mb-0 mt-1 text-xs leading-5 text-n-slate-11">
          {{ text('HELP') }}
        </p>
      </div>
      <RouterLink
        v-if="crmEnabled && crm"
        :to="route360"
        class="inline-flex items-center gap-2 rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-xs font-semibold text-n-blue-11"
      >
        <span class="i-lucide-external-link size-4" />{{ text('OPEN_CRM') }}
      </RouterLink>
    </header>
    <div v-if="loading" class="flex justify-center p-6"><Spinner /></div>
    <div
      v-else-if="failed"
      role="alert"
      class="rounded-xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      <button
        type="button"
        class="ml-2 rounded-lg border border-n-ruby-6 px-3 py-2 font-semibold"
        @click="retry += 1"
      >
        {{ t('CHAT_LIST.RETRY') }}
      </button>
    </div>
    <p
      v-else-if="!overview"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-5 text-sm text-n-slate-11"
    >
      {{ text('UNAVAILABLE') }}
    </p>
    <div v-else class="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
      <article
        v-for="card in cards"
        :key="card.key"
        class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-sm"
        :data-module="card.capability"
      >
        <h4
          class="m-0 flex items-center gap-2 border-b px-4 py-3 text-sm font-semibold"
          :class="WORKSPACE_APPEARANCE[card.tone].idle"
        >
          <span :class="card.icon" class="size-4 shrink-0" />{{
            text(card.key)
          }}
        </h4>
        <dl
          v-if="capabilities[card.capability] === true && card.values.length"
          class="m-0 space-y-3 p-4"
        >
          <div
            v-for="key in card.values"
            :key="key"
            class="flex items-center justify-between gap-3"
          >
            <dt class="text-xs text-n-slate-11">{{ text(key) }}</dt>
            <dd class="m-0 text-xl font-bold tabular-nums text-n-slate-12">
              {{ metrics[key] ?? '—' }}
            </dd>
          </div>
        </dl>
        <p v-else class="m-0 p-4 text-xs leading-5 text-n-slate-11">
          {{
            text(
              capabilities[card.capability] === true ? 'LINKED' : 'UNAVAILABLE'
            )
          }}
        </p>
      </article>
    </div>
  </section>
</template>
