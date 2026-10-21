<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  inbox360Labels,
  orderStateLabels,
  casePriorityLabels,
} from './inboxPresentation';

const props = defineProps({
  accountId: { type: Number, required: true },
  contact: { type: Object, default: null },
  company: { type: Object, default: null },
  crm: { type: Object, default: null },
  addresses: { type: Array, default: () => [] },
  cases: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  failed: { type: Boolean, default: false },
  unavailable: { type: Boolean, default: false },
  interaction: { type: Object, default: () => ({}) },
  crmEnabled: { type: Boolean, default: false },
  closable: { type: Boolean, default: false },
  whatsappTarget: { type: Object, default: null },
});
const emit = defineEmits(['showTab', 'more', 'close']);
const { t, locale } = useI18n();
const labels = computed(() => inbox360Labels(t));
const priorityLabels = computed(() => casePriorityLabels(t));
const orderLabels = computed(() => orderStateLabels(t));
const formatDate = value =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    dateStyle: 'short',
  }).format(new Date(value));
const tab = ref('SUMMARY');
const name = computed(
  () =>
    props.company?.trade_name ||
    props.company?.name ||
    props.contact?.name ||
    ''
);
const initials = computed(() =>
  name.value
    .split(' ')
    .slice(0, 2)
    .map(word => word.charAt(0))
    .join('')
    .toUpperCase()
);
const address = computed(() => props.addresses[0]);
const route360 = computed(() => ({
  name: 'crm_customer_360',
  params: { accountId: props.accountId, customerId: props.contact?.id },
  query: props.interaction,
}));
const openCases = computed(() =>
  props.cases.filter(
    item => !['closed', 'resolved', 'canceled'].includes(item.status)
  )
);
const details = computed(() =>
  [
    ['OWNER', props.company?.owner_name],
    ['CLASSIFICATION', props.company?.segment],
    [
      'LAST_INTERACTION',
      props.crm?.profile?.last_activity_at
        ? formatDate(props.crm.profile.last_activity_at)
        : null,
    ],
  ].filter(([, value]) => value)
);
</script>

