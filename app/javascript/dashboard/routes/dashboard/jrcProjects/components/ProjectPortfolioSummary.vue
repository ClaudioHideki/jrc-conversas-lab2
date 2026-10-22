<script setup>
import { computed } from 'vue';
import { useProjects } from '../useProjects';

const props = defineProps({ portfolio: { type: Object, required: true } });
const emit = defineEmits(['filter']);
const { projectText } = useProjects();
const total = computed(() => props.portfolio.total || 0);
const cards = computed(() => [
  {
    key: '',
    label: projectText('PORTFOLIO_TOTAL', 'Projetos no total'),
    value: total.value,
    icon: 'i-lucide-folder-open',
    tone: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    key: 'active',
    label: projectText('PORTFOLIO_ACTIVE', 'Em andamento'),
    value: props.portfolio.by_status?.active || 0,
    icon: 'i-lucide-refresh-cw',
    tone: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    key: 'planned',
    label: projectText('PORTFOLIO_PLANNED', 'Planejados'),
    value: props.portfolio.by_status?.planned || 0,
    icon: 'i-lucide-calendar-days',
    tone: 'bg-indigo-50 text-indigo-600 dark:bg-indigo-900/30 dark:text-indigo-200',
  },
  {
    key: 'completed',
    label: projectText('PORTFOLIO_COMPLETED', 'Concluídos'),
    value: props.portfolio.by_status?.completed || 0,
    icon: 'i-lucide-circle-check',
    tone: 'bg-emerald-50 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-200',
  },
  {
    key: 'overdue',
    label: projectText('PORTFOLIO_OVERDUE', 'Em atraso'),
    value: props.portfolio.overdue || 0,
    icon: 'i-lucide-clock-3',
    tone: 'bg-n-ruby-3 text-n-ruby-11',
  },
]);
const statuses = computed(() =>
  [
    {
      key: 'completed',
      label: projectText('PORTFOLIO_COMPLETED', 'Concluídos'),
      color: 'text-emerald-500',
    },
    {
      key: 'active',
      label: projectText('PORTFOLIO_ACTIVE', 'Em andamento'),
      color: 'text-n-blue-9',
    },
    {
      key: 'planned',
      label: projectText('PORTFOLIO_PLANNED', 'Planejados'),
      color: 'text-indigo-500',
    },
    {
      key: 'on_hold',
      label: projectText('PORTFOLIO_PAUSED', 'Pausados'),
      color: 'text-amber-500',
    },
    {
      key: 'canceled',
      label: projectText('PORTFOLIO_CANCELED', 'Cancelados'),
      color: 'text-n-slate-9',
    },
  ].map(row => ({ ...row, value: props.portfolio.by_status?.[row.key] || 0 }))
);
const taskCount = computed(() =>
  Object.values(props.portfolio.tasks || {}).reduce(
    (sum, count) => sum + count,
    0
  )
);
const taskComplete = computed(() => props.portfolio.tasks?.completed || 0);
const percent = (value, sum) => (sum ? Math.round((value * 100) / sum) : 0);
const taskPercent = computed(() =>
  percent(taskComplete.value, taskCount.value)
);
const offset = index =>
  -statuses.value
    .slice(0, index)
    .reduce((sum, row) => sum + (row.value * 100) / (total.value || 1), 0);
const maxDelivery = computed(() =>
  Math.max(
    1,
    ...(props.portfolio.deliveries || []).flatMap(row => [
      row.planned,
      row.completed,
    ])
  )
);
const monthLabel = month =>
  new Date(month + '-15T12:00:00')
    .toLocaleDateString('pt-BR', { month: 'short' })
    .replace('.', '');
</script>

