<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskOperationalRules';
import ReportExportMenu from './ReportExportMenu.vue';
import ManagerialReportIndicators from './ManagerialReportIndicators.vue';
import { useOperationalScope } from '../composables/useOperationalScope';
import { assertEnvelope } from '../helpers/operationalRules.mjs';
import messages from '../helpers/managerialReportMessages';

const emit = defineEmits(['open']);
const { t, locale } = useI18n({ useScope: 'local', messages });
const unitId = ref('');
const units = ref([]);
const scope = useOperationalScope(
  unitId,
  context => context?.capabilities.managerial_reports?.index === true
);
const firstDate = '2026-01-01';
const defaults = () => ({
  from: firstDate,
  to: '',
  date_field: 'opened_at',
  group_by: 'month',
  origin: 'native',
  phase: '',
});
const filters = reactive(defaults());
const fields = [
  'status_id',
  'priority_id',
  'requester_id',
  'company_id',
  'establishment_company_id',
  'assignee_membership_id',
  'team_id',
  'queue_id',
  'service_id',
  'category_id',
  'subcategory_id',
  'ticket_type_id',
];
const origins = [
  'all',
  'native',
  'legacy_import',
  'manual',
  'portal',
  'unknown',
];
const phases = ['open', 'waiting', 'resolved', 'closed', 'cancelled'];
const dates = ['opened_at', 'created_at', 'updated_at'];
const groups = ['day', 'week', 'month', 'year'];
const columns = [
  'id',
  'title',
  'status',
  'phase',
  'priority',
  'requester',
  'company',
  'establishment',
  'unit',
  'assignee',
  'team',
  'queue',
  'service',
  'category',
  'subcategory',
  'ticket_type',
  'origin',
  ...dates,
];
const selected = ref({});
const field = ref('');
const term = ref('');
const optionId = ref('');
const options = ref([]);
const optionLoading = ref(false);
const hasMore = ref(false);
const unitLoading = ref(false);
const report = ref(null);
const busy = ref(false);
const error = ref('');
const lookupError = ref('');
const applied = computed(() => ({
  ...Object.fromEntries(Object.entries(filters).filter(([, value]) => value)),
  ...Object.fromEntries(
    Object.entries(selected.value).map(([key, value]) => [key, value.id])
  ),
}));
const dateFormat = computed(
  () =>
    new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
      dateStyle: 'short',
      timeStyle: 'short',
      timeZone: report.value?.timezone || 'UTC',
    })
);

watch(
  scope.identity,
  async (_, __, onCleanup) => {
    units.value = [];
    unitId.value = '';
    unitLoading.value = false;
    error.value = '';
    const context = scope.session.state.context;
    if (
      scope.session.state.status !== 'ready' ||
      !context?.capabilities.managerial_reports?.index
    )
      return;

    const controller = new AbortController();
    onCleanup(() => controller.abort());
    unitLoading.value = true;
    try {
      const payload = await API.managerialReportOptions(
        context.account_id,
        {},
        controller.signal
      );
      if (controller.signal.aborted) return;
      if (
        payload.contract_version !== 1 ||
        payload.account_id !== context.account_id ||
        !Array.isArray(payload.items) ||
        !payload.items.every(item =>
          context.units.some(unit => unit.id === item.id)
        )
      )
        throw new Error('Invalid report units');
      units.value = payload.items;
      unitId.value = units.value[0]?.id || '';
    } catch {
      if (!controller.signal.aborted) error.value = 'unavailable';
    } finally {
      if (!controller.signal.aborted) unitLoading.value = false;
    }
  },
  { immediate: true }
);

function clearDimension() {
  field.value = '';
  term.value = '';
  optionId.value = '';
}

watch(unitId, () => {
  selected.value = {};
  clearDimension();
});

