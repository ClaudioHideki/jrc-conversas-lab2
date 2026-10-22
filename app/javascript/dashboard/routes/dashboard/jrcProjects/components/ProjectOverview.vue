<script setup>
import { computed, ref } from 'vue';
import { useProjects } from '../useProjects';
import { formatDate } from '../../jrcOperations/api';
import { projectTaskStatuses } from '../taskBoard';

const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
});
const emit = defineEmits(['navigate', 'openTask']);
const { projectText } = useProjects();
const showAllActivity = ref(false);
const overview = computed(() => props.project.overview || {});
const counts = computed(() => overview.value.status_counts || {});
const total = computed(() => Number(props.project.tasks_total || 0));
const completed = computed(() => Number(props.project.tasks_completed || 0));
const progress = computed(() => Number(props.project.progress || 0));
const pending = computed(() =>
  ['backlog', 'pending', 'review', 'blocked'].reduce(
    (sum, key) => sum + Number(counts.value[key] || 0),
    0
  )
);
const notConfigured = computed(() =>
  projectText('NOT_CONFIGURED', 'Não configurado')
);
const hours = minutes =>
  `${(Number(minutes || 0) / 60).toLocaleString('pt-BR', {
    maximumFractionDigits: 2,
  })} h`;
function percentage(value) {
  return total.value ? Math.round((Number(value || 0) * 100) / total.value) : 0;
}
const metrics = computed(() => [
  {
    key: 'total',
    value: total.value,
    label: projectText('TASKS_TOTAL', 'Total de tarefas'),
    icon: 'i-lucide-clipboard-list',
    color: 'bg-n-slate-3 text-n-slate-11',
    hint: `${completed.value} ${projectText('COMPLETED_LABEL', 'concluídas')} (${progress.value}%)`,
    percent: progress.value,
    bar: 'text-n-teal-9',
  },
  {
    key: 'active',
    value: Number(counts.value.in_progress || 0),
    label: projectText('TASKS_IN_PROGRESS', 'Tarefas em andamento'),
    icon: 'i-lucide-refresh-cw',
    color: 'bg-n-blue-3 text-n-blue-11',
    percent: percentage(counts.value.in_progress),
    bar: 'text-n-blue-9',
  },
  {
    key: 'overdue',
    value: Number(overview.value.overdue_tasks || 0),
    label: projectText('TASKS_OVERDUE', 'Tarefas em atraso'),
    icon: 'i-lucide-circle-alert',
    color: 'bg-n-ruby-3 text-n-ruby-11',
    percent: percentage(overview.value.overdue_tasks),
    bar: 'text-n-ruby-9',
  },
  {
    key: 'pending',
    value: pending.value,
    label: projectText('TASKS_PENDING', 'Tarefas pendentes'),
    icon: 'i-lucide-hourglass',
    color: 'bg-n-amber-3 text-n-amber-11',
    percent: percentage(pending.value),
    bar: 'text-n-amber-9',
  },
  {
    key: 'estimated',
    value: overview.value.estimated_configured
      ? hours(overview.value.estimated_minutes)
      : notConfigured.value,
    label: projectText('ESTIMATED_HOURS', 'Horas previstas'),
    icon: 'i-lucide-timer',
    color: 'bg-n-teal-3 text-n-teal-11',
    compact: !overview.value.estimated_configured,
  },
  {
    key: 'worked',
    value: hours(overview.value.worked_minutes),
    label: projectText('RECORDED_HOURS', 'Horas registradas'),
    icon: 'i-lucide-clock-3',
    color: 'bg-n-slate-3 text-n-slate-11',
    hint: projectText('RECORDED_HOURS_HINT', 'Enviadas e aprovadas'),
  },
]);
const series = computed(() => [
  {
    key: 'completed',
    label: projectText('TASKS_COMPLETED_SHORT', 'Concluídas'),
    value: completed.value,
    color: 'text-n-teal-9',
  },
  {
    key: 'in_progress',
    label: projectText('IN_PROGRESS', 'Em andamento'),
    value: Number(counts.value.in_progress || 0),
    color: 'text-n-blue-9',
  },
  {
    key: 'pending',
    label: projectText('PENDING_LABEL', 'Pendentes'),
    value: pending.value,
    color: 'text-n-slate-8',
  },
  {
    key: 'canceled',
    label: projectText('CANCELED_LABEL', 'Canceladas'),
    value: Number(counts.value.canceled || 0),
    color: 'text-n-ruby-9',
  },
]);
const chartMaximum = computed(() =>
  Math.max(1, ...series.value.map(item => item.value))
);
const milestones = computed(() => overview.value.milestones || []);
const upcoming = computed(() => overview.value.upcoming_milestones || []);
const recentTasks = computed(() =>
  [...props.tasks]
    .sort((a, b) => new Date(b.updated_at) - new Date(a.updated_at))
    .slice(0, 4)
);
const activity = computed(() =>
  (props.project.recent_activity || []).slice(
    0,
    showAllActivity.value ? undefined : 4
  )
);
const budgetCards = computed(() => {
  const budget = props.project.budget;
  if (!budget || !props.project.capabilities?.includes('projects.budget.view'))
    return [];
  const money = cents =>
    new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: budget.currency || 'BRL',
    }).format(Number(cents || 0) / 100);
  return [
    {
      key: 'planned',
      label: projectText('BUDGET_PLANNED_LABEL', 'Orçamento previsto'),
      value: budget.configured
        ? money(budget.planned_cents)
        : notConfigured.value,
      hint: projectText('BUDGET_PLANNED_HINT', 'Valor previsto para o projeto'),
      icon: 'i-lucide-wallet',
      color: 'bg-n-blue-3 text-n-blue-11',
    },
    {
      key: 'committed',
      label: projectText('BUDGET_COMMITTED', 'Comprometido informado'),
      value: budget.configured
        ? money(budget.committed_cents)
        : notConfigured.value,
      hint: projectText(
        'BUDGET_COMMITTED_HINT',
        'Compromissos registrados no orçamento'
      ),
      icon: 'i-lucide-shopping-cart',
      color: 'bg-n-violet-3 text-n-violet-11',
    },
    {
      key: 'actual',
      label: projectText('BUDGET_ACTUAL', 'Custo das horas aprovadas'),
      value: money(budget.actual_cents),
      hint: projectText(
        'BUDGET_ACTUAL_HINT',
        'Horas aprovadas com custo por hora'
      ),
      icon: 'i-lucide-clock-3',
      color: 'bg-n-amber-3 text-n-amber-11',
    },
    {
      key: 'remaining',
      label: projectText('BUDGET_REMAINING_LABEL', 'Saldo disponível'),
      value: budget.configured
        ? money(budget.remaining_cents)
        : notConfigured.value,
      hint: projectText('BUDGET_REMAINING', 'Saldo previsto menos realizado'),
      icon: 'i-lucide-chart-no-axes-combined',
      color: 'bg-n-teal-3 text-n-teal-11',
    },
  ];
});

