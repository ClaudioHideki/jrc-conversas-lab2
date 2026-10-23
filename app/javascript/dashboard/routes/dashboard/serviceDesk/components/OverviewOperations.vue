<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
import { v2Labels } from '../helpers/v2Labels';
const props = defineProps({ data: { type: Object, default: null } });
const emit = defineEmits(['navigate']);
const { t, locale } = useI18n();
const labels = computed(() => v2Labels(t));
const chart = computed(() => {
  const rows = props.data?.evolution || [];
  const maximum = Math.max(1, ...rows.map(row => row.count));
  const first = rows.length ? Date.parse(rows[0].date) : 0;
  const last = rows.length ? Date.parse(rows[rows.length - 1].date) : 0;
  return rows.map(row => ({
    ...row,
    x:
      24 +
      (last > first ? (Date.parse(row.date) - first) / (last - first) : 0.5) *
        452,
    y: 132 - (row.count / maximum) * 108,
  }));
});
const line = computed(() =>
  chart.value.map(row => `${row.x},${row.y}`).join(' ')
);
const categoriesTotal = computed(() =>
  (props.data?.top_categories || []).reduce(
    (total, row) => total + row.count,
    0
  )
);
const date = value =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    day: '2-digit',
    month: '2-digit',
    timeZone: 'UTC',
  }).format(new Date(`${value}T00:00:00Z`));
const duration = seconds => {
  if (seconds === null || seconds === undefined)
    return t('JRC_SERVICE_DESK.REDESIGN_LIST.not_measured');
  const minutes = Math.round(seconds / 60);
  if (minutes < 60)
    return t('JRC_SERVICE_DESK.REDESIGN_LIST.minutes', { count: minutes });
  return t('JRC_SERVICE_DESK.REDESIGN_LIST.hours_minutes', {
    hours: Math.floor(minutes / 60),
    minutes: minutes % 60,
  });
};
</script>