watch([field, term, unitId, scope.allowed], (_, __, onCleanup) => {
  options.value = [];
  optionId.value = '';
  optionLoading.value = false;
  lookupError.value = '';
  hasMore.value = false;
  if (!field.value || !scope.allowed.value) return;

  const controller = new AbortController();
  const context = scope.session.state.context;
  const unit = unitId.value;
  const params = { unit_id: unit, field: field.value, q: term.value.trim() };
  optionLoading.value = true;
  const timer = setTimeout(async () => {
    try {
      const payload = assertEnvelope(
        await API.managerialReportOptions(
          context.account_id,
          params,
          controller.signal
        ),
        context,
        unit
      );
      if (controller.signal.aborted) return;
      options.value = payload.items;
      hasMore.value = payload.has_more;
    } catch {
      if (!controller.signal.aborted) lookupError.value = 'unavailable';
    } finally {
      if (!controller.signal.aborted) optionLoading.value = false;
    }
  }, 250);
  onCleanup(() => {
    clearTimeout(timer);
    controller.abort();
  });
});

function clear() {
  Object.assign(filters, defaults());
  selected.value = {};
  clearDimension();
}

function addFilter() {
  const option = options.value.find(row => row.id === optionId.value);
  if (
    optionId.value === 'unassigned' &&
    field.value === 'assignee_membership_id'
  ) {
    selected.value[field.value] = { id: optionId.value, name: t('unassigned') };
  } else if (option) {
    selected.value[field.value] = option;
  }
  clearDimension();
}

watch(
  [filters, selected, unitId, scope.identity],
  () => {
    scope.cancel();
    report.value = null;
    busy.value = false;
    error.value = '';
  },
  { deep: true, flush: 'sync' }
);

