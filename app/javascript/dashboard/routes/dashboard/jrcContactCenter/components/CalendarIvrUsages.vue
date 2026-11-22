<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useCalendarIvrUsages } from '../composables/useCalendarIvrUsages';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  calendarId: { type: String, required: true },
  unitId: { type: String, required: true },
  contextKey: { type: String, required: true },
  canManage: { type: Boolean, required: true },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const router = useRouter();
const dialog = ref(null);
const {
  items,
  meta,
  page,
  query,
  status,
  loading,
  error,
  open: begin,
  clear,
  load,
  filter,
  resetFilters,
} = useCalendarIvrUsages(
  {
    get accountId() {
      return props.accountId;
    },
    get unitId() {
      return props.unitId;
    },
    get calendarId() {
      return props.calendarId;
    },
    get contextKey() {
      return props.contextKey;
    },
    get canManage() {
      return props.canManage;
    },
  },
  {
    close: () => dialog.value?.close(),
    denied: () => emit('denied'),
  }
);
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.OPEN'),
  TITLE: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.TITLE'),
  LIMITS: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.LIMITS'),
  SEARCH: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.SEARCH'),
  STATUS: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.STATUS'),
  ALL: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.ALL'),
  DRAFT: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.DRAFT'),
  ARCHIVED: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.ARCHIVED'),
  FILTER: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.FILTER'),
  CLEAR: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.CLEAR'),
  LOADING: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.ERROR'),
  RETRY: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.RETRY'),
  EMPTY: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.EMPTY'),
  CHANGED: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.CHANGED'),
  CURRENT: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.CURRENT'),
  LIST: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.LIST'),
  CLOSE: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.CLOSE'),
  PAGINATION: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.NEXT'),
}));
const label = key => labels.value[key];
const referenceState = row =>
  label(row.calendar_changed ? 'CHANGED' : 'CURRENT');
const describe = row =>
  t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.IDENTITY', {
    id: row.draft_id,
    revision: row.draft_revision,
  });
const describeReference = row =>
  t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.REFERENCE', {
    id: row.node_id,
    sha: row.sha256,
  });
const describePage = () =>
  t('JRC_CONTACT_CENTER.CALENDAR_IVR_USAGES.TOTAL', {
    total: meta.value.total,
    page: page.value,
  });
const open = () => {
  if (begin()) dialog.value?.open();
};
const showList = row => {
  if (!props.canManage || !items.value.includes(row)) return;
  dialog.value?.close();
  router.push({
    path: `/app/accounts/${props.accountId}/contact-center/ura`,
    query: {
      ivr_unit: props.unitId,
      ivr_q: Array.from(row.name).slice(0, 100).join(''),
      ivr_page: '1',
    },
  });
};
</script>

<template>
  <button
    type="button"
    :disabled="!canManage"
    class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
    data-calendar-ivr-usages-open
    @click="open"
  >
    {{ label('OPEN') }}
  </button>
  <Dialog
    ref="dialog"
    contained
    :use-form="false"
    :title="label('TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="label('CLOSE')"
    @close="clear"
  >
    <div
      class="min-w-0 space-y-3 text-sm text-n-slate-12"
      data-calendar-ivr-usages
    >
      <p
        class="break-words rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-n-amber-11"
      >
        {{ label('LIMITS') }}
      </p>
      <form class="grid min-w-0 gap-3 sm:grid-cols-2" @submit.prevent="filter">
        <label class="grid min-w-0 gap-1">
          <span>{{ label('SEARCH') }}</span>
          <input
            v-model="query"
            maxlength="100"
            :disabled="loading"
            data-calendar-ivr-query
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
        <label class="grid min-w-0 gap-1">
          <span>{{ label('STATUS') }}</span>
          <select
            v-model="status"
            :disabled="loading"
            data-calendar-ivr-status
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="all">{{ label('ALL') }}</option>
            <option value="draft">{{ label('DRAFT') }}</option>
            <option value="archived">{{ label('ARCHIVED') }}</option>
          </select>
        </label>
        <div class="flex flex-wrap gap-3">
          <button
            type="submit"
            :disabled="loading"
            data-calendar-ivr-filter
            class="text-n-blue-11"
          >
            {{ label('FILTER') }}
          </button>
          <button
            type="button"
            :disabled="loading"
            data-calendar-ivr-clear
            class="text-n-blue-11"
            @click="resetFilters"
          >
            {{ label('CLEAR') }}
          </button>
        </div>
      </form>
      <p v-if="loading" role="status">{{ label('LOADING') }}</p>
      <div v-else-if="error" role="alert" class="space-y-2 text-n-ruby-11">
        <p>{{ label('ERROR') }}</p>
        <button
          type="button"
          data-calendar-ivr-retry
          class="text-n-blue-11"
          @click="load(page)"
        >
          {{ label('RETRY') }}
        </button>
      </div>
      <template v-else>
        <p v-if="!items.length" data-calendar-ivr-empty>{{ label('EMPTY') }}</p>
        <article
          v-for="row in items"
          :key="row.draft_id"
          :data-calendar-ivr-draft="row.draft_id"
          class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        >
          <h4 class="break-words font-semibold">{{ row.name }}</h4>
          <p>{{ describe(row) }}</p>
          <p>{{ label(row.status === 'archived' ? 'ARCHIVED' : 'DRAFT') }}</p>
          <ul class="min-w-0 space-y-2">
            <li
              v-for="reference in row.references"
              :key="reference.node_id"
              class="break-words"
            >
              <span class="block break-all">{{
                describeReference(reference)
              }}</span>
              <span
                :class="
                  reference.calendar_changed
                    ? 'text-n-amber-11'
                    : 'text-n-slate-11'
                "
              >
                {{ referenceState(reference) }}
              </span>
            </li>
          </ul>
          <button
            type="button"
            data-calendar-ivr-list
            class="text-n-blue-11 underline"
            @click="showList(row)"
          >
            {{ label('LIST') }}
          </button>
        </article>
      </template>
      <p v-if="!loading && !error" data-calendar-ivr-total>
        {{ describePage() }}
      </p>
      <nav
        v-if="meta.pages > 1 && !error"
        :aria-label="label('PAGINATION')"
        class="flex flex-wrap items-center gap-3"
      >
        <button
          type="button"
          :disabled="loading || page <= 1"
          data-calendar-ivr-previous
          @click="load(page - 1)"
        >
          {{ label('PREVIOUS') }}
        </button>
        <button
          type="button"
          :disabled="loading || page >= meta.pages"
          data-calendar-ivr-next
          @click="load(page + 1)"
        >
          {{ label('NEXT') }}
        </button>
      </nav>
    </div>
  </Dialog>
</template>
