<script setup>
import { computed, ref } from 'vue';
import { useProjects } from '../useProjects';
import { projectTimeline } from '../planningProjection';
import { dateInput, formatDate, priorities } from '../../jrcOperations/api';
import { filterProjectTasks, projectTaskStatuses } from '../taskBoard';
import { taskProgress } from '../projectPresentation';

const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
  filteredTasks: { type: Array, default: null },
  filters: { type: Object, default: null },
  milestones: { type: Array, default: () => [] },
  dependencies: { type: Array, default: () => [] },
});
const emit = defineEmits(['openTask', 'filter']);
const { projectText } = useProjects();
const localFilters = ref({ q: '', status: '', assignee: '', priority: '' });
const filterModel = key =>
  computed({
    get: () => (props.filters ? props.filters[key] : localFilters.value[key]),
    set: value => {
      if (props.filters) emit('filter', { [key]: value });
      else localFilters.value[key] = value;
    },
  });
const query = filterModel('q');
const status = filterModel('status');
const assignee = filterModel('assignee');
const priority = filterModel('priority');
const scale = ref('week');
const collapsed = ref(new Set());
const chart = ref(null);
const dayNumber = value => Date.parse(`${value}T12:00:00Z`) / 86400000;
const today = dayNumber(dateInput());
const rowHeight = 56;
const headerHeight = 58;
const projection = computed(() =>
  projectTimeline(props.project, props.tasks, props.milestones)
);
const taskById = computed(
  () => new Map(props.tasks.map(task => [task.id, task]))
);
const matchingTasks = computed(() => {
  const source = props.filteredTasks ?? props.tasks;
  return props.filters
    ? source
    : filterProjectTasks(source, localFilters.value, dateInput());
});
const filtered = computed(() =>
  Boolean(
    query.value ||
      status.value ||
      assignee.value ||
      priority.value ||
      props.filters?.due ||
      props.filters?.label ||
      (props.filteredTasks && props.filteredTasks.length !== props.tasks.length)
  )
);
function clearFilters() {
  const empty = {
    q: '',
    status: '',
    assignee: '',
    priority: '',
    due: '',
    label: '',
  };
  if (props.filters) emit('filter', empty);
  else localFilters.value = empty;
}
const rows = computed(() => {
  const source = projection.value.rows;
  const output = [{ ...source[0], depth: 0, children: props.tasks.length > 0 }];
  if (collapsed.value.has(source[0].key) && !filtered.value) return output;
  const allowed = new Set(matchingTasks.value.map(task => task.id));
  matchingTasks.value.forEach(task => {
    const visited = new Set([task.id]);
    let parent = taskById.value.get(task.parent_id);
    while (parent && !visited.has(parent.id)) {
      allowed.add(parent.id);
      visited.add(parent.id);
      parent = taskById.value.get(parent.parent_id);
    }
  });
  const taskRows = source.filter(row => ['task', 'subtask'].includes(row.kind));
  const visited = new Set();
  function append(row, depth) {
    if (visited.has(row.record.id) || !allowed.has(row.record.id)) return;
    visited.add(row.record.id);
    const children = taskRows.filter(
      item => item.record.parent_id === row.record.id
    );
    output.push({ ...row, depth, children: children.length > 0 });
    if (!collapsed.value.has(row.key) || filtered.value)
      children.forEach(child => append(child, depth + 1));
  }
  taskRows
    .filter(row => !taskById.value.has(row.record.parent_id))
    .forEach(row => append(row, 1));
  taskRows
    .filter(row => !visited.has(row.record.id))
    .forEach(row => {
      if (!row.record.parent_id || filtered.value) append(row, 1);
    });
  if (!filtered.value)
    output.push(
      ...source
        .filter(row => row.kind === 'milestone')
        .map(row => ({ ...row, depth: 1 }))
    );
  return output;
});
const range = computed(() => {
  const value = projection.value.range;
  if (!value) return null;
  return {
    start: value.start - 2,
    end: Math.max(value.end + 3, value.start + 13),
  };
});
const span = computed(() =>
  range.value ? range.value.end - range.value.start + 1 : 1
);
const width = computed(() =>
  Math.max(
    620,
    Math.min(14000, span.value * { day: 44, week: 20, month: 6 }[scale.value])
  )
);
const x = day =>
  range.value ? ((day - range.value.start) / span.value) * width.value : 0;