function taskTone(task) {
  if (task.status === 'completed') return 'bg-n-teal-3 text-n-teal-11';
  if (task.status === 'in_progress') return 'bg-n-blue-3 text-n-blue-11';
  if (task.status === 'blocked') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-slate-3 text-n-slate-11';
}
function initials(name) {
  return String(name || '')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(part => part[0])
    .join('')
    .toUpperCase();
}
function activityLabel(action) {
  const labels = {
    'projects.ticket.linked': ['EVENT_TICKET_LINKED', 'Chamado vinculado'],
    'projects.task.linked': ['EVENT_TASK_LINKED', 'Tarefa vinculada a chamado'],
    'projects.deal.linked': ['EVENT_DEAL_LINKED', 'Negócio vinculado'],
    'projects.conversation.linked': [
      'EVENT_CONVERSATION_LINKED',
      'Conversa vinculada',
    ],
    'projects.link.removed': ['EVENT_LINK_REMOVED', 'Vínculo removido'],
    'projects.project.created_from_ticket': [
      'EVENT_FROM_TICKET',
      'Projeto criado a partir de chamado',
    ],
    'projects.project.created_from_deal': [
      'EVENT_FROM_DEAL',
      'Projeto criado a partir de negócio',
    ],
    'projects.project.created_from_conversation': [
      'EVENT_FROM_CONVERSATION',
      'Projeto criado a partir de conversa',
    ],
    'projects.project.created': ['EVENT_PROJECT_CREATED', 'Projeto criado'],
    'projects.project.updated': ['EVENT_PROJECT_UPDATED', 'Projeto atualizado'],
    'projects.milestone.created': ['EVENT_MILESTONE_CREATED', 'Marco criado'],
    'projects.milestone.updated': [
      'EVENT_MILESTONE_UPDATED',
      'Marco atualizado',
    ],
    'projects.milestone.completed': [
      'EVENT_MILESTONE_COMPLETED',
      'Marco concluído',
    ],
    'projects.milestone.deleted': ['EVENT_MILESTONE_DELETED', 'Marco removido'],
    'projects.member.created': [
      'EVENT_MEMBER_CREATED',
      'Participante adicionado',
    ],
    'projects.member.updated': [
      'EVENT_MEMBER_UPDATED',
      'Participante atualizado',
    ],
    'projects.member.deleted': [
      'EVENT_MEMBER_DELETED',
      'Participante removido',
    ],
    'projects.task.created': ['EVENT_TASK_CREATED', 'Tarefa criada'],
    'projects.task.updated': ['EVENT_TASK_UPDATED', 'Tarefa atualizada'],
    'projects.task.moved': ['EVENT_TASK_MOVED', 'Tarefa movimentada'],
    'projects.task.deleted': ['EVENT_TASK_DELETED', 'Tarefa removida'],
    'projects.task.comment_added': [
      'EVENT_COMMENT',
      'Comentário interno registrado',
    ],
    'projects.task.checklist_added': [
      'EVENT_CHECKLIST',
      'Checklist atualizado',
    ],
    'projects.task.checklist_updated': [
      'EVENT_CHECKLIST',
      'Checklist atualizado',
    ],
    'projects.task.checklist_removed': [
      'EVENT_CHECKLIST',
      'Checklist atualizado',
    ],
    'projects.task.dependency_added': [
      'EVENT_DEPENDENCY_ADDED',
      'Dependência adicionada',
    ],
    'projects.task.dependency_removed': [
      'EVENT_DEPENDENCY_REMOVED',
      'Dependência removida',
    ],
    'projects.attachment.added': ['EVENT_ATTACHMENT_ADDED', 'Arquivo enviado'],
    'projects.attachment.removed': [
      'EVENT_ATTACHMENT_REMOVED',
      'Arquivo removido',
    ],
    'projects.time_entry.created': ['EVENT_TIME_CREATED', 'Horas registradas'],
    'projects.time_entry.updated': [
      'EVENT_TIME_UPDATED',
      'Apontamento revisado',
    ],
    'projects.budget.updated': ['EVENT_BUDGET_UPDATED', 'Orçamento atualizado'],
  };
  const [key, fallback] = labels[action] || [
    'EVENT_REGISTERED',
    'Atividade registrada',
  ];
  return projectText(key, fallback);
}
</script>