<template>
  <div
    class="flex min-h-0 flex-col gap-2.5 text-n-slate-12"
    data-testid="customer-360"
  >
    <section
      class="overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
    >
      <header
        class="flex items-center justify-between gap-2 border-b border-n-weak px-3 py-3"
      >
        <h2 class="m-0 flex-1 text-sm font-semibold">
          {{ t('JRC_CONTACT_CENTER.INBOX_360.CUSTOMER') }}
        </h2>
        <RouterLink
          v-if="contact && crmEnabled"
          :to="route360"
          class="inline-flex items-center gap-1 rounded-md border border-n-weak px-2 py-1 text-[11px] font-semibold text-n-brand"
        >
          <span class="i-lucide-orbit size-3" />
          {{ t('JRC_CONTACT_CENTER.INBOX_360.VIEW_360') }}
        </RouterLink>
        <button
          v-if="closable"
          type="button"
          class="grid size-7 shrink-0 place-items-center rounded-md text-n-slate-10 hover:bg-n-alpha-2"
          :aria-label="t('DIALOG.BUTTONS.CANCEL')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>
      <div
        v-if="loading"
        class="m-3 h-40 animate-pulse rounded-lg bg-n-alpha-2"
      />
      <p v-else-if="failed" role="alert" class="p-4 text-xs text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>
      <p
        v-else-if="!contact"
        class="px-4 py-8 text-center text-xs leading-5 text-n-slate-10"
      >
        {{ t('JRC_CONTACT_CENTER.INBOX_360.NO_CUSTOMER') }}
      </p>
      <template v-else>
        <div class="flex gap-2.5 p-3">
          <span
            class="grid size-11 shrink-0 place-items-center rounded-full bg-n-blue-3 text-base font-semibold text-n-blue-11"
          >
            {{ initials }}
          </span>
          <div class="min-w-0 flex-1">
            <h3 class="m-0 break-words text-sm font-semibold leading-5">
              {{ name }}
            </h3>
            <span
              v-if="company"
              class="mt-1 inline-block rounded-full px-2 py-0.5 text-[10px] font-medium"
              :class="
                company.active
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-alpha-2 text-n-slate-10'
              "
            >
              {{ company.active ? labels.ACTIVE : labels.INACTIVE }}
            </span>
            <p
              v-if="
                company?.tax_id || company?.customer_code || contact.identifier
              "
              class="mb-0 mt-1 break-all text-[11px] text-n-slate-10"
            >
              {{
                company?.tax_id || company?.customer_code || contact.identifier
              }}
            </p>
            <p
              v-if="address?.city || company?.city"
              class="mb-0 mt-1 text-[11px] text-n-slate-10"
            >
              <span class="i-lucide-map-pin mr-1 inline-block size-3" />
              {{ address?.city || company.city
              }}{{ address?.state ? ` / ${address.state}` : '' }}
            </p>
            <div class="mt-2 flex gap-1.5">
              <RouterLink
                v-if="whatsappTarget"
                :to="whatsappTarget"
                class="grid size-7 place-items-center rounded-md border border-n-weak bg-n-teal-2 text-n-teal-11"
                :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.WHATSAPP')"
              >
                <span class="i-ri-whatsapp-fill size-4" />
              </RouterLink>
              <a
                v-if="contact.phone_number"
                :href="`tel:${contact.phone_number}`"
                class="grid size-7 place-items-center rounded-md border border-n-weak bg-n-blue-2 text-n-brand"
                :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.PHONE')"
              >
                <span class="i-lucide-phone size-4" />
              </a>
              <a
                v-if="contact.email"
                :href="`mailto:${contact.email}`"
                class="grid size-7 place-items-center rounded-md border border-n-weak bg-n-blue-2 text-n-brand"
                :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.EMAIL')"
              >
                <span class="i-lucide-mail size-4" />
              </a>
              <button
                type="button"
                class="grid size-7 place-items-center rounded-md border border-n-weak text-n-slate-11"
                :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.MORE')"
                @click="emit('more')"
              >
                <span class="i-lucide-ellipsis size-4" />
              </button>
            </div>
          </div>
        </div>
        <nav
          class="flex border-y border-n-weak"
          :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.CUSTOMER')"
        >
          <button
            v-for="key in ['SUMMARY', 'CONTACTS', 'ADDRESS', 'FINANCE']"
            :key="key"
            type="button"
            class="min-w-0 flex-1 border-b-2 px-1 py-2 text-[10px] font-medium"
            :class="
              tab === key
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-10'
            "
            :aria-pressed="tab === key"
            @click="tab = key"
          >
            {{ labels[key] }}
          </button>
        </nav>
        <div class="min-h-20 p-3 text-[11px]">
          <dl
            v-if="tab === 'SUMMARY' && details.length"
            class="m-0 space-y-2.5"
          >
            <div
              v-for="[key, value] in details"
              :key="key"
              class="grid grid-cols-[.9fr_1.2fr] gap-2"
            >
              <dt class="text-n-slate-10">
                {{ labels[key] }}
              </dt>
              <dd class="m-0 break-words font-medium">
                {{ value }}
              </dd>
            </div>
          </dl>
          <div v-else-if="tab === 'CONTACTS'" class="space-y-2 break-words">
            <p>
              {{ contact.name }}
            </p>
            <p v-if="contact.phone_number">
              {{ contact.phone_number }}
            </p>
            <p v-if="contact.email">
              {{ contact.email }}
            </p>
          </div>
          <div v-else-if="tab === 'ADDRESS' && address" class="space-y-1">
            <p>{{ address.street }} {{ address.number }}</p>
            <p>{{ address.district }} {{ address.city }} {{ address.state }}</p>
            <p>
              {{ address.postal_code }}
            </p>
          </div>
          <p v-else class="m-0 leading-5 text-n-slate-10">
            {{ labels[tab === 'FINANCE' ? 'FINANCE_EMPTY' : 'DETAILS_EMPTY'] }}
          </p>
        </div>
      </template>
    </section>
    <section class="rounded-lg border border-n-weak bg-n-solid-1 p-3">
      <header class="mb-3 flex items-center justify-between gap-2">
        <h3 class="m-0 text-xs font-semibold">
          {{ t('JRC_CONTACT_CENTER.INBOX_360.RECENT_ORDERS') }}
        </h3>
        <button
          type="button"
          class="text-[10px] text-n-brand"
          @click="emit('showTab', 'ORDERS')"
        >
          {{ t('JRC_CONTACT_CENTER.INBOX_360.VIEW_ALL') }}
        </button>
      </header>
      <p class="mb-2 text-[10px] text-n-slate-10">
        {{ t('JRC_CONTACT_CENTER.INBOX_360.CRM_SOURCE') }}
      </p>
      <div
        v-for="order in (crm?.orders || []).slice(0, 3)"
        :key="order.id"
        class="flex items-start justify-between gap-2 border-l-2 border-n-blue-6 py-2 pl-2 text-xs [&+div]:mt-2"
      >
        <div class="min-w-0">
          <p class="m-0 truncate font-semibold">
            {{ order.number }}
          </p>
          <p class="mb-0 mt-1 truncate text-[11px] text-n-slate-10">
            {{ order.deal?.title }}
          </p>
        </div>
        <span
          class="rounded-full bg-n-blue-3 px-2 py-0.5 text-[10px] text-n-blue-11"
        >
          {{ orderLabels[order.status] }}
        </span>
      </div>
      <p
        v-if="!crm?.orders?.length"
        class="m-0 py-3 text-xs leading-5 text-n-slate-10"
      >
        {{ t('JRC_CONTACT_CENTER.INBOX_360.ORDERS_EMPTY') }}
      </p>
    </section>
    <section class="rounded-lg border border-n-weak bg-n-solid-1 p-3">
      <header class="mb-3 flex items-center justify-between gap-2">
        <h3 class="m-0 text-xs font-semibold">
          {{ t('JRC_CONTACT_CENTER.INBOX_360.OPEN_CASES') }}
        </h3>
        <button
          type="button"
          class="text-[10px] text-n-brand"
          @click="emit('showTab', 'CASES')"
        >
          {{ t('JRC_CONTACT_CENTER.INBOX_360.VIEW_ALL') }}
        </button>
      </header>
      <div
        v-for="item in openCases.slice(0, 3)"
        :key="item.id"
        class="border-l-2 border-n-amber-7 py-2 pl-2 text-xs [&+div]:mt-2"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <b>
            {{ item.protocol }}
          </b>
          <span
            class="rounded-full bg-n-amber-3 px-2 py-0.5 text-[10px] text-n-amber-11"
          >
            {{ priorityLabels[item.priority] }}
          </span>
        </div>
        <p class="mb-0 mt-1 line-clamp-2 text-[11px] text-n-slate-10">
          {{ item.summary }}
        </p>
      </div>
      <p v-if="!openCases.length" class="m-0 py-3 text-xs text-n-slate-10">
        {{ t('JRC_CONTACT_CENTER.INBOX_360.CASES_EMPTY') }}
      </p>
    </section>
    <p
      v-if="unavailable"
      role="status"
      class="px-1 text-[10px] text-n-slate-10"
    >
      {{ t('JRC_CONTACT_CENTER.INBOX_360.PARTIAL_CONTEXT') }}
    </p>
  </div>
</template>
