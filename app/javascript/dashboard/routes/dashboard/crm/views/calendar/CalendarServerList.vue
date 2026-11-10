<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { activitiesAPI } from 'dashboard/api/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import { createCalendarPageState } from '../../utils/calendarPageState';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  identity: { type: String, required: true },
  startsOn: { type: String, required: true },
  endsBefore: { type: String, required: true },
  filters: { type: Object, required: true },
  customerSegmentId: { type: [String, Number], default: '' },
  revision: { type: Number, default: 0 },
});
const emit = defineEmits(['edit', 'owners']);
const { t } = useI18n();
const state = ref({
  rows: [],
  owners: [],
  meta: null,
  loading: false,
  error: null,
});
const completing = ref(null);
const completionError = ref('');
let operationGeneration = 0;
let disposed = false;
const query = computed(() => ({
  accountId: props.accountId,
  identity: props.identity,
  startsOn: props.startsOn,
  endsBefore: props.endsBefore,
  customerSegmentId: props.customerSegmentId,
  filters: { ...props.filters },
}));
const reader = createCalendarPageState({
  fetchPage: (accountId, params, options) =>
    activitiesAPI.calendarPageInAccount(accountId, params, options),
  currentContext: () => props.identity,
  publish: value => {
    state.value = value;
    emit('owners', value.owners);
  },
});
const load = (page = 1) => reader.load(query.value, page);
const canEdit = row =>
  !row.completed_at && !['completed', 'cancelled'].includes(row.status);
const complete = async row => {
  if (disposed || completing.value || state.value.loading || !canEdit(row))
    return;
  const identity = props.identity;
  const accountId = props.accountId;
  operationGeneration += 1;
  const generation = operationGeneration;
  completing.value = row.id;
  completionError.value = '';
  const active = () =>
    !disposed &&
    generation === operationGeneration &&
    identity === props.identity;
  try {
    await activitiesAPI.completeInAccount(accountId, row.id);
    if (active()) await load(state.value.meta?.page || 1);
  } catch (error) {
    if (!active()) return;
    if ([401, 403, 404].includes(error.response?.status)) reader.clear();
    completionError.value = t('CRM.CALENDAR_ACTIONS.COMPLETE_FAILED');
  } finally {
    if (active()) completing.value = null;
  }
};
// The server serializes due_at_local in the account zone. Do not regroup by the
// browser's zone: a late appointment must stay on its account calendar date.
const groups = computed(() => {
  const result = new Map();
  state.value.rows.forEach(row => {
    const local = row.due_at_local;
    const key =
      typeof local === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(local)
        ? local.slice(0, 10)
        : '';
    if (!result.has(key)) result.set(key, []);
    result.get(key).push(row);
  });
  return [...result.entries()].map(([day, rows]) => ({ day, rows }));
});
watch(
  [query, () => props.revision],
  () => {
    operationGeneration += 1;
    completing.value = null;
    completionError.value = '';
    load();
  },
  { deep: true, immediate: true, flush: 'sync' }
);
onBeforeUnmount(() => {
  disposed = true;
  operationGeneration += 1;
  reader.dispose();
});
</script>

<template>
  <div data-testid="calendar-server-list" class="min-w-0">
    <p v-if="completionError" role="alert" class="p-4 text-sm text-n-ruby-11">
      {{ completionError }}
    </p>
    <p v-if="state.loading" role="status" class="p-6 text-sm text-n-slate-11">
      {{ t('CRM.CALENDAR_SERVER.LOADING') }}
    </p>
    <div
      v-else-if="state.error"
      role="alert"
      class="space-y-3 p-6 text-sm text-n-ruby-11"
    >
      <p>
        {{
          t(
            state.error === 'ACCESS_DENIED'
              ? 'CRM.CALENDAR_SERVER.ACCESS_DENIED'
              : 'CRM.CALENDAR_SERVER.LOAD_FAILED'
          )
        }}
      </p>
      <Button
        :label="t('CRM.CALENDAR_SERVER.RETRY')"
        variant="outline"
        @click="load()"
      />
    </div>
    <p
      v-else-if="!state.rows.length"
      role="status"
      class="p-6 text-sm text-n-slate-11"
    >
      {{ t('CRM.CALENDAR_ACTIONS.EMPTY_PERIOD') }}
    </p>
    <div v-else data-testid="calendar-period" class="divide-y divide-n-weak">
      <section
        v-for="group in groups"
        :key="group.day"
        :data-calendar-day="group.day"
        class="p-4"
      >
        <h3 class="mb-3 text-sm font-semibold text-n-slate-12">
          {{ group.day || t('CRM.CALENDAR_SERVER.DATE_UNAVAILABLE') }}
        </h3>
        <article
          v-for="row in group.rows"
          :key="row.id"
          class="mb-2 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak p-3"
        >
          <div class="min-w-0">
            <p class="m-0 break-words text-sm font-semibold text-n-slate-12">
              {{ row.title }}
            </p>
            <p class="m-0 text-xs text-n-slate-11">{{ row.due_at_display }}</p>
          </div>
          <div v-if="canEdit(row)" class="flex gap-2">
            <Button
              :label="t('CRM.ACTIVITY_EDIT.TITLE')"
              variant="outline"
              :disabled="!!completing"
              @click="emit('edit', row.id)"
            />
            <Button
              :label="t('CRM.CALENDAR_SERVER.COMPLETE')"
              :disabled="!!completing"
              @click="complete(row)"
            />
          </div>
        </article>
      </section>
    </div>
    <nav
      v-if="state.meta && !state.loading && !state.error"
      :aria-label="t('CRM.CALENDAR_ACTIONS.LIST_PAGES')"
      class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak p-3"
    >
      <p role="status" class="m-0 text-xs text-n-slate-11">
        {{ t('CRM.CALENDAR_ACTIONS.LIST_PAGE', state.meta) }}
      </p>
      <div class="flex gap-2">
        <Button
          data-testid="calendar-list-previous"
          variant="outline"
          :label="t('CRM.CALENDAR_ACTIONS.PREVIOUS_PAGE')"
          :disabled="state.meta.page <= 1 || !!completing"
          @click="load(state.meta.page - 1)"
        />
        <Button
          data-testid="calendar-list-next"
          variant="outline"
          :label="t('CRM.CALENDAR_ACTIONS.NEXT_PAGE')"
          :disabled="state.meta.page >= state.meta.pages || !!completing"
          @click="load(state.meta.page + 1)"
        />
      </div>
    </nav>
  </div>
</template>
