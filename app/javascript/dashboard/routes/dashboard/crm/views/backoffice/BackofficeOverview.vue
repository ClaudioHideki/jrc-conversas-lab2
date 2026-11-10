<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { moduleTabClasses } from 'dashboard/components-next/navigation/moduleTabClasses';
import { useBackofficeWorkspace } from './useBackofficeWorkspace';
import { stages, useBackofficePresentation } from './useBackofficePresentation';
import { stageTones, stageIcons, money } from './backofficeVisuals';
import BackofficeDashboardPanels from './BackofficeDashboardPanels.vue';
const props = defineProps({ report: { type: Boolean, default: false } });
const route = useRoute();
const {
  text,
  label,
  destination: requestDestination,
  date,
  deadline,
  late,
} = useBackofficePresentation();
const destination = id => ({
  ...requestDestination(id),
  query: { customer_segment_id: route.query.customer_segment_id },
});
const { result, loading, error, load } = useBackofficeWorkspace(
  props.report ? 'reports' : 'overview',
  { status: '', per_page: 5 }
);
const tab = ref(props.report ? 'indicators' : 'operation');
const stageCount = stage => {
  if (stage === 'completed') return result.value.summary.completed;
  if (stage === 'analysis')
    return (
      (result.value.summary.stages.analysis || 0) +
      (result.value.summary.stages.request || 0)
    );
  return result.value.summary.stages[stage] || 0;
};
const metrics = computed(() =>
  result.value
    ? [
        {
          key: 'TOTAL',
          value: result.value.summary.total,
          tone: 'blue',
          icon: 'i-lucide-inbox',
          section: 'requests',
          query: { status: 'all' },
        },
        {
          key: 'ANALYSIS',
          value: stageCount('analysis'),
          tone: 'cyan',
          icon: 'i-lucide-search',
          section: 'process',
        },
        {
          key: 'APPROVAL',
          value: stageCount('approval'),
          tone: 'violet',
          icon: 'i-lucide-check-check',
          section: 'approvals',
        },
        {
          key: 'CONTRACT',
          value: stageCount('contract'),
          tone: 'amber',
          icon: 'i-lucide-file-signature',
          section: 'contracts',
        },
        {
          key: 'COMPLETED',
          value: result.value.summary.completed,
          tone: 'teal',
          icon: 'i-lucide-circle-check',
          section: 'requests',
          query: { status: 'completed' },
        },
        {
          key: 'OVERDUE',
          value: result.value.summary.overdue,
          tone: 'rose',
          icon: 'i-lucide-clock-alert',
          section: 'sla',
        },
      ]
    : []
);
const alerts = computed(() =>
  result.value
    ? [
        {
          key: 'overdue',
          value: result.value.summary.overdue,
          tone: 'rose',
          icon: 'i-lucide-clock-alert',
          section: 'sla',
        },
        {
          key: 'blocked',
          value: result.value.summary.blocked,
          tone: 'amber',
          icon: 'i-lucide-triangle-alert',
          section: 'requests',
          query: { status: 'blocked' },
        },
        {
          key: 'waiting_customer',
          value: result.value.summary.waiting_customer,
          tone: 'blue',
          icon: 'i-lucide-user-clock',
          section: 'requests',
          query: { status: 'waiting_customer' },
        },
      ].filter(item => item.value)
    : []
);
const primaryStages = [
  'analysis',
  'documentation',
  'approval',
  'contract',
  'implementation',
  'completed',
];
const queueRows = computed(() =>
  Object.entries(result.value?.summary.queues || {}).map(([id, count]) => ({
    id,
    name:
      result.value.options.queues.find(queue => String(queue.id) === id)
        ?.name || (id ? `${text('QUEUE_REFERENCE')} #${id}` : text('NO_QUEUE')),
    count,
  }))
);
const target = (section, query = {}) => ({
  name: 'crm_backoffice',
  params: { section },
  query: { customer_segment_id: route.query.customer_segment_id, ...query },
});
const stageTarget = stage =>
  stage === 'analysis'
    ? target('process')
    : target(
        'requests',
        stage === 'completed' ? { status: 'completed' } : { stage }
      );
</script>