async function load(page = 1) {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;

  busy.value = true;
  error.value = '';
  try {
    const params = { ...applied.value, page };
    const payload = assertEnvelope(
      await API.managerialReport(
        lease.context.account_id,
        lease.unit,
        params,
        lease.signal
      ),
      lease.context,
      lease.unit
    );
    if (scope.live(lease)) report.value = payload;
  } catch (failure) {
    if (!scope.live(lease)) return;
    report.value = null;
    error.value = failure.response?.status === 422 ? 'invalid' : 'unavailable';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
}

function display(row, column) {
  if (column === 'origin') {
    const label = t(`origins.${row.origin}`);
    return row.origin === 'unknown' ? `${label} (${row.origin_code})` : label;
  }
  if (column === 'phase') return t(`phases.${row.phase}`);
  if (dates.includes(column))
    return dateFormat.value.format(new Date(row[column]));
  if (column === 'assignee' && !row.assignee) return t('unassigned');
  return row[column] || '—';
}

const inputClass =
  'rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 min-w-0';
</script>

<template>
  <section class="grid gap-4 text-n-slate-12">
    <p class="text-sm text-n-slate-11">{{ t('period') }}</p>
    <form class="grid gap-4" @submit.prevent="load()">
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <label class="grid gap-1 text-sm">
          {{ t('labels.unit') }}
          <select
            v-model="unitId"
            :class="inputClass"
            :disabled="unitLoading || !units.length"
            required
          >
            <option v-if="!units.length" value="">
              {{ t(unitLoading ? 'loading' : 'noUnits') }}
            </option>
            <option v-for="unit in units" :key="unit.id" :value="unit.id">
              {{ unit.name }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-sm">
          {{ t('reference') }}
          <select v-model="filters.date_field" :class="inputClass">
            <option v-for="value in dates" :key="value" :value="value">
              {{ t(`labels.${value}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-sm">
          {{ t('group') }}
          <select v-model="filters.group_by" :class="inputClass">
            <option v-for="value in groups" :key="value" :value="value">
              {{ t(`groups.${value}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-sm">
          {{ t('labels.origin') }}
          <select v-model="filters.origin" :class="inputClass">
            <option v-for="value in origins" :key="value" :value="value">
              {{ t(`origins.${value}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-sm">
          {{ t('from') }}
          <input
            v-model="filters.from"
            type="date"
            :min="firstDate"
            :class="inputClass"
          />
        </label>
        <label class="grid gap-1 text-sm">
          {{ t('to') }}
          <input
            v-model="filters.to"
            type="date"
            :min="filters.from || firstDate"
            :class="inputClass"
          />
        </label>
        <label class="grid gap-1 text-sm">
          {{ t('labels.phase') }}
          <select v-model="filters.phase" :class="inputClass">
            <option value="">{{ t('allPhases') }}</option>
            <option v-for="value in phases" :key="value" :value="value">
              {{ t(`phases.${value}`) }}
            </option>
          </select>
        </label>
      </div>
      <div class="flex flex-wrap items-end gap-3">
        <label class="grid gap-1 text-sm">
          {{ t('extra') }}
          <select
            v-model="field"
            :class="inputClass"
            :disabled="!scope.allowed.value"
            @change="term = ''"
          >
            <option value="">{{ t('choose') }}</option>
            <option v-for="key in fields" :key="key" :value="key">
              {{ t(`fields.${key}`) }}
            </option>
          </select>
        </label>
        <template v-if="field">
          <label class="grid gap-1 text-sm">
            {{ t('searchOption') }}
            <input
              v-model="term"
              type="search"
              maxlength="100"
              :class="inputClass"
              @keydown.enter.prevent
            />
          </label>
          <label class="grid gap-1 text-sm">
            {{ t('value') }}
            <select
              v-model="optionId"
              :class="inputClass"
              :disabled="optionLoading"
            >
              <option value="">
                {{ t(optionLoading ? 'loading' : 'choose') }}
              </option>
              <option
                v-if="field === 'assignee_membership_id'"
                value="unassigned"
              >
                {{ t('unassigned') }}
              </option>
              <option v-for="row in options" :key="row.id" :value="row.id">
                {{ row.name }}
              </option>
            </select>
          </label>
          <button
            type="button"
            :class="inputClass"
            :disabled="!optionId"
            @click="addFilter"
          >
            {{ t('add') }}
          </button>
        </template>
      </div>
      <p v-if="lookupError || hasMore" class="text-sm" role="status">
        {{ t(lookupError || 'refine') }}
      </p>
      <ul v-if="Object.keys(selected).length" class="flex flex-wrap gap-2">
        <li v-for="(row, key) in selected" :key="key">
          <button
            type="button"
            :class="inputClass"
            :aria-label="t('remove', { field: t(`fields.${key}`) })"
            @click="delete selected[key]"
          >
            {{
              t('activeFilter', { field: t(`fields.${key}`), name: row.name })
            }}
          </button>
        </li>
      </ul>
      <div class="flex gap-2">
        <button
          type="submit"
          class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
          :disabled="!scope.allowed.value || busy"
        >
          {{ t(busy ? 'loading' : 'run') }}
        </button>
        <button type="button" :class="inputClass" @click="clear">
          {{ t('clear') }}
        </button>
      </div>
    </form>
    <p v-if="error" class="text-sm text-n-ruby-11" role="alert">
      {{ t(error) }}
    </p>
    <ManagerialReportIndicators
      v-if="report?.indicators"
      :data="report.indicators"
    />
    <ReportExportMenu
      v-if="report?.export_limits"
      managerial
      :unit-id="unitId"
      :filters="applied"
      :total="report.meta.total"
      :limits="report.export_limits"
    />
    <p v-if="report?.meta.total === 0" class="text-sm" role="status">
      {{ t('empty') }}
    </p>
    <template v-if="report?.meta.total">
      <p class="text-sm" role="status">
        {{ t('total', { count: report.meta.total }) }} · {{ report.timezone }}
      </p>
      <div class="overflow-x-auto">
        <table class="w-full min-w-max text-sm">
          <thead class="bg-n-alpha-1">
            <tr>
              <th
                v-for="column in columns"
                :key="column"
                scope="col"
                class="px-3 py-2 text-left"
              >
                {{ t(`labels.${column}`) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in report.items"
              :key="row.id"
              class="border-b border-n-weak"
            >
              <td
                v-for="column in columns"
                :key="column"
                class="max-w-72 break-words px-3 py-2"
              >
                <button
                  v-if="column === 'id'"
                  type="button"
                  class="text-n-blue-11 underline"
                  @click="emit('open', row.id)"
                >
                  #{{ row.id }}
                </button>
                <template v-else>{{ display(row, column) }}</template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="flex flex-wrap items-center gap-3 text-sm">
        <button
          type="button"
          :class="inputClass"
          :disabled="busy || report.meta.page < 2"
          @click="load(report.meta.page - 1)"
        >
          {{ t('previous') }}
        </button>
        <span>{{ t('page', { page: report.meta.page }) }}</span>
        <button
          type="button"
          :class="inputClass"
          :disabled="
            busy || report.meta.page * report.meta.per_page >= report.meta.total
          "
          @click="load(report.meta.page + 1)"
        >
          {{ t('next') }}
        </button>
      </div>
    </template>
  </section>
</template>