<template>
  <div v-if="data" class="mb-4 grid gap-4">
    <div class="grid gap-4 xl:grid-cols-3">
      <Panel
        :title="labels.supervisor.evolution"
        icon="i-lucide-chart-no-axes-combined"
        class="xl:col-span-2"
      >
        <template #actions>
          <span class="text-[10px] text-n-slate-11">{{
            t('JRC_SERVICE_DESK.REDESIGN_LIST.evolution_utc')
          }}</span>
        </template>
        <template v-if="chart.length">
          <svg
            class="h-40 w-full text-n-blue-9"
            viewBox="0 0 500 154"
            role="img"
            :aria-label="labels.supervisor.evolution"
          >
            <line
              x1="24"
              y1="24"
              x2="476"
              y2="24"
              stroke="currentColor"
              stroke-opacity="0.1"
            />
            <line
              x1="24"
              y1="78"
              x2="476"
              y2="78"
              stroke="currentColor"
              stroke-opacity="0.1"
            />
            <line
              x1="24"
              y1="132"
              x2="476"
              y2="132"
              stroke="currentColor"
              stroke-opacity="0.2"
            />
            <polyline
              :points="line"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            />
            <circle
              v-for="row in chart"
              :key="row.date"
              :cx="row.x"
              :cy="row.y"
              r="3"
              fill="currentColor"
            >
              <title>{{ date(row.date) }}: {{ row.count }}</title>
            </circle>
          </svg>
          <div class="flex justify-between gap-3 text-xs text-n-slate-11">
            <span>{{ date(chart[0].date) }}</span
            ><span>{{ date(chart[chart.length - 1].date) }}</span>
          </div>
          <details class="mt-3 text-xs text-n-slate-11">
            <summary class="cursor-pointer">
              {{ t('JRC_SERVICE_DESK.REDESIGN_LIST.daily_counts') }}
            </summary>
            <div class="mt-2 grid grid-cols-3 gap-2 sm:grid-cols-5">
              <p v-for="row in chart" :key="row.date" class="m-0 tabular-nums">
                {{ date(row.date) }}: {{ row.count }}
              </p>
            </div>
          </details>
        </template>
        <p v-else class="text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
        </p>
      </Panel>
      <Panel :title="labels.supervisor.top_categories" icon="i-lucide-tags">
        <p v-if="!data.top_categories.length" class="text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
        </p>
        <div
          v-for="row in data.top_categories.slice(0, 5)"
          :key="row.id || 'uncategorized'"
          class="mb-3 grid gap-1"
        >
          <div class="flex items-center justify-between gap-3 text-xs">
            <button
              v-if="row.id"
              type="button"
              class="text-start text-n-blue-11 focus-visible:ring-2 focus-visible:ring-n-blue-9"
              @click="
                emit('navigate', {
                  name: 'tickets',
                  query: { category_id: row.id },
                })
              "
            >
              {{ row.name }}
            </button>
            <span v-else>{{
              t('JRC_SERVICE_DESK.REDESIGN_LIST.uncategorized')
            }}</span>
            <strong class="tabular-nums">{{ row.count }}</strong>
          </div>
          <progress
            class="h-1.5 w-full accent-blue-700"
            :value="row.count"
            :max="Math.max(categoriesTotal, 1)"
            :aria-label="
              row.name || t('JRC_SERVICE_DESK.REDESIGN_LIST.uncategorized')
            "
          />
        </div>
      </Panel>
    </div>
    <div class="grid gap-4 lg:grid-cols-3">
      <Panel
        :title="t('JRC_SERVICE_DESK.REDESIGN_LIST.sla_summary')"
        icon="i-lucide-timer"
      >
        <template #actions>
          <Button
            v-if="data.sla"
            size="xs"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.COMMON.open')"
            @click="emit('navigate', { name: 'sla' })"
          />
        </template>
        <dl v-if="data.sla" class="grid gap-3 text-xs">
          <div class="flex justify-between gap-3">
            <dt class="text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.REDESIGN_LIST.first_response') }}
            </dt>
            <dd class="m-0 font-semibold">
              {{ duration(data.sla.first_response_average_seconds) }}
            </dd>
          </div>
          <div class="flex justify-between gap-3">
            <dt class="text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.REDESIGN_LIST.resolution') }}
            </dt>
            <dd class="m-0 font-semibold">
              {{ duration(data.sla.resolution_average_seconds) }}
            </dd>
          </div>
          <div class="flex justify-between gap-3">
            <dt class="text-n-slate-11">
              {{ labels.supervisor.running_breached }}
            </dt>
            <dd class="m-0 font-semibold text-n-ruby-11">
              {{ data.sla.running_breached }}
            </dd>
          </div>
        </dl>
        <p v-else class="text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.EXPERIENCE.sla_unavailable') }}
        </p>
      </Panel>
      <Panel
        :title="t('JRC_SERVICE_DESK.REDESIGN_LIST.workload')"
        icon="i-lucide-users"
      >
        <p v-if="!data.by_agent.length" class="text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
        </p>
        <button
          v-for="row in data.by_agent.slice(0, 4)"
          :key="row.id || 'unassigned'"
          type="button"
          :disabled="Boolean(row.id && !row.account_user_id)"
          class="mb-2 flex w-full items-center justify-between gap-3 text-start text-xs focus-visible:ring-2 focus-visible:ring-n-blue-9"
          @click="
            emit('navigate', {
              name: 'tickets',
              query: row.id
                ? {
                    assignee_id: row.account_user_id,
                    unit_id: row.unit_id,
                    phase: 'active',
                    status_id: undefined,
                    assignment: undefined,
                    mine: undefined,
                  }
                : {
                    assignment: 'unassigned',
                    phase: 'active',
                    status_id: undefined,
                    assignee_id: undefined,
                    mine: undefined,
                  },
            })
          "
        >
          <span class="text-n-blue-11">{{
            row.name || t('JRC_SERVICE_DESK.CREATION.unassigned')
          }}</span
          ><strong class="tabular-nums">{{ row.count }}</strong>
        </button>
      </Panel>
      <Panel
        :title="t('JRC_SERVICE_DESK.REDESIGN_LIST.pending_work')"
        icon="i-lucide-list-checks"
      >
        <div class="grid gap-2">
          <button
            v-for="kind in ['tasks', 'approvals'].filter(key => data[key])"
            :key="kind"
            type="button"
            class="flex items-center justify-between gap-3 rounded-lg bg-n-slate-2 p-2 text-start text-xs focus-visible:ring-2 focus-visible:ring-n-blue-9"
            @click="
              emit('navigate', {
                name: kind,
                query: kind === 'approvals' ? { status: 'pending' } : {},
              })
            "
          >
            <span>{{ t(`JRC_SERVICE_DESK.SCREENS.${kind}`) }}</span
            ><span class="font-semibold">{{
              data[kind].open ?? data[kind].pending
            }}</span>
            <span v-if="data[kind].overdue" class="text-n-ruby-11">{{
              t('JRC_SERVICE_DESK.REDESIGN_LIST.overdue_count', {
                count: data[kind].overdue,
              })
            }}</span>
          </button>
          <p
            v-if="!data.tasks && !data.approvals"
            class="text-xs text-n-slate-11"
          >
            {{ t('JRC_SERVICE_DESK.COMMON.not_available') }}
          </p>
        </div>
      </Panel>
    </div>
  </div>
</template>