<template>
  <div
    class="space-y-4"
    :aria-busy="loading"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-xl font-bold">
          {{ text(report ? 'NAV.reports' : 'NAV.overview') }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ text('DASHBOARD.SUBTITLE') }}
        </p>
      </div>
      <button
        class="inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm font-semibold disabled:opacity-50"
        :class="moduleTabClasses('blue')"
        :disabled="loading"
        @click="load()"
      >
        <span class="i-lucide-refresh-cw size-4" />
        {{ text('REFRESH') }}
      </button>
    </header>
    <p
      v-if="loading"
      role="status"
      class="rounded-xl border border-n-weak bg-n-solid-2 p-8"
    >
      {{ text('LOADING') }}
    </p>
    <p
      v-else-if="error"
      role="alert"
      class="rounded-xl border border-rose-300 bg-rose-50 p-5 text-rose-800 dark:border-rose-800 dark:bg-rose-950/40 dark:text-rose-200"
    >
      {{ text('LOAD_ERROR') }}
    </p>
    <template v-else-if="result">
      <section class="grid gap-3 sm:grid-cols-3 xl:grid-cols-6">
        <RouterLink
          v-for="metric in metrics"
          :key="metric.key"
          :to="target(metric.section, metric.query)"
          class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-3 shadow-sm transition hover:border-n-strong"
        >
          <span
            class="grid size-10 shrink-0 place-content-center rounded-xl border"
            :class="moduleTabClasses(metric.tone)"
          >
            <span
              :class="metric.icon"
              class="size-5"
            />
          </span>
          <div class="min-w-0">
            <p class="text-xs font-medium text-n-slate-11">
              {{ text(`DASHBOARD.${metric.key}`) }}
            </p>
            <b class="text-2xl">{{ metric.value }}</b>
          </div>
        </RouterLink>
      </section>
      <nav
        :aria-label="text('OVERVIEW_TABS_LABEL')"
        class="flex flex-wrap gap-2"
      >
        <button
          v-for="(item, index) in ['operation', 'indicators', 'queues']"
          :key="item"
          class="rounded-lg border px-4 py-2 text-sm font-semibold"
          :class="
            moduleTabClasses(['blue', 'violet', 'teal'][index], tab === item)
          "
          :aria-pressed="tab === item"
          @click="tab = item"
        >
          {{ text(`DASHBOARD.${item}`) }}
        </button>
      </nav>
      <div
        v-if="tab === 'operation'"
        class="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_270px]"
      >
        <div class="min-w-0 space-y-4">
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
          >
            <h3 class="mb-3 flex items-center gap-2 font-semibold">
              <span
                class="i-lucide-workflow size-5 text-blue-600 dark:text-blue-300"
              />
              {{ text('DASHBOARD.PIPELINE') }}
            </h3>
            <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 2xl:grid-cols-6">
              <RouterLink
                v-for="stage in primaryStages"
                :key="stage"
                :to="stageTarget(stage)"
                class="rounded-xl border p-3"
                :class="moduleTabClasses(stageTones[stage])"
              >
                <span
                  class="mb-2 block size-5"
                  :class="stageIcons[stage]"
                />
                <span class="block text-xs font-semibold">
                  {{ label(stage) }}
                </span>
                <b class="mt-1 block text-xl">{{ stageCount(stage) }}</b>
              </RouterLink>
            </div>
            <details class="mt-3">
              <summary
                class="cursor-pointer text-xs font-semibold text-n-slate-11"
              >
                {{ text('DASHBOARD.MORE_STAGES') }}
              </summary>
              <div class="mt-3 flex flex-wrap gap-2">
                <RouterLink
                  v-for="stage in stages.filter(
                    item => !primaryStages.includes(item) && item !== 'request'
                  )"
                  :key="stage"
                  :to="stageTarget(stage)"
                  class="rounded-lg border px-3 py-2 text-xs font-semibold"
                  :class="moduleTabClasses(stageTones[stage])"
                >
                  {{ label(stage) }} {{ text('SEPARATOR') }}
                  {{ stageCount(stage) }}
                </RouterLink>
              </div>
            </details>
          </section>
          <section
            class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
          >
            <div
              class="flex items-center justify-between gap-3 border-b border-n-weak p-4"
            >
              <h3 class="font-semibold">{{ text('DASHBOARD.RECENT') }}</h3>
              <RouterLink
                :to="target('requests', { status: 'all' })"
                class="text-xs font-semibold text-blue-700 dark:text-blue-300"
              >
                {{ text('DASHBOARD.SEE_ALL') }}
              </RouterLink>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-left text-xs">
                <thead class="bg-n-slate-3 text-n-slate-11">
                  <tr>
                    <th class="px-3 py-2">{{ text('REQUEST') }}</th>
                    <th class="px-3 py-2">{{ text('CLIENT') }}</th>
                    <th class="px-3 py-2">{{ text('STAGE') }}</th>
                    <th class="px-3 py-2">{{ text('DASHBOARD.VALUE') }}</th>
                    <th class="px-3 py-2">{{ text('DEADLINE') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="item in result.data"
                    :key="item.id"
                    class="border-t border-n-weak"
                  >
                    <td class="max-w-52 px-3 py-3">
                      <RouterLink
                        :to="destination(item.id)"
                        class="font-bold text-blue-700 dark:text-blue-300"
                      >
                        {{ item.request_number }}
                      </RouterLink>
                      <p
                        class="mt-1 truncate text-n-slate-11"
                        :title="item.title"
                      >
                        {{ item.title }}
                      </p>
                    </td>
                    <td class="max-w-40 px-3 py-3">
                      <p class="truncate">
                        {{
                          item.company?.name ||
                          item.contact?.name ||
                          text('NO_CLIENT')
                        }}
                      </p>
                      <p class="mt-1 text-n-slate-11">
                        {{ label(item.request_kind) }}
                      </p>
                    </td>
                    <td class="px-3 py-3">
                      <span
                        class="inline-block rounded-lg border px-2 py-1"
                        :class="moduleTabClasses(stageTones[item.stage])"
                      >
                        {{ label(item.stage) }}
                      </span>
                      <p class="mt-1 text-n-slate-11">{{ item.owner.name }}</p>
                    </td>
                    <td class="whitespace-nowrap px-3 py-3 font-semibold">
                      {{ money(item.order.total_cents) }}
                    </td>
                    <td
                      class="px-3 py-3"
                      :class="
                        late(item)
                          ? 'font-semibold text-rose-700 dark:text-rose-300'
                          : 'text-n-slate-11'
                      "
                    >
                      {{ date(deadline(item)) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p
              v-if="!result.data.length"
              class="p-6 text-sm text-n-slate-11"
            >
              {{ text('EMPTY') }}
            </p>
          </section>
        </div>
        <aside class="space-y-4">
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
          >
            <h3 class="mb-3 font-semibold">{{ text('DASHBOARD.ALERTS') }}</h3>
            <div class="space-y-2">
              <RouterLink
                v-for="item in alerts"
                :key="item.key"
                :to="target(item.section, item.query)"
                class="flex items-center gap-2 rounded-lg border p-3 text-xs font-semibold"
                :class="moduleTabClasses(item.tone)"
              >
                <span
                  :class="item.icon"
                  class="size-4 shrink-0"
                />
                <span>{{ item.value }} {{ text(`METRICS.${item.key}`) }}</span>
                <span class="i-lucide-chevron-right ml-auto size-4 shrink-0" />
              </RouterLink>
              <p
                v-if="!alerts.length"
                class="text-sm text-n-slate-11"
              >
                {{ text('DASHBOARD.NO_ALERTS') }}
              </p>
            </div>
          </section>
          <section
            v-if="!report"
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
          >
            <div class="flex items-center justify-between gap-2">
              <h3 class="font-semibold">
                {{ text('DASHBOARD.MINE') }} {{ text('SEPARATOR') }}
                {{ result.dashboard.mine_total }}
              </h3>
              <RouterLink
                :to="target('mine')"
                class="text-xs font-semibold text-blue-700 dark:text-blue-300"
              >
                {{ text('DASHBOARD.SEE_ALL') }}
              </RouterLink>
            </div>
            <RouterLink
              v-for="item in result.dashboard.mine.slice(0, 3)"
              :key="item.id"
              :to="destination(item.id)"
              class="mt-3 flex items-start gap-2 text-xs"
            >
              <span class="i-lucide-circle size-4 shrink-0 text-n-slate-11" />
              <span class="min-w-0">
                <b class="block truncate">{{ item.title }}</b>
                <span class="mt-1 block text-n-slate-11">
                  {{ label(item.stage) }}
                </span>
              </span>
            </RouterLink>
            <p
              v-if="!result.dashboard.mine.length"
              class="mt-3 text-xs text-n-slate-11"
            >
              {{ text('DASHBOARD.NO_MINE') }}
            </p>
          </section>
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
          >
            <h3 class="mb-3 font-semibold">
              {{ text('DASHBOARD.QUICK_ACTIONS') }}
            </h3>
            <div class="grid grid-cols-2 gap-2">
              <RouterLink
                v-for="item in [
                  {
                    key: 'NEW_ORDER',
                    to: { name: 'crm_order_new' },
                    icon: 'i-lucide-shopping-cart',
                    tone: 'blue',
                  },
                  {
                    key: 'CHECK_DOCUMENTS',
                    to: target('docs'),
                    icon: 'i-lucide-files',
                    tone: 'amber',
                  },
                  {
                    key: 'CHECK_CONTRACTS',
                    to: target('contracts'),
                    icon: 'i-lucide-file-signature',
                    tone: 'violet',
                  },
                  {
                    key: 'FIND_REQUEST',
                    to: target('requests'),
                    icon: 'i-lucide-search',
                    tone: 'teal',
                  },
                ]"
                :key="item.key"
                :to="item.to"
                class="grid justify-items-center gap-2 rounded-xl border p-3 text-center text-xs font-semibold"
                :class="moduleTabClasses(item.tone)"
              >
                <span
                  :class="item.icon"
                  class="size-5"
                />
                {{ text(`DASHBOARD.${item.key}`) }}
              </RouterLink>
            </div>
          </section>
        </aside>
      </div>
      <BackofficeDashboardPanels
        v-else-if="tab === 'indicators'"
        :summary="result.summary"
      />
      <section
        v-else
        class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3"
      >
        <RouterLink
          v-for="queue in queueRows"
          :key="queue.id"
          :to="target('requests', queue.id ? { queueId: queue.id } : {})"
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        >
          <span>{{ queue.name }}</span>
          <b class="text-xl text-teal-700 dark:text-teal-300">
            {{ queue.count }}
          </b>
        </RouterLink>
        <p
          v-if="!queueRows.length"
          class="text-sm text-n-slate-11"
        >
          {{ text('EMPTY') }}
        </p>
      </section>
      <p class="text-xs text-n-slate-11">
        {{ text('DASHBOARD.COUNT_NOTE') }} {{ text('SCOPE_NOTE') }}
      </p>
    </template>
  </div>
</template>