const position = row =>
  row.start === null || row.end === null
    ? null
    : {
        x: x(row.start),
        width: Math.max(
          8,
          ((row.end - row.start + 1) / span.value) * width.value
        ),
      };
const ticks = computed(() => {
  if (!range.value) return [];
  const days = [];
  if (scale.value === 'month') {
    days.push(range.value.start);
    const first = new Date(range.value.start * 86400000);
    first.setUTCDate(1);
    first.setUTCMonth(first.getUTCMonth() + 1);
    while (first.getTime() / 86400000 <= range.value.end) {
      days.push(first.getTime() / 86400000);
      first.setUTCMonth(first.getUTCMonth() + 1);
    }
  } else {
    const step = scale.value === 'day' ? 1 : 7;
    const interval = Math.max(step, Math.ceil(span.value / 100));
    for (let day = range.value.start; day <= range.value.end; day += interval)
      days.push(day);
  }
  return days.map(day => ({
    day,
    x: x(day),
    label: new Date(day * 86400000).toLocaleDateString(
      'pt-BR',
      scale.value === 'month'
        ? { month: 'short', year: '2-digit', timeZone: 'UTC' }
        : { day: '2-digit', month: '2-digit', timeZone: 'UTC' }
    ),
  }));
});
const todayX = computed(() =>
  range.value && today >= range.value.start && today <= range.value.end
    ? x(today)
    : null
);
const edges = computed(() =>
  props.dependencies.flatMap(edge => {
    const from = rows.value.findIndex(
      row =>
        ['task', 'subtask'].includes(row.kind) &&
        row.record.id === edge.predecessor_id
    );
    const to = rows.value.findIndex(
      row =>
        ['task', 'subtask'].includes(row.kind) &&
        row.record.id === edge.successor_id
    );
    if (from < 0 || to < 0) return [];
    const fromPosition = position(rows.value[from]);
    const toPosition = position(rows.value[to]);
    if (!fromPosition || !toPosition) return [];
    const startX = fromPosition.x + fromPosition.width;
    const endX = toPosition.x;
    const startY = headerHeight + from * rowHeight + rowHeight / 2;
    const endY = headerHeight + to * rowHeight + rowHeight / 2;
    const turn = Math.max(startX + 10, endX - 10);
    return [
      {
        id: edge.id,
        path: `M ${startX} ${startY} H ${turn} V ${endY} H ${endX}`,
        endX,
        endY,
      },
    ];
  })
);
const canCreate = computed(
  () =>
    !['completed', 'canceled'].includes(props.project.status) &&
    props.project.capabilities.includes('projects.task.create')
);
const metrics = computed(() => [
  {
    label: projectText('TASKS_TOTAL', 'Total de tarefas'),
    value: props.tasks.length,
    icon: 'i-lucide-list-todo',
    tone: 'bg-n-slate-3 text-n-slate-11',
  },
  {
    label: projectText('IN_PROGRESS', 'Em andamento'),
    value: props.tasks.filter(task => task.status === 'in_progress').length,
    icon: 'i-lucide-refresh-cw',
    tone: 'bg-n-blue-2 text-n-blue-11',
  },
  {
    label: projectText('TASKS_COMPLETED', 'Tarefas concluídas'),
    value: props.tasks.filter(task => task.status === 'completed').length,
    icon: 'i-lucide-check',
    tone: 'bg-n-teal-2 text-n-teal-11',
  },
  {
    label: projectText('IN_REVIEW', 'Em validação'),
    value: props.tasks.filter(task => task.status === 'review').length,
    icon: 'i-lucide-hourglass',
    tone: 'bg-n-amber-2 text-n-amber-11',
  },
  {
    label: projectText('OVERDUE', 'Atrasadas'),
    value: props.tasks.filter(
      task =>
        task.due_on &&
        dayNumber(task.due_on) < today &&
        !['completed', 'canceled'].includes(task.status)
    ).length,
    icon: 'i-lucide-circle-alert',
    tone: 'bg-n-ruby-2 text-n-ruby-11',
  },
]);
function toggle(row) {
  const value = new Set(collapsed.value);
  if (value.has(row.key)) value.delete(row.key);
  else value.add(row.key);
  collapsed.value = value;
}
function color(row) {
  if (row.kind === 'project') return 'fill-n-blue-9';
  if (row.kind === 'milestone')
    return row.record.status === 'completed'
      ? 'fill-n-teal-9'
      : 'fill-n-blue-9';
  return (
    {
      completed: 'fill-n-teal-9',
      in_progress: 'fill-n-blue-9',
      review: 'fill-n-iris-9',
      blocked: 'fill-n-ruby-9',
      canceled: 'fill-n-slate-7',
    }[row.record.status] || 'fill-n-blue-6'
  );
}
function progress(row) {
  if (row.kind === 'project') return props.project.progress;
  if (row.kind === 'milestone')
    return row.record.status === 'completed' ? 100 : null;
  return taskProgress(row.record);
}
function focusToday() {
  if (chart.value && todayX.value !== null)
    chart.value.scrollLeft = Math.max(
      0,
      (window.innerWidth >= 768 ? 580 : 280) +
        todayX.value -
        chart.value.clientWidth / 2
    );
}
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <div class="grid grid-cols-2 gap-3 xl:grid-cols-5">
      <article
        v-for="metric in metrics"
        :key="metric.label"
        class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
      >
        <span
          class="flex size-11 shrink-0 items-center justify-center rounded-xl"
          :class="metric.tone"
          ><span
            class="pointer-events-none size-5 shrink-0"
            :class="metric.icon"
            aria-hidden="true"
        /></span>
        <div class="min-w-0">
          <strong class="text-2xl font-semibold">{{ metric.value }}</strong>
          <p class="m-0 text-xs text-n-slate-11">{{ metric.label }}</p>
        </div>
      </article>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <label
        class="flex min-w-44 flex-1 items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3"
        ><span class="i-lucide-search size-4 shrink-0 text-n-slate-10" /><input
          v-model="query"
          class="min-w-0 flex-1 border-0 bg-transparent py-2 text-sm outline-none"
          :placeholder="projectText('SEARCH_TASKS', 'Pesquisar tarefa...')"
          :aria-label="projectText('SEARCH_TASKS', 'Pesquisar tarefa...')"
      /></label>
      <select
        v-model="status"
        class="w-auto rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
        :aria-label="projectText('TASK_STATUS', 'Situação da tarefa')"
      >
        <option value="">
          {{ projectText('ALL_STATUSES', 'Todas as situações') }}
        </option>
        <option
          v-for="(label, value) in projectTaskStatuses"
          :key="value"
          :value="value"
        >
          {{ label }}
        </option>
      </select>
      <select
        v-model="assignee"
        class="w-auto rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
        :aria-label="projectText('ASSIGNEE', 'Responsável')"
      >
        <option value="">
          {{ projectText('ALL_ASSIGNEES', 'Todos os responsáveis') }}
        </option>
        <option
          v-for="member in project.members"
          :key="member.user_id"
          :value="member.user_id"
        >
          {{ member.user.name }}
        </option>
      </select>
      <select
        v-model="priority"
        class="w-auto rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
        :aria-label="projectText('PRIORITY', 'Prioridade')"
      >
        <option value="">
          {{ projectText('ALL_PRIORITIES', 'Todas as prioridades') }}
        </option>
        <option
          v-for="(label, value) in priorities"
          :key="value"
          :value="value"
        >
          {{ label }}
        </option>
      </select>
      <button
        v-if="filtered"
        class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-11"
        @click="clearFilters"
      >
        {{ projectText('CLEAR_FILTERS', 'Limpar filtros') }}
      </button>
      <div
        class="flex rounded-lg border border-n-weak bg-n-solid-1 p-1"
        :aria-label="projectText('TIMELINE_SCALE', 'Escala do cronograma')"
      >
        <button
          v-for="item in [
            ['day', projectText('DAY', 'Dia')],
            ['week', projectText('WEEK', 'Semana')],
            ['month', projectText('MONTH', 'Mês')],
          ]"
          :key="item[0]"
          class="rounded-md px-3 py-1 text-xs"
          :class="
            scale === item[0] ? 'bg-n-blue-9 text-white' : 'text-n-slate-11'
          "
          :aria-pressed="scale === item[0]"
          @click="scale = item[0]"
        >
          {{ item[1] }}
        </button>
      </div>
      <button
        class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm disabled:opacity-50"
        :disabled="todayX === null"
        @click="focusToday"
      >
        {{ projectText('TODAY', 'Hoje') }}
      </button>
      <button
        v-if="canCreate"
        class="flex items-center gap-2 rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-medium text-white"
        @click="emit('openTask', null)"
      >
        <span class="i-lucide-plus size-4" />{{
          projectText('NEW_TASK', 'Nova tarefa')
        }}
      </button>
    </div>
    <p
      v-if="filteredTasks && filteredTasks.length !== tasks.length"
      class="m-0 text-xs text-n-blue-11"
    >
      {{
        projectText(
          'SHARED_TASK_FILTERS',
          'Os filtros da Execução também estão aplicados ao cronograma.'
        )
      }}
    </p>
    <div
      v-if="!range"
      class="rounded-xl border border-dashed border-n-weak bg-n-solid-1 p-8 text-center text-sm text-n-slate-11"
    >
      {{
        projectText(
          'TIMELINE_NO_DATES',
          'Os registros ainda não possuem datas previstas.'
        )
      }}
    </div>
    <div
      v-else
      ref="chart"
      class="max-h-[640px] overflow-auto rounded-xl border border-n-weak bg-n-solid-1"
    >
      <div class="flex w-max min-w-full items-start">
        <div
          class="sticky left-0 z-10 w-[280px] shrink-0 bg-n-solid-1 shadow-sm md:w-[580px]"
        >
          <div
            class="grid h-[58px] grid-cols-[minmax(0,1fr)_55px] md:grid-cols-[minmax(0,1fr)_100px_75px_75px_55px] items-center gap-2 border-b border-n-weak bg-n-slate-2 px-3 text-xs font-semibold text-n-slate-11"
          >
            <span>{{ projectText('TASK', 'Tarefa') }}</span
            ><span class="hidden md:block">{{
              projectText('ASSIGNEE', 'Responsável')
            }}</span
            ><span class="hidden md:block">{{
              projectText('START', 'Início')
            }}</span
            ><span class="hidden md:block">{{
              projectText('END', 'Término')
            }}</span
            ><span>{{ projectText('PROGRESS', 'Progresso') }}</span>
          </div>
          <div
            v-for="row in rows"
            :key="row.key"
            class="grid h-14 grid-cols-[minmax(0,1fr)_55px] md:grid-cols-[minmax(0,1fr)_100px_75px_75px_55px] items-center gap-2 border-b border-n-weak px-3 text-xs"
            :class="row.kind === 'project' ? 'bg-n-blue-2/40' : ''"
          >
            <div
              class="flex min-w-0 items-center gap-1"
              :class="row.depth > 1 ? 'pl-6' : row.depth === 1 ? 'pl-3' : ''"
            >
              <button
                v-if="row.children"
                class="flex size-5 shrink-0 items-center justify-center rounded hover:bg-n-slate-3"
                :aria-expanded="!collapsed.has(row.key)"
                :aria-label="`${projectText('EXPAND_COLLAPSE', 'Expandir ou recolher')}: ${row.title}`"
                @click="toggle(row)"
              >
                <span
                  class="size-3"
                  :class="
                    collapsed.has(row.key)
                      ? 'i-lucide-chevron-right'
                      : 'i-lucide-chevron-down'
                  "
                /></button
              ><span v-else class="size-5 shrink-0" />
              <span
                class="size-4 shrink-0"
                :class="
                  row.kind === 'project'
                    ? 'i-lucide-folder text-n-amber-11'
                    : row.kind === 'milestone'
                      ? 'i-lucide-diamond text-n-blue-11'
                      : row.record.status === 'completed'
                        ? 'i-lucide-circle-check text-n-teal-11'
                        : 'i-lucide-circle text-n-slate-10'
                "
              />
              <button
                v-if="['task', 'subtask'].includes(row.kind)"
                class="truncate text-left font-medium hover:text-n-blue-11"
                :title="row.title"
                @click="emit('openTask', row.record)"
              >
                {{ row.title }}</button
              ><strong v-else class="truncate" :title="row.title">{{
                row.title
              }}</strong>
            </div>
            <span
              class="hidden truncate text-n-slate-11 md:block"
              :title="row.record.assignee?.name || row.record.owner?.name"
              >{{
                row.record.assignee?.name || row.record.owner?.name || '—'
              }}</span
            ><span class="hidden md:block">{{
              row.record.starts_on
                ? formatDate(row.record.starts_on).slice(0, 5)
                : '—'
            }}</span
            ><span class="hidden md:block">{{
              row.record.due_on
                ? formatDate(row.record.due_on).slice(0, 5)
                : '—'
            }}</span
            ><span>{{
              progress(row) === null ? '—' : `${progress(row)}%`
            }}</span>
          </div>
        </div>
        <svg
          :width="width"
          :height="headerHeight + rows.length * rowHeight"
          class="shrink-0"
          role="img"
          :aria-label="projectText('TIMELINE', 'Cronograma')"
        >
          <rect :width="width" :height="headerHeight" class="fill-n-slate-2" />
          <g v-for="tick in ticks" :key="tick.day">
            <line
              :x1="tick.x"
              :x2="tick.x"
              y1="0"
              :y2="headerHeight + rows.length * rowHeight"
              class="stroke-n-weak"
            />
            <text :x="tick.x + 6" y="35" class="fill-n-slate-11 text-[11px]">
              {{ tick.label }}
            </text>
          </g>
          <g v-for="(row, index) in rows" :key="row.key">
            <line
              x1="0"
              :x2="width"
              :y1="headerHeight + index * rowHeight"
              :y2="headerHeight + index * rowHeight"
              class="stroke-n-weak"
            />
            <g
              v-if="position(row)"
              :transform="`translate(${position(row).x}, ${headerHeight + index * rowHeight + 16})`"
              :role="
                ['task', 'subtask'].includes(row.kind) ? 'button' : undefined
              "
              :tabindex="['task', 'subtask'].includes(row.kind) ? 0 : undefined"
              :aria-label="row.title"
              class="cursor-pointer outline-none focus:opacity-60"
              @click="
                ['task', 'subtask'].includes(row.kind) &&
                  emit('openTask', row.record)
              "
              @keydown.enter="
                ['task', 'subtask'].includes(row.kind) &&
                  emit('openTask', row.record)
              "
              @keydown.space.prevent="
                ['task', 'subtask'].includes(row.kind) &&
                  emit('openTask', row.record)
              "
            >
              <title>
                {{
                  `${row.title}: ${formatDate(row.record.starts_on || row.record.due_on)} → ${formatDate(row.record.due_on || row.record.starts_on)}`
                }}
              </title>
              <polygon
                v-if="row.kind === 'milestone'"
                points="0,12 10,2 20,12 10,22"
                :class="color(row)"
              />
              <rect
                v-else
                :width="position(row).width"
                height="24"
                rx="5"
                :class="color(row)"
              />
            </g>
            <text
              v-else
              x="12"
              :y="headerHeight + index * rowHeight + 33"
              class="fill-n-slate-10 text-[11px]"
            >
              {{ projectText('NO_DATE', 'Sem prazo') }}
            </text>
          </g>
          <g v-for="edge in edges" :key="edge.id">
            <path
              :d="edge.path"
              fill="none"
              class="stroke-n-slate-10"
              stroke-width="1.25"
            />
            <path
              :d="`M ${edge.endX - 5} ${edge.endY - 3} L ${edge.endX} ${edge.endY} L ${edge.endX - 5} ${edge.endY + 3}`"
              fill="none"
              class="stroke-n-slate-10"
            />
          </g>
          <g v-if="todayX !== null">
            <line
              :x1="todayX"
              :x2="todayX"
              :y1="headerHeight - 8"
              :y2="headerHeight + rows.length * rowHeight"
              stroke-dasharray="4 3"
              class="stroke-n-ruby-9"
              stroke-width="1.5"
            />
            <rect
              :x="todayX - 19"
              y="3"
              width="38"
              height="19"
              rx="4"
              class="fill-n-ruby-9"
            />
            <text
              :x="todayX"
              y="16"
              text-anchor="middle"
              class="fill-white text-[10px]"
            >
              {{ projectText('TODAY', 'Hoje') }}
            </text>
          </g>
        </svg>
      </div>
    </div>
    <p v-if="filtered && !matchingTasks.length" class="text-sm text-n-slate-11">
      {{
        projectText(
          'TASK_LIST_EMPTY',
          'Nenhuma tarefa corresponde a estes filtros.'
        )
      }}
    </p>
    <p class="m-0 text-xs text-n-slate-11">
      {{
        projectText(
          'GANTT_EDIT_HINT',
          'Selecione uma tarefa para consultar os detalhes ou editar as datas. As linhas mostram dependências cadastradas.'
        )
      }}
    </p>
  </section>
</template>
