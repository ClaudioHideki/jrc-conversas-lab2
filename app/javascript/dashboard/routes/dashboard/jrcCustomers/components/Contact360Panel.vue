<script setup>
import {
  computed,
  defineAsyncComponent,
  onBeforeUnmount,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import CompanyContactHistoryPanel from './CompanyContactHistoryPanel.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useCustomerMaster } from '../useCustomerMaster';
import MasterContactPanel from './MasterContactPanel.vue';
import RecordsPanel from './RecordsPanel.vue';
import TimelinePanel from './TimelinePanel.vue';
import { T, errorMessage } from '../copy';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
});
const emit = defineEmits(['updated', 'denied']);
const CompanyDetailsDialog = defineAsyncComponent(
  () => import('./CompanyDetailsDialog.vue')
);
const { t } = useI18n();
const { accountId, identity, date } = useCustomerMaster();
const { checkPermissions } = usePolicy();
const contact = ref(null);
const overview = ref(null);
const busy = ref(false);
const error = ref('');
const tab = ref('overview');
const historySection = ref('timeline');
const commercialKind = ref('leads');
const companyDialog = ref(false);
const composer = ref(null);
let generation = 0;
let controller;
const canConverse = computed(() =>
  checkPermissions([
    'administrator',
    'conversation_manage',
    'conversation_unassigned_manage',
    'conversation_participating_manage',
  ])
);
const tabs = computed(() => [
  { key: 'overview', label: t('CRM.CONTACT_MASTER_360.OVERVIEW') },
  { key: 'company', label: t('CRM.CONTACT_MASTER_360.COMPANY') },
  { key: 'conversations', label: t('CRM.CONTACT_MASTER_360.CONVERSATIONS') },
  ...(overview.value?.capabilities?.crm
    ? [
        { key: 'crm', label: t('CRM.CONTACT_MASTER_360.CRM') },
        { key: 'activities', label: t('CRM.CONTACT_MASTER_360.ACTIVITIES') },
      ]
    : []),
  { key: 'history', label: t('CRM.CONTACT_MASTER_360.HISTORY') },
]);
const commercialKinds = ['leads', 'deals', 'proposals', 'orders', 'contracts'];
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  contact.value = null;
  overview.value = null;
  error.value = '';
  busy.value = true;
  const options = { accountId: accountId.value, signal: controller.signal };
  try {
    const [record, summary] = await Promise.all([
      API.contact(props.contactId, options),
      API.contactOverview(props.contactId, options),
    ]);
    if (version !== generation) return false;
    contact.value = record.data.payload;
    overview.value = summary.data;
    if (!tabs.value.some(item => item.key === tab.value))
      tab.value = 'overview';
    return true;
  } catch (failure) {
    if (version !== generation) return false;
    error.value = errorMessage(failure);
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
    return false;
  } finally {
    if (version === generation) busy.value = false;
  }
};
const updated = async () => {
  const context = identity.value;
  if ((await load()) && context === identity.value) emit('updated');
};
watch(
  [identity, () => props.contactId],
  () => {
    companyDialog.value = false;
    tab.value = 'overview';
    commercialKind.value = 'leads';
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  contact.value = null;
  overview.value = null;
});
</script>