<template>
  <section
    class="flex flex-col gap-4"
    :aria-label="
      projectText('PORTFOLIO_INDICATORS', 'Indicadores do portfólio')
    "
  >
    <div class="grid grid-cols-2 gap-3 lg:grid-cols-5">
      <button
        v-for="card in cards"
        :key="card.key"
        class="flex items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 text-left shadow-sm transition hover:border-n-blue-7"
        @click="emit('filter', card.key)"
      >
        <span
          class="flex size-11 shrink-0 items-center justify-center rounded-2xl"
          :class="card.tone"
          ><span
            class="block size-6 shrink-0"
            :class="card.icon"
            aria-hidden="true"
        /></span>
        <span class="min-w-0 flex-1"
          ><strong class="block text-2xl leading-tight">{{ card.value }}</strong
          ><span class="mt-1 block text-xs text-n-slate-11">{{
            card.label
          }}</span
          ><span class="mt-2 block text-xs text-n-slate-10">{{
            card.key
              ? percent(card.value, total) +
                '% ' +
                projectText('OF_TOTAL', 'do total')
              : projectText('VISIBLE_PROJECTS', 'Projetos no seu acesso')
          }}</span></span
        >
      </button>
    </div>
    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <article
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
      >
        <h3 class="text-sm font-semibold">
          {{ projectText('PROJECT_STATUS_CHART', 'Situação dos projetos') }}
        </h3>
        <div class="mt-4 flex items-center justify-around gap-4">
          <div class="relative size-36 shrink-0">
            <svg
              viewBox="0 0 120 120"
              class="size-full -rotate-90"
              aria-hidden="true"
            >
              <circle
                cx="60"
                cy="60"
                r="46"
                fill="none"
                stroke="currentColor"
                stroke-width="15"
                class="text-n-slate-3"
              />
              <circle
                v-for="(row, index) in statuses"
                :key="row.key"
                cx="60"
                cy="60"
                r="46"
                pathLength="100"
                fill="none"
                stroke="currentColor"
                stroke-width="15"
                :stroke-dasharray="(row.value * 100) / (total || 1) + ' 100'"
                :stroke-dashoffset="offset(index)"
                :class="row.color"
              />
            </svg>
            <div
              class="absolute inset-0 flex flex-col items-center justify-center"
            >
              <strong class="text-2xl">{{ total }}</strong
              ><span class="text-xs text-n-slate-11">{{
                projectText('PROJECTS', 'Projetos')
              }}</span>
            </div>
          </div>
          <ul class="min-w-0 flex-1 space-y-2 text-xs">
            <li
              v-for="row in statuses"
              :key="row.key"
              class="flex items-center gap-2"
            >
              <span
                class="size-2.5 shrink-0 rounded-full bg-current"
                :class="row.color"
              /><span class="flex-1 text-n-slate-11">{{ row.label }}</span
              ><strong>{{ row.value }}</strong>
            </li>
          </ul>
        </div>
      </article>
      <article
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
      >
        <div class="flex flex-wrap justify-between gap-2">
          <h3 class="text-sm font-semibold">
            {{ projectText('MONTHLY_DELIVERIES', 'Entregas por mês') }}
          </h3>
          <div class="flex gap-3 text-xs text-n-slate-11">
            <span class="flex items-center gap-1"
              ><span class="size-2 rounded-full bg-n-slate-7" />{{
                projectText('DELIVERIES_PLANNED', 'Previstas')
              }}</span
            ><span class="flex items-center gap-1"
              ><span class="size-2 rounded-full bg-n-blue-9" />{{
                projectText('PORTFOLIO_COMPLETED', 'Concluídas')
              }}</span
            >
          </div>
        </div>
        <svg
          v-if="portfolio.deliveries?.some(row => row.planned || row.completed)"
          viewBox="0 0 350 150"
          class="mt-3 h-40 w-full"
          role="img"
          :aria-label="
            projectText(
              'DELIVERY_CHART_LABEL',
              'Entregas previstas por prazo e concluídas pela data de encerramento'
            )
          "
        >
          <line
            v-for="line in 4"
            :key="line"
            x1="25"
            x2="345"
            :y1="line * 28"
            :y2="line * 28"
            stroke="currentColor"
            class="text-n-slate-3"
          />
          <g v-for="(row, index) in portfolio.deliveries" :key="row.month">
            <rect
              :x="32 + index * 52"
              :y="116 - (row.planned * 90) / maxDelivery"
              width="17"
              :height="(row.planned * 90) / maxDelivery"
              rx="2"
              fill="currentColor"
              class="text-n-slate-7"
            >
              <title>
                {{ row.month }}: {{ row.planned }}
                {{ projectText('DELIVERIES_PLANNED', 'previstas') }}
              </title>
            </rect>
            <rect
              :x="51 + index * 52"
              :y="116 - (row.completed * 90) / maxDelivery"
              width="17"
              :height="(row.completed * 90) / maxDelivery"
              rx="2"
              fill="currentColor"
              class="text-n-blue-9"
            >
              <title>
                {{ row.month }}: {{ row.completed }}
                {{ projectText('PORTFOLIO_COMPLETED', 'concluídas') }}
              </title>
            </rect>
            <text
              :x="49 + index * 52"
              :y="
                Math.max(
                  13,
                  108 -
                    (Math.max(row.planned, row.completed) * 90) / maxDelivery
                )
              "
              text-anchor="middle"
              fill="currentColor"
              class="text-[9px] text-n-slate-11"
            >
              {{ row.planned }}/{{ row.completed }}
            </text>
            <text
              :x="49 + index * 52"
              y="138"
              text-anchor="middle"
              fill="currentColor"
              class="text-[11px] text-n-slate-11"
            >
              {{ monthLabel(row.month) }}
            </text>
          </g>
        </svg>
        <p v-else class="py-12 text-center text-sm text-n-slate-11">
          {{
            projectText(
              'NO_DELIVERY_DATA',
              'Nenhuma entrega com datas registradas neste período.'
            )
          }}
        </p>
      </article>
      <article
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
      >
        <h3 class="text-sm font-semibold">
          {{ projectText('TASKS', 'Tarefas') }}
        </h3>
        <div class="mt-4 flex items-center justify-around gap-4">
          <div class="relative size-36 shrink-0">
            <svg
              viewBox="0 0 120 120"
              class="size-full -rotate-90"
              aria-hidden="true"
            >
              <circle
                cx="60"
                cy="60"
                r="46"
                fill="none"
                stroke="currentColor"
                stroke-width="15"
                class="text-n-slate-3"
              />
              <circle
                cx="60"
                cy="60"
                r="46"
                fill="none"
                pathLength="100"
                stroke="currentColor"
                stroke-width="15"
                :stroke-dasharray="taskPercent + ' 100'"
                class="text-emerald-500"
              />
            </svg>
            <div
              class="absolute inset-0 flex flex-col items-center justify-center"
            >
              <strong class="text-2xl">{{ taskPercent }}%</strong
              ><span class="text-xs text-n-slate-11"
                >{{ taskComplete }}/{{ taskCount }}</span
              >
            </div>
          </div>
          <ul class="flex-1 space-y-3 text-xs">
            <li class="flex justify-between gap-2">
              <span class="text-n-slate-11">{{
                projectText('TASKS_COMPLETED', 'Concluídas')
              }}</span
              ><strong class="text-emerald-600">{{ taskComplete }}</strong>
            </li>
            <li class="flex justify-between gap-2">
              <span class="text-n-slate-11">{{
                projectText('PORTFOLIO_ACTIVE', 'Em andamento')
              }}</span
              ><strong class="text-n-blue-11">{{
                portfolio.tasks?.in_progress || 0
              }}</strong>
            </li>
            <li class="flex justify-between gap-2">
              <span class="text-n-slate-11">{{
                projectText('TASKS_OTHER', 'Demais situações')
              }}</span
              ><strong>{{
                taskCount - taskComplete - (portfolio.tasks?.in_progress || 0)
              }}</strong>
            </li>
            <li class="flex justify-between gap-2 border-t border-n-weak pt-2">
              <span class="text-n-slate-11">{{
                projectText('OVERDUE', 'Atrasadas')
              }}</span
              ><strong class="text-n-ruby-11">{{
                portfolio.overdue_tasks || 0
              }}</strong>
            </li>
          </ul>
        </div>
      </article>
    </div>
  </section>
</template>