<template>
  <div class="flex min-w-0 flex-col gap-4">
    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 2xl:grid-cols-6">
      <article
        v-for="metric in metrics"
        :key="metric.key"
        class="flex gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
      >
        <span
          class="flex size-11 shrink-0 items-center justify-center rounded-xl [&_span]:size-6"
          :class="metric.color"
          aria-hidden="true"
          ><span :class="metric.icon"
        /></span>
        <div class="min-w-0 flex-1">
          <strong
            class="block font-semibold leading-tight"
            :class="metric.compact ? 'text-sm' : 'text-2xl'"
            >{{ metric.value }}</strong
          >
          <p class="mt-1 text-xs text-n-slate-11">{{ metric.label }}</p>
          <svg
            v-if="metric.percent !== undefined"
            class="mt-3 h-1.5 w-full"
            viewBox="0 0 100 6"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect
              width="100"
              height="6"
              rx="3"
              class="fill-current text-n-slate-3"
            />
            <rect
              :width="metric.percent"
              height="6"
              rx="3"
              class="fill-current"
              :class="metric.bar"
            />
          </svg>
          <p
            v-if="metric.hint || metric.percent !== undefined"
            class="mt-1 text-xs text-n-slate-11"
          >
            {{ metric.hint || `${metric.percent}%` }}
          </p>
        </div>
      </article>
    </div>

    <div class="grid min-w-0 grid-cols-1 gap-4 xl:grid-cols-3">
      <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <h3 class="text-sm font-semibold">
          {{ projectText('PROJECT_PROGRESS', 'Progresso do projeto') }}
        </h3>
        <div class="mt-4 flex flex-wrap items-center justify-center gap-5">
          <div class="relative size-36 shrink-0">
            <svg
              viewBox="0 0 120 120"
              class="size-full -rotate-90"
              aria-hidden="true"
            >
              <circle
                cx="60"
                cy="60"
                r="48"
                fill="none"
                stroke="currentColor"
                stroke-width="13"
                class="text-n-slate-3"
              />
              <circle
                cx="60"
                cy="60"
                r="48"
                fill="none"
                stroke="currentColor"
                stroke-width="13"
                pathLength="100"
                :stroke-dasharray="`${progress} 100`"
                class="text-n-teal-9"
              />
            </svg>
            <div
              class="absolute inset-0 flex flex-col items-center justify-center"
            >
              <strong class="text-3xl font-semibold">{{ progress }}%</strong
              ><span class="text-xs text-n-slate-11">{{
                projectText('COMPLETION', 'Conclusão')
              }}</span>
            </div>
          </div>
          <ul class="min-w-[150px] flex-1 space-y-3 text-xs">
            <li
              v-for="item in series"
              :key="item.key"
              class="flex items-center gap-2"
            >
              <span
                class="size-2 shrink-0 rounded-full bg-current"
                :class="item.color"
              /><span class="flex-1 text-n-slate-11">{{ item.label }}</span
              ><strong>{{ item.value }} ({{ percentage(item.value) }}%)</strong>
            </li>
          </ul>
        </div>
        <p v-if="!total" class="mt-3 text-xs text-n-slate-11">
          {{
            projectText(
              'NO_TASKS_PROGRESS',
              'Adicione tarefas para acompanhar o progresso.'
            )
          }}
        </p>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="text-sm font-semibold">
            {{ projectText('TASKS_BY_STATUS', 'Tarefas por situação') }}
          </h3>
          <span class="text-xs text-n-slate-11"
            >{{ total }} {{ projectText('TASKS_LABEL', 'tarefas') }}</span
          >
        </div>
        <div
          class="mt-5 flex h-40 items-end gap-3 border-b border-n-weak px-2"
          role="img"
          :aria-label="
            series.map(item => `${item.label}: ${item.value}`).join('; ')
          "
        >
          <div
            v-for="item in series"
            :key="item.key"
            class="flex h-full min-w-0 flex-1 flex-col justify-end text-center"
          >
            <svg
              class="h-36 w-full overflow-visible"
              viewBox="0 0 60 140"
              preserveAspectRatio="none"
              aria-hidden="true"
            >
              <rect
                x="6"
                :y="130 - (item.value / chartMaximum) * 105"
                width="48"
                :height="(item.value / chartMaximum) * 105"
                rx="5"
                class="fill-current"
                :class="item.color"
              />
              <text
                x="30"
                :y="121 - (item.value / chartMaximum) * 105"
                text-anchor="middle"
                class="fill-current text-xs font-semibold text-n-slate-12"
              >
                {{ item.value }}
              </text>
            </svg>
          </div>
        </div>
        <div
          class="mt-2 grid grid-cols-4 gap-3 text-center text-xs text-n-slate-11"
        >
          <span v-for="item in series" :key="item.key">{{ item.label }}</span>
        </div>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <div class="flex items-center justify-between gap-2">
          <h3 class="text-sm font-semibold">
            {{ projectText('PROJECT_MILESTONES', 'Marcos do projeto') }}
          </h3>
          <button
            class="text-xs text-n-blue-11 hover:underline"
            @click="emit('navigate', 'planning')"
          >
            {{ projectText('VIEW_PLANNING', 'Ver planejamento') }}
          </button>
        </div>
        <ol v-if="milestones.length" class="mt-5 space-y-4">
          <li
            v-for="milestone in milestones.slice(0, 5)"
            :key="milestone.id"
            class="flex items-center gap-3 text-xs"
          >
            <span
              class="flex size-6 shrink-0 items-center justify-center rounded-full"
              :class="
                milestone.status === 'completed'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-slate-3 text-n-slate-10'
              "
              aria-hidden="true"
              ><span
                :class="
                  milestone.status === 'completed'
                    ? 'i-lucide-check size-4'
                    : 'i-lucide-flag size-3.5'
                "
            /></span>
            <span class="min-w-0 flex-1 font-medium">{{ milestone.name }}</span
            ><time
              :datetime="milestone.due_on || undefined"
              class="text-n-slate-11"
              >{{ formatDate(milestone.due_on) }}</time
            >
          </li>
        </ol>
        <div
          v-else
          class="flex min-h-40 flex-col items-center justify-center gap-3 text-center text-n-slate-11"
        >
          <span
            class="i-lucide-flag size-8 text-n-slate-8"
            aria-hidden="true"
          />
          <p class="text-sm">
            {{ projectText('NO_MILESTONES', 'Nenhum marco cadastrado.') }}
          </p>
          <button
            class="text-xs text-n-blue-11 hover:underline"
            @click="emit('navigate', 'planning')"
          >
            {{ projectText('OPEN_PLANNING', 'Abrir planejamento') }}
          </button>
        </div>
      </section>
    </div>

    <div
      v-if="budgetCards.length"
      class="grid grid-cols-1 gap-3 sm:grid-cols-2 2xl:grid-cols-4"
    >
      <button
        v-for="item in budgetCards"
        :key="item.key"
        class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 text-left hover:border-n-blue-7"
        @click="emit('navigate', 'hours')"
      >
        <span
          class="flex size-11 shrink-0 items-center justify-center rounded-xl [&_span]:size-5"
          :class="item.color"
          aria-hidden="true"
          ><span :class="item.icon"
        /></span>
        <span class="min-w-0"
          ><strong class="block text-lg font-semibold">{{ item.value }}</strong
          ><span class="block text-xs text-n-slate-11">{{ item.label }}</span
          ><span class="mt-1 block text-xs text-n-slate-11">{{
            item.hint
          }}</span></span
        >
      </button>
    </div>

    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <section class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <div class="mb-3 flex items-center justify-between gap-2">
          <h3 class="text-sm font-semibold">
            {{ projectText('RECENT_TASKS', 'Tarefas recentes') }}
          </h3>
          <button
            class="rounded bg-n-blue-2 px-2 py-1 text-xs text-n-blue-11"
            @click="emit('navigate', 'board')"
          >
            {{ projectText('VIEW_ALL_TASKS', 'Ver todas') }}
          </button>
        </div>
        <button
          v-for="task in recentTasks"
          :key="task.id"
          class="flex w-full items-center gap-3 border-b border-n-weak py-3 text-left last:border-0 hover:bg-n-slate-2"
          @click="emit('openTask', task)"
        >
          <span
            class="flex size-7 shrink-0 items-center justify-center rounded-full"
            :class="taskTone(task)"
            aria-hidden="true"
            ><span
              class="size-4"
              :class="
                task.status === 'completed'
                  ? 'i-lucide-check'
                  : 'i-lucide-clipboard-list'
              "
          /></span>
          <span class="min-w-0 flex-1"
            ><strong class="block truncate text-xs">{{ task.title }}</strong
            ><span class="block truncate text-xs text-n-slate-11">{{
              task.assignee?.name ||
              projectText('UNASSIGNED', 'Sem responsável')
            }}</span></span
          >
          <span
            class="max-w-[100px] rounded px-2 py-1 text-center text-xs"
            :class="taskTone(task)"
            >{{ projectTaskStatuses[task.status] || task.status }}</span
          >
        </button>
        <p
          v-if="!recentTasks.length"
          class="py-10 text-center text-sm text-n-slate-11"
        >
          {{ projectText('NO_TASKS', 'Nenhuma tarefa cadastrada.') }}
        </p>
      </section>

      <section class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <div class="mb-3 flex items-center justify-between gap-2">
          <h3 class="text-sm font-semibold">
            {{ projectText('UPCOMING_MILESTONES_SHORT', 'Próximos marcos') }}
          </h3>
          <button
            class="rounded bg-n-blue-2 px-2 py-1 text-xs text-n-blue-11"
            @click="emit('navigate', 'planning')"
          >
            {{ projectText('VIEW_SCHEDULE', 'Ver cronograma') }}
          </button>
        </div>
        <div
          v-for="milestone in upcoming.slice(0, 4)"
          :key="milestone.id"
          class="flex items-center gap-3 border-b border-n-weak py-3 last:border-0"
        >
          <span
            class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-violet-3 text-n-violet-11"
            aria-hidden="true"
            ><span class="i-lucide-calendar-check size-4" /></span
          ><strong class="min-w-0 flex-1 text-xs">{{ milestone.name }}</strong
          ><time :datetime="milestone.due_on" class="text-xs text-n-slate-11">{{
            formatDate(milestone.due_on)
          }}</time>
        </div>
        <p
          v-if="!upcoming.length"
          class="py-10 text-center text-sm text-n-slate-11"
        >
          {{
            projectText(
              'NO_UPCOMING_MILESTONES',
              'Nenhum marco aberto com prazo definido.'
            )
          }}
        </p>
      </section>

      <section class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <div class="mb-3 flex items-center justify-between gap-2">
          <h3 class="text-sm font-semibold">
            {{ projectText('RECENT_ACTIVITY', 'Atividade recente') }}
          </h3>
          <button
            v-if="project.recent_activity?.length > 4"
            class="rounded bg-n-blue-2 px-2 py-1 text-xs text-n-blue-11"
            :aria-expanded="showAllActivity"
            @click="showAllActivity = !showAllActivity"
          >
            {{
              showAllActivity
                ? projectText('SHOW_LESS', 'Ver menos')
                : projectText('VIEW_ALL_ACTIVITY', 'Ver todas')
            }}
          </button>
        </div>
        <div class="max-h-96 overflow-y-auto">
          <article
            v-for="event in activity"
            :key="event.id"
            class="flex gap-3 border-b border-n-weak py-3 last:border-0"
          >
            <span
              class="flex size-7 shrink-0 items-center justify-center rounded-full bg-n-slate-4 text-xs text-n-slate-11"
              aria-hidden="true"
              >{{ initials(event.actor?.name) || '•' }}</span
            >
            <div class="min-w-0 flex-1">
              <strong class="block text-xs">{{
                activityLabel(event.action)
              }}</strong>
              <p class="text-xs text-n-slate-11">
                {{ event.actor?.name || projectText('SYSTEM', 'Sistema') }}
              </p>
              <time
                :datetime="event.created_at"
                class="mt-1 block text-xs text-n-slate-10"
                >{{ formatDate(event.created_at) }}</time
              >
            </div>
          </article>
        </div>
        <p
          v-if="!activity.length"
          class="py-10 text-center text-sm text-n-slate-11"
        >
          {{ projectText('NO_ACTIVITY', 'Nenhuma atividade registrada.') }}
        </p>
      </section>
    </div>
  </div>
</template>