<template>
  <section class="space-y-4 text-n-slate-12">
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 text-n-ruby-12"
    >
      {{ error }}
    </p>
    <template v-if="contact">
      <header
        class="space-y-3 rounded-xl border border-n-blue-6 bg-n-blue-3 p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="min-w-0 break-words text-xl font-bold">
            {{ contact.name }}
          </h2>
          <span class="rounded-lg bg-n-solid-2 px-3 py-1 text-sm">{{
            contact.registration_status === 'registered'
              ? T.registered
              : T.provisional
          }}</span>
        </div>
        <p class="break-words text-sm">
          {{ `${contact.email || ''} / ${contact.phone_number || ''}` }}
        </p>
        <button
          v-if="contact.company_id"
          type="button"
          class="text-left text-sm font-semibold text-n-blue-11 underline"
          @click="companyDialog = true"
        >
          {{ contact.company_name }}
        </button>
        <p
          v-else
          class="text-sm text-n-amber-text"
        >
          {{ T.noCompany }}
        </p>
        <div
          v-if="canConverse"
          class="flex flex-wrap gap-2"
        >
          <ComposeConversation
            ref="composer"
            :contact-id="String(contact.id)"
            native-dialog
          >
            <template #trigger>
              <Button
                :label="t('CRM.CONTACT_MASTER_360.NEW_CONVERSATION')"
                size="sm"
                @click="composer.selectContact(contact)"
              />
            </template>
          </ComposeConversation>
          <VoiceCallButton
            :contact-id="contact.id"
            :phone="contact.phone_number || ''"
            :label="t('CONTACT_PANEL.CALL')"
          />
        </div>
      </header>
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="t('CRM.CONTACT_MASTER_360.TITLE')"
      >
        <button
          v-for="item in tabs"
          :key="item.key"
          type="button"
          class="rounded-lg border px-3 py-2 text-sm font-semibold"
          :class="
            tab === item.key
              ? 'border-n-blue-8 bg-n-blue-9 text-white'
              : 'border-n-teal-6 bg-n-teal-3 text-n-teal-12'
          "
          :aria-current="tab === item.key ? 'page' : undefined"
          @click="tab = item.key"
        >
          {{ item.label }}
        </button>
      </nav>
      <section
        v-if="tab === 'overview'"
        class="space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      >
        <div class="grid gap-3 sm:grid-cols-3">
          <article class="rounded-xl bg-n-blue-3 p-4">
            <p class="text-sm">{{ T.openConversations }}</p>
            <b class="text-xl">{{ overview.conversations_open }}</b>
          </article>
          <article
            v-if="overview.capabilities.crm"
            class="rounded-xl bg-n-teal-3 p-4"
          >
            <p class="text-sm">{{ T.opportunities }}</p>
            <b class="text-xl">{{ overview.opportunities }}</b>
          </article>
          <article
            v-if="overview.capabilities.crm"
            class="rounded-xl bg-n-amber-3 p-4"
          >
            <p class="text-sm">{{ T.pendingActivities }}</p>
            <b class="text-xl">{{ overview.pending_activities }}</b>
          </article>
        </div>
        <dl class="grid gap-4 text-sm sm:grid-cols-2">
          <div>
            <dt class="text-n-slate-10">{{ T.lastInteraction }}</dt>
            <dd>{{ date(overview.last_interaction_at) }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-10">{{ T.nextActivity }}</dt>
            <dd>{{ overview.next_activity?.title || T.noNextActivity }}</dd>
          </div>
        </dl>
        <p class="text-xs text-n-slate-10">{{ T.permissionsHelp }}</p>
      </section>
      <MasterContactPanel
        v-else-if="tab === 'company'"
        :key="identity"
        :contact-id="contact.id"
        expanded-by-default
        @updated="updated"
        @denied="emit('denied')"
      />
      <RecordsPanel
        v-else-if="tab === 'conversations' || tab === 'activities'"
        :key="`${identity}:${contact.id}:${tab}`"
        :contact-id="contact.id"
        :kind="tab"
      />
      <section
        v-else-if="tab === 'crm'"
        class="space-y-4"
      >
        <nav
          class="flex flex-wrap gap-2"
          :aria-label="t('CRM.CONTACT_MASTER_360.CRM')"
        >
          <button
            v-for="kind in commercialKinds"
            :key="kind"
            type="button"
            class="rounded-lg border px-3 py-2 text-sm"
            :class="
              commercialKind === kind
                ? 'border-n-amber-8 bg-n-amber-3 text-n-amber-12'
                : 'border-n-weak'
            "
            @click="commercialKind = kind"
          >
            {{ T[kind] }}
          </button>
        </nav>
        <RecordsPanel
          :key="`${identity}:${contact.id}:${commercialKind}`"
          :contact-id="contact.id"
          :kind="commercialKind"
        />
      </section>
      <section
        v-else-if="tab === 'history'"
        class="space-y-4"
      >
        <nav
          class="flex flex-wrap gap-2"
          :aria-label="t('CRM.CONTACT_MASTER_360.HISTORY')"
        >
          <button
            v-for="section in ['timeline', 'links']"
            :key="section"
            type="button"
            class="rounded-lg border px-3 py-2 text-sm"
            :class="
              historySection === section
                ? 'border-n-teal-8 bg-n-teal-3 text-n-teal-12'
                : 'border-n-weak'
            "
            @click="historySection = section"
          >
            {{
              section === 'timeline'
                ? t('CRM.COMPANY_CONTACT_CONTEXT.TIMELINE')
                : t('CRM.COMPANY_CONTACT_CONTEXT.HISTORY')
            }}
          </button>
        </nav>
        <TimelinePanel
          v-if="historySection === 'timeline'"
          :key="`${identity}:${contact.id}`"
          :resource-id="contact.id"
          resource-type="contacts"
        />
        <CompanyContactHistoryPanel
          v-else
          :key="`${identity}:${contact.id}`"
          :contact-id="contact.id"
        />
      </section>
      <CompanyDetailsDialog
        v-if="companyDialog"
        :key="identity"
        :company-id="contact.company_id"
        @close="companyDialog = false"
        @updated="updated"
      />
    </template>
  </section>
</template>
