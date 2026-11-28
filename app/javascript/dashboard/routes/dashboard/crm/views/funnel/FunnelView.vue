<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import FunnelAPI from 'dashboard/api/crm/funnel';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import CrmListingHeader from '../../components/shared/CrmListingHeader.vue';
import DealsFunnelKanban from '../../components/kanban/DealsFunnelKanban.vue';
import FunnelDealsDialog from './FunnelDealsDialog.vue';
import {
  formatFunnelMoney,
  funnelMetrics,
  funnelTotals,
} from './funnelMetrics';
import { exportFunnelDeals } from './exportFunnel';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t, n, locale } = useI18n();
const initialFilters = () => ({
  month: '',
  pipeline_id: '',
  team_id: '',
  owner_id: '',
});
const draft = ref(initialFilters());
const applied = ref(initialFilters());
const mode = ref('conversion');
const isBoard = computed(() => route.query.view === 'kanban');
const report = ref(null);
const options = ref({ pipelines: [], owners: [], teams: [] });
const busy = ref(false);
const failed = ref(false);
const selection = ref(null);
let controller;
const identity = computed(
  () => `${route.params.accountId}:${authorityScope(store.getters)}`
);
const dimensions = ['team_id', 'owner_id'];
const resetDimensions = () =>
  dimensions.forEach(key => {
    draft.value[key] = '';
  });

async function load() {
  controller?.abort();
  const request = new AbortController();
  controller = request;
  const context = identity.value;
  const filters = { ...draft.value, mode: mode.value };
  if (route.query.customer_segment_id)
    filters.customer_segment_id = route.query.customer_segment_id;
  busy.value = true;
  failed.value = false;
  report.value = null;
  selection.value = null;

  try {
    const { data } = await FunnelAPI.show(filters, {
      accountId: route.params.accountId,
      signal: request.signal,
    });
    if (request.signal.aborted || context !== identity.value) return;
    options.value = {
      pipelines: data.pipelines,
      owners: data.owners,
      teams: data.teams,
    };
    draft.value = {
      ...draft.value,
      pipeline_id: data.pipeline_id || '',
      month: data.month,
    };
    applied.value = { ...draft.value };
    report.value = data;
  } catch {
    if (!request.signal.aborted && context === identity.value)
      failed.value = true;
  } finally {
    if (!request.signal.aborted && context === identity.value)
      busy.value = false;
  }
}

const changeView = async view => {
  if (view === 'kanban') {
    selection.value = null;
    await router.replace({ query: { ...route.query, view: 'kanban' } });
  } else {
    const changed = mode.value !== view;
    mode.value = view;
    if (changed) resetDimensions();
    if (isBoard.value)
      await router.replace({ query: { ...route.query, view: undefined } });
    else if (changed) await load();
  }
};
watch(identity, () => {
  controller?.abort();
  selection.value = null;
  report.value = null;
  options.value = { pipelines: [], owners: [], teams: [] };
  draft.value = initialFilters();
  if (!isBoard.value) load();
});
watch(
  [isBoard, () => route.query.customer_segment_id],
  ([board]) => {
    if (board) {
      controller?.abort();
      selection.value = null;
    } else load();
  },
  { immediate: true }
);
onBeforeUnmount(() => controller?.abort());

const portfolio = computed(() => mode.value === 'portfolio');
const metrics = computed(
  () => report.value && funnelMetrics(report.value, mode.value)
);
const description = computed(() =>
  portfolio.value
    ? t('CRM.SALES_FUNNEL.PORTFOLIO_HELP')
    : t('CRM.SALES_FUNNEL.COHORT_HELP')
);
const chartRows = computed(
  () => metrics.value?.stages.filter(item => item.measured.length) || []
);
const maxCount = computed(() =>
  Math.max(1, ...(metrics.value?.bars.map(item => item.rows.length) || []))
);
const maxDays = computed(() =>
  Math.max(0.1, ...chartRows.value.map(item => item.averageDays))
);
const widthClasses = [
  'w-1/12',
  'w-2/12',
  'w-3/12',
  'w-4/12',
  'w-5/12',
  'w-6/12',
  'w-7/12',
  'w-8/12',
  'w-9/12',
  'w-10/12',
  'w-11/12',
  'w-full',
];
const heightClasses = [
  'h-2',
  'h-3',
  'h-5',
  'h-7',
  'h-9',
  'h-11',
  'h-14',
  'h-16',
  'h-20',
  'h-24',
  'h-28',
  'h-32',
];
const widthClass = count =>
  widthClasses[Math.max(0, Math.ceil((count * 12) / maxCount.value) - 1)];
