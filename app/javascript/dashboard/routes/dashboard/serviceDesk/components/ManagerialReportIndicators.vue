<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BarChart from 'shared/components/charts/BarChart.vue';
import messages from '../helpers/managerialReportMessages';

const props = defineProps({ data: { type: Object, required: true } });
const { t, locale } = useI18n({ useScope: 'local', messages });
const dimension = ref('origin');
const formatter = computed(
  () =>
    new Intl.NumberFormat(locale.value.replace('_', '-'), {
      maximumFractionDigits: 1,
    })
);
const number = value =>
  value == null ? t('indicators.unavailable') : formatter.value.format(value);
const closureRate = computed(() =>
  props.data.closure_rate == null
    ? t('indicators.unavailable')
    : `${number(props.data.closure_rate)}%`
);

const tiles = computed(() => [
  [t('indicators.total'), number(props.data.total)],
  [t('phases.closed'), number(props.data.phases.closed)],
  [t('indicators.rate'), closureRate.value],
  [t('indicators.new'), number(props.data.new_count)],
  [t('indicators.inService'), number(props.data.in_service)],
  [t('phases.waiting'), number(props.data.phases.waiting)],
  [t('phases.resolved'), number(props.data.phases.resolved)],
  [t('phases.cancelled'), number(props.data.phases.cancelled)],
  [t('indicators.openWaiting'), number(props.data.open_or_waiting)],
]);
const volume = computed(() =>
  props.data.volume.items.map(row => [row.day, row.count])
);
const distribution = computed(() =>
  (props.data.dimensions[dimension.value]?.items || []).map(row => {
    let label =
      row.name ||
      t(
        dimension.value === 'assignee_membership_id'
          ? 'unassigned'
          : 'indicators.missing'
      );
    if (dimension.value === 'origin') label = t(`origins.${row.id}`);
    return [label, row.count];
  })
);
const chart = rows => ({
  labels: rows.map(([label]) => label),
  datasets: [
    {
      data: rows.map(([, count]) => count),
      backgroundColor: '#3b82f6',
      borderRadius: 4,
      label: t('indicators.total'),
    },
  ],
});
const chartOptions = (horizontal = false) => ({
  indexAxis: horizontal ? 'y' : 'x',
  scales: {
    x: {
      ticks: { color: '#64748b', maxTicksLimit: 10, precision: 0 },
      grid: { display: false },
    },
    y: { ticks: { color: '#64748b', precision: 0 }, grid: { display: false } },
  },
});
const slaFields = [
  'measured',
  'unmeasured',
  'within',
  'late',
  'in_progress',
  'overdue',
  'mean_seconds',
];
</script>

<template>
  <section class="grid min-w-0 gap-4" data-testid="managerial-indicators">
    <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
      <div
        v-for="[label, value] in tiles"
        :key="label"
        class="rounded-lg border border-n-weak bg-n-solid-2 p-3"
      >
        <div class="text-sm text-n-slate-11">{{ label }}</div>
        <strong class="text-xl">{{ value }}</strong>
      </div>
    </div>
    <p class="text-xs text-n-slate-11">{{ t('indicators.definition') }}</p>
    <div class="grid min-w-0 gap-3 xl:grid-cols-2">
      <section class="min-w-0 rounded-lg border border-n-weak p-3">
        <h3 class="font-semibold">{{ t('indicators.volume') }}</h3>
        <p v-if="!volume.length" class="text-sm">{{ t('empty') }}</p>
        <template v-else>
          <div class="h-64">
            <BarChart
              :collection="chart(volume)"
              :chart-options="chartOptions()"
            />
          </div>
          <p v-if="data.volume.truncated" class="text-xs">
            {{ t('indicators.limitedPeriods') }}
          </p>
          <details>
            <summary class="cursor-pointer text-sm">
              {{ t('indicators.values') }}
            </summary>
            <ul class="grid gap-1 text-sm">
              <li v-for="[label, count] in volume" :key="label">
                {{ t('indicators.value', { label, count: number(count) }) }}
              </li>
            </ul>
          </details>
        </template>
      </section>
      <section class="min-w-0 rounded-lg border border-n-weak p-3">
        <label class="flex flex-wrap items-center gap-2 font-semibold">
          {{ t('indicators.distribution') }}
          <select
            v-model="dimension"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-sm"
          >
            <option v-for="(_, key) in data.dimensions" :key="key" :value="key">
              {{ t(`indicators.dimensions.${key}`) }}
            </option>
          </select>
        </label>
        <p v-if="!distribution.length" class="text-sm">
          {{ t('indicators.unavailable') }}
        </p>
        <template v-else>
          <div class="h-[24rem]">
            <BarChart
              :collection="chart(distribution)"
              :chart-options="chartOptions(true)"
            />
          </div>
          <p v-if="data.dimensions[dimension].truncated" class="text-xs">
            {{ t('indicators.limitedGroups') }}
          </p>
          <details>
            <summary class="cursor-pointer text-sm">
              {{ t('indicators.values') }}
            </summary>
            <ul class="grid gap-1 text-sm">
              <li v-for="([label, count], index) in distribution" :key="index">
                {{ t('indicators.value', { label, count: number(count) }) }}
              </li>
            </ul>
          </details>
        </template>
      </section>
    </div>
    <section class="min-w-0 rounded-lg border border-n-weak p-3">
      <h3 class="font-semibold">{{ t('indicators.sla') }}</h3>
      <p class="my-2 text-sm">
        {{
          t('indicators.closure', {
            seconds: number(data.closure.mean_seconds),
            count: number(data.closure.measured),
          })
        }}
      </p>
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr>
              <th scope="col" class="p-2 text-left">
                {{ t('indicators.clock') }}
              </th>
              <th
                v-for="field in slaFields"
                :key="field"
                scope="col"
                class="p-2 text-left"
              >
                {{ t(`indicators.slaFields.${field}`) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, key) in data.sla"
              :key="key"
              class="border-t border-n-weak"
            >
              <th scope="row" class="p-2 text-left">
                {{ t(`indicators.clocks.${key}`) }}
              </th>
              <td v-for="field in slaFields" :key="field" class="p-2">
                {{ number(row[field]) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="mt-2 text-xs text-n-slate-11">{{ t('indicators.coverage') }}</p>
    </section>
  </section>
</template>
