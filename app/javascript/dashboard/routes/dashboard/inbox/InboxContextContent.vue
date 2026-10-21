<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  inbox360Labels,
  orderStateLabels,
  casePriorityLabels,
  caseStateLabels,
} from './inboxPresentation';
const props = defineProps({
  tab: { type: String, required: true },
  scriptReply: { type: String, default: '' },
  crm: { type: Object, default: null },
  contact: { type: Object, default: null },
  company: { type: Object, default: null },
  cases: { type: Array, default: () => [] },
});
const emit = defineEmits(['replies']);
const { t, locale } = useI18n();
const labels = computed(() => inbox360Labels(t));
const priorityLabels = computed(() => casePriorityLabels(t));
const caseLabels = computed(() => caseStateLabels(t));
const orderLabels = computed(() => orderStateLabels(t));
const formatDateTime = value => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(date);
};
const timeline = computed(() =>
  (props.crm?.timeline || []).filter(
    item => props.tab !== 'TASKS' || item.status === 'scheduled'
  )
);
</script>

<template>
  <div class="min-h-0 flex-1 overflow-y-auto p-4">
    <template v-if="tab === 'SCRIPT'">
      <p
        v-if="scriptReply"
        class="whitespace-pre-wrap rounded-lg border border-n-blue-6 bg-n-blue-2 p-4 text-sm leading-6 text-n-slate-12"
      >
        {{ scriptReply }}
      </p>
      <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
        <span class="i-lucide-book-open mb-3 block size-6 text-n-brand" />
        <h3 class="text-base font-semibold">
          {{ t('JRC_CONTACT_CENTER.INBOX_360.SCRIPT') }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-10">
          {{ t('JRC_CONTACT_CENTER.INBOX_360.SCRIPT_HINT') }}
        </p>
        <button
          type="button"
          class="rounded-lg bg-n-brand px-4 py-2 text-xs font-semibold text-white"
          @click="emit('replies')"
        >
          {{ t('JRC_CONTACT_CENTER.INBOX_360.REPLIES') }}
        </button>
      </div>
    </template>
    <dl
      v-else-if="tab === 'CUSTOMER_DATA' && contact"
      class="space-y-4 rounded-lg border border-n-weak bg-n-solid-1 p-4 text-sm"
    >
      <div
        v-for="(value, key) in {
          CUSTOMER: company?.name || contact.name,
          CONTACTS: contact.name,
          PHONE: contact.phone_number,
          EMAIL: contact.email,
          CUSTOMER_CODE: company?.customer_code,
          CLASSIFICATION: company?.segment,
        }"
        :key="key"
      >
        <template v-if="value">
          <dt class="mb-1 text-xs text-n-slate-10">
            {{ labels[key] }}
          </dt>
          <dd class="m-0 break-words font-medium text-n-slate-12">
            {{ value }}
          </dd>
        </template>
      </div>
    </dl>
    <div
      v-else-if="tab === 'ORDERS' && crm?.orders?.length"
      class="overflow-x-auto rounded-lg border border-n-weak bg-n-solid-1"
    >
      <p class="m-0 border-b border-n-weak p-3 text-xs text-n-slate-10">
        {{ t('JRC_CONTACT_CENTER.INBOX_360.CRM_SOURCE') }}
      </p>
      <table class="w-full text-left text-xs">
        <thead class="bg-n-alpha-2 text-n-slate-10">
          <tr>
            <th class="p-3">
              {{ t('JRC_CONTACT_CENTER.INBOX_360.ORDER') }}
            </th>
            <th class="p-3">
              {{ t('JRC_CONTACT_CENTER.INBOX_360.SUMMARY') }}
            </th>
            <th class="p-3">
              {{ t('JRC_CONTACT_CENTER.INBOX_360.STATUS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="order in crm.orders"
            :key="order.id"
            class="border-t border-n-weak"
          >
            <td class="p-3 font-semibold">
              {{ order.number }}
            </td>
            <td class="p-3">
              {{ order.deal?.title }}
            </td>
            <td class="p-3">
              <span class="rounded-full bg-n-blue-3 px-2 py-1 text-n-blue-11">
                {{ orderLabels[order.status] }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-else-if="tab === 'CASES' && cases.length" class="space-y-3">
      <article
        v-for="item in cases"
        :key="item.id"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-4"
      >
        <header class="flex flex-wrap justify-between gap-2 text-xs">
          <b>
            {{ item.protocol }}
          </b>
          <span class="rounded-full bg-n-amber-3 px-2 py-0.5 text-n-amber-11">
            {{
              t('JRC_CONTACT_CENTER.COMMON.CODE_DETAIL', {
                code: priorityLabels[item.priority],
                detail: caseLabels[item.status],
              })
            }}
          </span>
        </header>
        <p class="mb-1 mt-3 text-sm font-medium">
          {{ item.summary }}
        </p>
        <p class="mb-0 text-xs text-n-slate-10">
          {{ item.category }}
        </p>
      </article>
    </div>
    <ol
      v-else-if="['HISTORY', 'TASKS'].includes(tab) && timeline.length"
      class="m-0 list-none space-y-4 border-l-2 border-n-blue-5 pl-4"
    >
      <li
        v-for="item in timeline"
        :key="item.id"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
      >
        <p class="m-0 text-sm font-semibold">
          {{ item.title }}
        </p>
        <p class="mb-0 mt-2 text-xs leading-5 text-n-slate-10">
          {{ item.description }}
        </p>
        <p class="mb-0 mt-2 text-[11px] text-n-brand">
          {{ item.user }} {{ formatDateTime(item.due_at || item.created_at) }}
        </p>
      </li>
    </ol>
    <div
      v-else
      class="grid min-h-48 place-content-center rounded-lg border border-dashed border-n-weak px-6 text-center text-sm leading-6 text-n-slate-10"
    >
      <span class="i-lucide-files mx-auto mb-3 block size-7 text-n-slate-9" />
      {{
        labels[
          tab === 'ORDERS'
            ? 'ORDERS_EMPTY'
            : tab === 'CASES'
              ? 'CASES_EMPTY'
              : 'DETAILS_EMPTY'
        ]
      }}
    </div>
  </div>
</template>