const heightClass = days =>
  heightClasses[Math.max(0, Math.ceil((days * 12) / maxDays.value) - 1)];
const funnelColors = [
  'bg-[#123fa4]',
  'bg-[#0754bd]',
  'bg-[#096bb0]',
  'bg-[#087f9f]',
  'bg-[#087e82]',
  'bg-[#09726d]',
];
const timeColors = [
  'bg-[#13a998]',
  'bg-[#10928b]',
  'bg-[#087e82]',
  'bg-[#b96d00]',
];
const dayLabel = value => {
  if (value === null || value === undefined) return '—';
  const count = Math.round(value * 10) / 10;
  return t('CRM.SALES_FUNNEL.DAYS', { count: n(count) }, count);
};
const percent = value =>
  value === undefined || value === null
    ? '—'
    : `${n(Math.round(value * 10) / 10)}%`;
const formatDate = value =>
  value === null || value === undefined
    ? '—'
    : new Intl.DateTimeFormat(locale.value, {
        timeZone: report.value.timezone,
      }).format(value);
const monthLabel = computed(() => {
  if (!applied.value.month) return '';
  return new Intl.DateTimeFormat(locale.value, {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${applied.value.month}-01T00:00:00Z`));
});
const contextLabels = computed(() =>
  [
    portfolio.value ? t('CRM.SALES_FUNNEL.PORTFOLIO') : monthLabel.value,
    options.value.pipelines.find(item => item.id === applied.value.pipeline_id)
      ?.name,
    options.value.teams.find(item => item.id === applied.value.team_id)?.name ||
      t('CRM.SALES_FUNNEL.ALL_TEAMS'),
    options.value.owners.find(item => item.id === applied.value.owner_id)
      ?.name || t('CRM.SALES_FUNNEL.ALL_OWNERS'),
  ].filter(Boolean)
);
const money = rows =>
  funnelTotals(rows)
    .map(([currency, cents]) =>
      formatFunnelMoney(cents, currency, locale.value)
    )
    .join(' · ') || '—';
const cards = computed(() => {
  const data = metrics.value;
  if (!data) return [];
  const tones = [
    'bg-n-blue-3 text-n-blue-11',
    'bg-n-teal-3 text-n-teal-11',
    'bg-n-iris-3 text-n-iris-11',
    'bg-n-amber-3 text-n-amber-11',
  ];
  const definitions = portfolio.value
    ? [
        [
          t('CRM.SALES_FUNNEL.PORTFOLIO'),
          n(data.entry.rows.length),
          'i-lucide-briefcase-business',
          data.entry.rows,
        ],
        [
          t('CRM.SALES_FUNNEL.OPEN_VALUE'),
          money(data.entry.rows),
          'i-lucide-coins',
          data.entry.rows,
        ],
        [
          t('CRM.SALES_FUNNEL.ACTIVITY_LABEL'),
          n(data.withoutActivity.length),
          'i-lucide-calendar-clock',
          data.withoutActivity,
        ],
        [
          t('CRM.SALES_FUNNEL.STALLED_LABEL'),
          n(data.stalled.length),
          'i-lucide-clock-3',
          data.stalled,
        ],
      ]
    : [
        [
          t('CRM.SALES_FUNNEL.ENTRIES'),
          n(data.entry.rows.length),
          'i-lucide-filter',
          data.entry.rows,
        ],
        [
          t('CRM.SALES_FUNNEL.WON'),
          n(data.won.length),
          'i-lucide-trophy',
          data.won,
        ],
        [
          t('CRM.SALES_FUNNEL.OVERALL_CONVERSION'),
          percent(data.conversion),
          'i-lucide-target',
          data.won,
        ],
        [
          t('CRM.SALES_FUNNEL.AVG_CYCLE'),
          dayLabel(data.averageCycle),
          'i-lucide-calendar-days',
          null,
        ],
      ];
  return definitions.map(([label, value, icon, rows], index) => ({
    label,
    value,
    icon,
    rows,
    tone: tones[index],
  }));
});
const attention = computed(() => {
  const data = metrics.value;
  if (!data) return [];
  const items = [];
  if (data.awaitingWin) {
    const { from, to, rows } = data.awaitingWin;
    items.push({
      title: t('CRM.SALES_FUNNEL.AWAITING_WIN', {
        from,
        to,
        count: rows.length,
      }),
      icon: 'i-lucide-triangle-alert',
      rows,
    });
  }
  if (data.withoutActivity.length)
    items.push({
      title: t('CRM.SALES_FUNNEL.WITHOUT_ACTIVITY', {
        count: data.withoutActivity.length,
      }),
      icon: 'i-lucide-calendar-x',
      rows: data.withoutActivity,
    });
  if (data.stalled.length)
    items.push({
      title: t('CRM.SALES_FUNNEL.STALLED', { count: data.stalled.length }),
      icon: 'i-lucide-clock-3',
      rows: data.stalled,
    });
  return items;
});
const stageLabel = stage =>
  stage.id ? stage.name : t('CRM.SALES_FUNNEL.ENTRY');
const openRows = (title, rows, measured = false) => {
  selection.value = { title, rows, measured, description: description.value };
};
const openStage = item => {
  const title = item.id
    ? t(
        portfolio.value
          ? 'CRM.SALES_FUNNEL.CURRENT_DETAIL'
          : 'CRM.SALES_FUNNEL.STAGE_DETAIL',
        { stage: item.name }
      )
    : t('CRM.SALES_FUNNEL.ENTRY');
  openRows(title, item.rows);
};
const exportReport = () =>
  exportFunnelDeals(
    metrics.value.entry.rows,
    report.value.stages,
    t,
    formatDate,
    locale.value,
    report.value.month
  );
</script>

<template>
  <div
    class="flex min-h-full min-w-0 flex-col gap-3 bg-gradient-to-b from-n-blue-2 to-n-surface-1 p-3 sm:px-6"
  >
    <CrmListingHeader :title="t('CRM.SALES_FUNNEL.TITLE')">
      <button
        v-if="!isBoard"
        type="button"
        class="inline-flex items-center gap-2 rounded-lg border border-n-blue-6 bg-n-solid-2 px-3 py-2 text-sm font-semibold text-n-blue-11"
        :disabled="!metrics?.entry.rows.length"
        @click="exportReport"
      >
        <span class="i-lucide-download size-4" aria-hidden="true" />
        {{ t('CRM.SALES_FUNNEL.EXPORT') }}
      </button>
    </CrmListingHeader>
    <form
      v-if="!isBoard"
      class="grid gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-2 shadow-sm sm:grid-cols-2 xl:grid-cols-[repeat(4,minmax(0,1fr))_auto]"
      @submit.prevent="load"
    >
      <input
        v-model="draft.month"
        type="month"
        :aria-label="t('CRM.SALES_FUNNEL.MONTH')"
        :disabled="portfolio || busy"
        class="!mb-0 h-9 min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-sm"
        @change="resetDimensions"
      />
      <select
        v-model="draft.pipeline_id"
        :aria-label="t('CRM.SALES_FUNNEL.PIPELINE')"
        :disabled="busy"
        class="!mb-0 h-9 min-w-0 !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
        @change="resetDimensions"
      >
        <option v-if="!options.pipelines.length" value="">
          {{ t('CRM.SALES_FUNNEL.PIPELINE') }}
        </option>
        <option
          v-for="pipeline in options.pipelines"
          :key="pipeline.id"
          :value="pipeline.id"
        >
          {{ pipeline.name }}
        </option>
      </select>
      <select
        v-model="draft.team_id"
        :aria-label="t('CRM.SALES_FUNNEL.ALL_TEAMS')"
        :disabled="busy"
        class="!mb-0 h-9 min-w-0 !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
      >
        <option value="">{{ t('CRM.SALES_FUNNEL.ALL_TEAMS') }}</option>
        <option v-for="team in options.teams" :key="team.id" :value="team.id">
          {{ team.name }}
        </option>
      </select>
      <select
        v-model="draft.owner_id"
        :aria-label="t('CRM.SALES_FUNNEL.ALL_OWNERS')"
        :disabled="busy"
        class="!mb-0 h-9 min-w-0 !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
      >
        <option value="">{{ t('CRM.SALES_FUNNEL.ALL_OWNERS') }}</option>
        <option
          v-for="owner in options.owners"
          :key="owner.id"
          :value="owner.id"
        >
          {{ owner.name }}
        </option>
      </select>
      <button
        type="submit"
        class="inline-flex h-9 items-center justify-center gap-1.5 rounded-lg bg-n-brand px-3 text-sm font-semibold text-white"
        :disabled="busy"
      >
        <span class="i-lucide-filter size-4" aria-hidden="true" />
        {{ t('CRM.SALES_FUNNEL.APPLY') }}
      </button>
    </form>
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        :aria-pressed="!isBoard && !portfolio"
        :class="
          !isBoard && !portfolio
            ? 'border-n-blue-7 bg-n-blue-3 text-n-blue-11'
            : 'border-n-weak bg-n-solid-2'
        "
        class="rounded-full border px-3 py-1 text-xs font-semibold"
        @click="changeView('conversion')"
      >
        {{ t('CRM.SALES_FUNNEL.CONVERSION') }}
      </button>
      <button
        type="button"
        :aria-pressed="!isBoard && portfolio"
        :class="
          !isBoard && portfolio
            ? 'border-n-blue-7 bg-n-blue-3 text-n-blue-11'
            : 'border-n-weak bg-n-solid-2'
        "
        class="rounded-full border px-3 py-1 text-xs font-semibold"
        @click="changeView('portfolio')"
      >
        {{ t('CRM.SALES_FUNNEL.PORTFOLIO') }}
      </button>
      <button
        type="button"
        :aria-pressed="isBoard"
        :class="
          isBoard
            ? 'border-n-blue-7 bg-n-blue-3 text-n-blue-11'
            : 'border-n-weak bg-n-solid-2'
        "
        class="rounded-full border px-3 py-1 text-xs font-semibold"
        @click="changeView('kanban')"
      >
        {{ t('CRM.SALES_FUNNEL.BOARD') }}
      </button>
      <p v-if="!isBoard" class="m-0 text-xs text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <DealsFunnelKanban v-if="isBoard" />
    <p
      v-else-if="busy"
      role="status"
      class="m-0 rounded-xl border border-n-weak bg-n-solid-2 p-6 text-center text-sm"
    >
      {{ t('CRM.SALES_FUNNEL.LOADING') }}
    </p>
    <div
      v-else-if="failed"
      role="alert"
      class="rounded-xl border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
    >
      {{ t('CRM.SALES_FUNNEL.ERROR') }}
      <button type="button" class="ms-2 underline" @click="load">
        {{ t('CRM.FUNNEL.RETRY') }}
      </button>
    </div>
    <p
      v-else-if="!report?.pipeline_id"
      class="m-0 rounded-xl border border-n-weak bg-n-solid-2 p-6 text-center text-sm"
    >
      {{ t('CRM.FUNNEL.NO_PIPELINES') }}
    </p>
    <template v-else>
      <div class="grid grid-cols-2 gap-2 lg:grid-cols-4">
        <component
          :is="card.rows ? 'button' : 'div'"
          v-for="card in cards"
          :key="card.label"
          :type="card.rows ? 'button' : undefined"
          class="flex min-w-0 items-center gap-2 rounded-xl border border-n-weak px-3 py-2 text-left"
          :class="card.tone"
          @click="card.rows && openRows(card.label, card.rows)"
        >
          <span :class="card.icon" class="size-5 shrink-0" aria-hidden="true" />
          <span>
            <span class="block text-xs font-semibold">{{ card.label }}</span>
            <strong class="block text-lg tabular-nums sm:text-xl">{{
              card.value
            }}</strong>
          </span>
        </component>
      </div>

      <div
        class="grid min-w-0 items-start gap-3 xl:grid-cols-[minmax(0,1.32fr)_minmax(0,1fr)]"
      >
        <section
          class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-3 shadow-sm"
        >
          <h2 class="mb-2 flex items-center gap-2 text-sm font-bold">
            <span
              class="i-lucide-chart-no-axes-column-increasing size-4 text-n-blue-11"
              aria-hidden="true"
            />
            {{
              portfolio
                ? t('CRM.SALES_FUNNEL.CURRENT_BY_STAGE')
                : t('CRM.SALES_FUNNEL.CONVERSION_BY_STAGE')
            }}
          </h2>
          <p
            v-if="!portfolio"
            class="m-0 mb-1 text-right text-[11px] text-n-slate-11"
          >
            {{ t('CRM.SALES_FUNNEL.ADVANCE') }}
          </p>
          <div class="grid gap-1.5">
            <div
              v-for="(stage, index) in metrics.bars"
              :key="stage.key"
              class="flex items-center gap-2"
            >
              <div class="flex min-w-0 flex-1 justify-center">
                <button
                  type="button"
                  class="min-w-[7.5rem] max-w-full rounded-lg px-2 py-1.5 text-xs font-semibold text-white hover:brightness-110 focus-visible:ring-2 focus-visible:ring-n-brand"
                  :class="[
                    widthClass(stage.rows.length),
                    stage.is_won
                      ? 'bg-[#09726d]'
                      : funnelColors[index % funnelColors.length],
                  ]"
                  @click="openStage(stage)"
                >
                  <span class="block break-words">{{ stageLabel(stage) }}</span>
                  <strong class="block leading-none tabular-nums">{{
                    n(stage.rows.length)
                  }}</strong>
                </button>
              </div>
              <span
                v-if="!portfolio"
                class="w-14 shrink-0 rounded-full bg-n-teal-3 px-1 py-1 text-center text-xs font-bold text-n-teal-11"
                >{{ percent(metrics.advancement[stage.key]) }}</span
              >
            </div>
          </div>
          <p
            v-if="!metrics.bars.length"
            class="m-0 py-3 text-sm text-n-slate-11"
          >
            {{ t('CRM.FUNNEL.NO_STAGES') }}
          </p>
        </section>

        <section
          class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-3 shadow-sm"
        >
          <h2 class="mb-2 flex items-center gap-2 text-sm font-bold">
            <span
              class="i-lucide-triangle-alert size-4 text-n-amber-11"
              aria-hidden="true"
            />{{ t('CRM.SALES_FUNNEL.ATTENTION') }}
          </h2>
          <div class="grid gap-1.5">
            <div
              v-for="item in attention"
              :key="item.title"
              class="flex flex-wrap items-center gap-2 rounded-lg bg-n-amber-2 px-2 py-1 text-xs text-n-amber-11"
            >
              <span
                :class="item.icon"
                class="size-4 shrink-0"
                aria-hidden="true"
              />
              <span class="min-w-32 flex-1 font-semibold">{{
                item.title
              }}</span>
              <button
                type="button"
                class="rounded-md border border-n-amber-6 bg-n-solid-2 px-2 py-0.5 text-xs font-semibold"
                @click="openRows(item.title, item.rows)"
              >
                {{ t('CRM.SALES_FUNNEL.VIEW_DEALS') }}
              </button>
            </div>
            <p
              v-if="!attention.length"
              class="m-0 rounded-lg bg-n-slate-2 px-2 py-2 text-xs text-n-slate-11"
            >
              {{ t('CRM.SALES_FUNNEL.NO_ALERTS') }}
            </p>
          </div>
          <div class="mt-3 border-t border-n-weak pt-2">
            <h2 class="mb-1.5 flex items-center gap-2 text-sm font-bold">
              <span
                class="i-lucide-chart-column size-4 text-n-blue-11"
                aria-hidden="true"
              />{{
                portfolio
                  ? t('CRM.SALES_FUNNEL.AGE_BY_STAGE')
                  : t('CRM.SALES_FUNNEL.TIME_BY_STAGE')
              }}
            </h2>
            <div
              v-if="chartRows.length"
              class="flex items-end gap-1.5 overflow-x-auto rounded-md bg-n-slate-2 p-1"
            >
              <button
                v-for="(item, index) in chartRows"
                :key="item.key"
                type="button"
                class="flex min-w-20 flex-1 flex-col items-stretch justify-end rounded-md !p-1 text-xs hover:bg-n-blue-2"
                @click="
                  openRows(
                    t('CRM.SALES_FUNNEL.MEASURED', { stage: item.name }),
                    item.measured,
                    true
                  )
                "
              >
                <strong class="block py-0.5 text-xs">{{
                  dayLabel(item.averageDays)
                }}</strong>
                <span
                  class="block rounded-t-md"
                  :class="[
                    heightClass(item.averageDays),
                    timeColors[index % timeColors.length],
                  ]"
                  aria-hidden="true"
                />
                <span
                  class="flex h-9 items-start justify-center border-t border-n-weak pt-1 text-xs leading-tight"
                  >{{ item.name }}</span
                >
              </button>
            </div>
            <p
              v-else
              class="m-0 rounded-lg bg-n-slate-2 p-3 text-xs text-n-slate-11"
            >
              {{ t('CRM.SALES_FUNNEL.NO_TIME_DATA') }}
            </p>
          </div>
        </section>
      </div>

      <section
        class="min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <h2 class="flex items-center gap-2 p-3 text-sm font-bold">
          <span
            class="i-lucide-coins size-4 text-n-blue-11"
            aria-hidden="true"
          />{{ t('CRM.SALES_FUNNEL.STAGE_TABLE') }}
        </h2>
        <div class="relative overflow-x-auto">
          <table class="w-full min-w-[710px] text-left text-xs">
            <thead class="bg-n-blue-2 text-n-slate-11">
              <tr>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.STAGE') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{
                    portfolio
                      ? t('CRM.SALES_FUNNEL.CURRENT')
                      : t('CRM.SALES_FUNNEL.REACHED')
                  }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.VALUE') }}
                </th>
                <th v-if="!portfolio" scope="col" class="px-3 py-2">
                  {{ t('CRM.SALES_FUNNEL.ADVANCE') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.SALES_FUNNEL.AVG_TIME') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.CONTACT_LEAD.UI.ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="item in portfolio
                  ? metrics.stages
                  : [metrics.entry, ...metrics.stages]"
                :key="item.key"
              >
                <th scope="row" class="px-3 py-1.5 font-semibold">
                  {{ stageLabel(item) }}
                </th>
                <td class="px-3 py-1.5 tabular-nums">
                  {{ n(item.rows.length) }}
                </td>
                <td class="px-3 py-1.5">{{ money(item.rows) }}</td>
                <td v-if="!portfolio" class="px-3 py-1.5 tabular-nums">
                  {{ percent(metrics.advancement[item.key]) }}
                </td>
                <td class="px-3 py-1.5">{{ dayLabel(item.averageDays) }}</td>
                <td class="px-3 py-1.5">
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 rounded-md bg-n-blue-2 px-2 py-1 text-xs font-semibold text-n-blue-11"
                    @click="openStage(item)"
                  >
                    {{ t('CRM.SALES_FUNNEL.VIEW_DEALS')
                    }}<span
                      class="i-lucide-external-link size-3.5"
                      aria-hidden="true"
                    />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="m-0 border-t border-n-weak p-2.5 text-xs text-n-slate-11">
          {{
            portfolio
              ? t('CRM.SALES_FUNNEL.PORTFOLIO_NOTE')
              : t('CRM.SALES_FUNNEL.HISTORY_NOTE')
          }}
        </p>
      </section>
    </template>

    <FunnelDealsDialog
      v-if="selection && report && !isBoard"
      :selection="selection"
      :report="report"
      :context-labels="contextLabels"
      @close="selection = null"
    />
  </div>
</template>
