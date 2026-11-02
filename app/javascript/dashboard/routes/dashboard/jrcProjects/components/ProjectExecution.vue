<script setup>
import { computed, ref, watch } from 'vue';
import { useProjects } from '../useProjects';
import {
  projectTaskStatuses,
  filterProjectTasks,
  persistTaskMove,
} from '../taskBoard';
import {
  statusTone,
  priorityTone,
  initials,
  isOverdue,
  taskProgress,
} from '../projectPresentation';
import {
  request,
  errorMessage,
  priorities,
  dateInput,
  formatDate,
} from '../../jrcOperations/api';

const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
  filters: { type: Object, required: true },
  synced: Boolean,
  refresh: { type: Function, required: true },
});
const emit = defineEmits(['openTask', 'filter', 'navigate']);
const { accountId, userId, projectText } = useProjects();
const busy = ref(false);
const error = ref('');
const notice = ref('');
const page = ref(1);
const selected = ref([]);
const bulkColumn = ref('');
const dragging = ref(null);
const today = dateInput();
const pageSize = 20;
const editable = computed(
  () => !['completed', 'canceled'].includes(props.project.status)
);
const filtered = computed(() =>
  filterProjectTasks(props.tasks, props.filters, today)
);
const paged = computed(() =>
  filtered.value.slice((page.value - 1) * pageSize, page.value * pageSize)
);
const labels = computed(() =>
  [...new Set(props.tasks.flatMap(task => task.labels || []))].sort()
);
const columns = computed(() =>
  props.project.columns.map(column => ({
    ...column,
    tasks: filtered.value.filter(task => task.board_column_id === column.id),
    total: props.tasks.filter(task => task.board_column_id === column.id)
      .length,
  }))
);
const orphaned = computed(() =>
  filtered.value.filter(
    task =>
      !props.project.columns.some(column => column.id === task.board_column_id)
  )
);
const visibleRows = computed(() =>
  props.filters.boardView === 'list' ? paged.value : orphaned.value
);
const selectable = computed(() =>
  visibleRows.value.filter(task => task.can_move && editable.value)
);
const allSelected = computed(
  () =>
    selectable.value.length > 0 &&
    selectable.value.every(task => selected.value.includes(task.id))
);
const counts = computed(() =>
  props.tasks.reduce((result, task) => {
    result[task.status] = (result[task.status] || 0) + 1;
    return result;
  }, {})
);
const cards = computed(() => [
  {
    key: '',
    label: projectText('TASKS_TOTAL', 'Total de tarefas'),
    value: props.tasks.length,
    icon: 'i-lucide-list-checks',
    tone: 'text-n-slate-11 bg-n-slate-3',
  },
  {
    key: 'backlog',
    label: projectText('TO_DO', 'A fazer'),
    value: counts.value.backlog || 0,
    icon: 'i-lucide-clipboard-list',
    tone: 'text-n-blue-11 bg-n-blue-3',
  },
  {
    key: 'in_progress',
    label: projectText('IN_PROGRESS', 'Em andamento'),
    value: counts.value.in_progress || 0,
    icon: 'i-lucide-refresh-cw',
    tone: 'text-n-blue-11 bg-n-blue-3',
  },
  {
    key: 'review',
    label: projectText('IN_REVIEW', 'Em validação'),
    value: counts.value.review || 0,
    icon: 'i-lucide-hourglass',
    tone: 'text-amber-600 bg-amber-50 dark:bg-amber-900/20',
  },
  {
    key: 'completed',
    label: projectText('TASKS_COMPLETED', 'Concluídas'),
    value: counts.value.completed || 0,
    icon: 'i-lucide-circle-check',
    tone: 'text-emerald-600 bg-emerald-50 dark:bg-emerald-900/20',
  },
  {
    key: 'overdue',
    label: projectText('OVERDUE', 'Atrasadas'),
    value: props.tasks.filter(task => isOverdue(task, today)).length,
    icon: 'i-lucide-clock-3',
    tone: 'text-n-ruby-11 bg-n-ruby-3',
  },
]);
watch(filtered, () => {
  page.value = 1;
  selected.value = selected.value.filter(id =>
    filtered.value.some(task => task.id === id && task.can_move)
  );
});
function update(key, value) {
  emit('filter', { [key]: value });
}
function filterCard(key) {
  emit('filter', {
    status: key === 'overdue' ? '' : key,
    due: key === 'overdue' ? 'overdue' : '',
  });
}
function toggleAll() {
  selected.value = allSelected.value
    ? selected.value.filter(
        id => !selectable.value.some(task => task.id === id)
      )
    : [
        ...new Set([
          ...selected.value,
          ...selectable.value.map(task => task.id),
        ]),
      ];
}
function toggleTask(id) {
  selected.value = selected.value.includes(id)
    ? selected.value.filter(value => value !== id)
    : [...selected.value, id];
}
const taskUrl = task =>
  'projects/projects/' + props.project.id + '/tasks/' + task.id;
function confirmMove(columnId) {
  const column = props.project.columns.find(
    item => String(item.id) === String(columnId)
  );
  return (
    !['completed', 'canceled'].includes(column?.status_key) ||
    window.confirm(
      projectText(
        'CONFIRM_TASK_TRANSITION',
        'Confirmar esta mudança de situação? As dependências e os limites do quadro serão validados.'
      )
    )
  );
}
async function move(task, columnId, event) {
  if (busy.value || !props.synced || !editable.value || !task.can_move) return;
  if (!confirmMove(columnId)) {
    if (event) event.target.value = task.board_column_id;
    return;
  }
  busy.value = true;
  error.value = '';
  notice.value = '';
  try {
    await persistTaskMove(
      () =>
        request(accountId.value, taskUrl(task) + '/move', {
          method: 'post',
          data: {
            column_id: Number(columnId),
            lock_version: task.lock_version,
          },
        }),
      props.refresh
    );
  } catch (err) {
    if (event) event.target.value = task.board_column_id;
    error.value = Array.isArray(err.errors)
      ? err.errors.map(errorMessage).join(' | ')
      : errorMessage(err);
  } finally {
    busy.value = false;
    dragging.value = null;
  }
}
async function inlineEdit(task, key, event) {
  if (busy.value || !props.synced || !editable.value || !task.can_update)
    return;
  const previous = task[key] ?? '';
  const value = event.target.value;
  if (String(previous) === value) return;
  busy.value = true;
  error.value = '';
  try {
    await persistTaskMove(
      () =>
        request(accountId.value, taskUrl(task), {
          method: 'patch',
          data: {
            task: { [key]: value || null, lock_version: task.lock_version },
          },
        }),
      props.refresh
    );
  } catch (err) {
    event.target.value = previous;
    error.value = Array.isArray(err.errors)
      ? err.errors.map(errorMessage).join(' | ')
      : errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function removeTask(task) {
  if (busy.value || !props.synced || !editable.value || !task.can_delete)
    return;
  if (
    !window.confirm(
      projectText(
        'DELETE_TASK_CONFIRM',
        'Excluir esta tarefa e suas subtarefas? Apontamentos de horas e vínculos com outros registros impedem a exclusão.'
      )
    )
  )
    return;
  busy.value = true;
  error.value = '';
  notice.value = '';
  try {
    await persistTaskMove(
      () =>
        request(accountId.value, taskUrl(task), {
          method: 'delete',
          data: { lock_version: task.lock_version },
        }),
      props.refresh
    );
  } catch (err) {
    error.value = Array.isArray(err.errors)
      ? err.errors.map(errorMessage).join(' | ')
      : errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function bulkMove() {
  if (!bulkColumn.value || busy.value || !props.synced || !editable.value)
    return;
  const columnId = Number(bulkColumn.value);
  const moveAccountId = accountId.value;
  const moves = filtered.value
    .filter(item => selected.value.includes(item.id) && item.can_move)
    .map(task => ({
      path: taskUrl(task) + '/move',
      lockVersion: task.lock_version,
    }));
  if (
    !window.confirm(
      projectText(
        'CONFIRM_BULK_MOVE',
        'Mover as tarefas selecionadas? Cada tarefa será validada individualmente; alterações já concluídas serão preservadas em caso de impedimento.'
      )
    )
  )
    return;
  busy.value = true;
  error.value = '';
  notice.value = '';
  let completed = 0;
  try {
    await persistTaskMove(async () => {
      await moves.reduce(
        (chain, moveRequest) =>
          chain.then(async () => {
            await request(moveAccountId, moveRequest.path, {
              method: 'post',
              data: {
                column_id: columnId,
                lock_version: moveRequest.lockVersion,
              },
            });
            completed += 1;
          }),
        Promise.resolve()
      );
    }, props.refresh);
  } catch (err) {
    error.value = Array.isArray(err.errors)
      ? err.errors.map(errorMessage).join(' | ')
      : errorMessage(err);
  } finally {
    busy.value = false;
    selected.value = [];
    notice.value =
      completed + ' ' + projectText('TASKS_MOVED', 'tarefa(s) movimentada(s).');
  }
}
function dragStart(event, task) {
  dragging.value = task.id;
  event.dataTransfer.setData('text/plain', String(task.id));
  event.dataTransfer.effectAllowed = 'move';
}
function drop(event, column) {
  event.preventDefault();
  const task = props.tasks.find(item => item.id === dragging.value);
  if (task && task.board_column_id !== column.id) move(task, column.id);
}
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 2xl:grid-cols-6">
      <button
        v-for="card in cards"
        :key="card.key"
        class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3 text-left shadow-sm"
        @click="filterCard(card.key)"
      >
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-xl"
          :class="card.tone"
          ><span class="size-5" :class="card.icon" /></span
        ><span
          ><strong class="block text-xl leading-tight">{{ card.value }}</strong
          ><span class="block text-xs text-n-slate-11">{{
            card.label
          }}</span></span
        >
      </button>
    </div>
    <div
      v-if="error"
      class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm"
      role="alert"
    >
      {{ error }}
    </div>
    <p
      v-if="notice"
      class="rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11"
      role="status"
    >
      {{ notice }}
    </p>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div
        class="flex rounded-lg border border-n-weak bg-n-solid-1 p-1"
        :aria-label="projectText('TASK_VIEW', 'Visualização de tarefas')"
      >
        <button
          v-for="view in [
            ['board', 'Kanban', 'i-lucide-columns-3'],
            ['list', projectText('LIST', 'Lista'), 'i-lucide-list'],
          ]"
          :key="view[0]"
          class="flex items-center gap-2 rounded-md px-3 py-1.5 text-sm"
          :class="
            filters.boardView === view[0]
              ? 'bg-n-blue-9 text-white'
              : 'text-n-slate-11'
          "
          :aria-pressed="filters.boardView === view[0]"
          @click="update('boardView', view[0])"
        >
          <span class="size-4" :class="view[2]" />{{ view[1] }}</button
        ><button
          class="flex items-center gap-2 rounded-md px-3 py-1.5 text-sm text-n-slate-11"
          @click="emit('navigate', 'planning')"
        >
          <span class="i-lucide-chart-gantt size-4" />{{
            projectText('GANTT', 'Gantt')
          }}
        </button>
      </div>
      <div class="flex items-center gap-2">
        <button
          class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :class="{
            'text-n-blue-11': String(filters.assignee) === String(userId),
          }"
          @click="
            update(
              'assignee',
              String(filters.assignee) === String(userId) ? '' : String(userId)
            )
          "
        >
          {{ projectText('MY_TASKS', 'Minhas tarefas') }}</button
        ><button
          v-if="
            project.capabilities.includes('projects.task.create') && editable
          "
          class="flex items-center gap-2 rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-medium text-white"
          :disabled="!synced || busy"
          @click="emit('openTask', null)"
        >
          <span class="i-lucide-plus size-4" />{{
            projectText('NEW_TASK', 'Nova tarefa')
          }}
        </button>
      </div>
    </div>
    <div
      class="grid grid-cols-2 gap-2 lg:grid-cols-[minmax(180px,2fr)_repeat(4,minmax(120px,1fr))_auto]"
    >
      <label class="relative col-span-2 lg:col-span-1"
        ><span
          class="i-lucide-search pointer-events-none absolute left-3 top-3 size-4 text-n-slate-10" /><input
          :value="filters.q"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 py-2 pl-9 pr-3 text-sm"
          :placeholder="
            projectText(
              'FILTER_TASKS',
              'Buscar tarefa, responsável ou etiqueta...'
            )
          "
          :aria-label="projectText('FILTER_TASKS', 'Pesquisar tarefas')"
          @input="update('q', $event.target.value)"
      /></label>
      <select
        :value="filters.assignee"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
        :aria-label="projectText('ASSIGNEE', 'Responsável')"
        @change="update('assignee', $event.target.value)"
      >
        <option value="">
          {{ projectText('ALL_OWNERS', 'Todos os responsáveis') }}
        </option>
        <option
          v-for="member in project.members"
          :key="member.user_id"
          :value="String(member.user_id)"
        >
          {{ member.user.name }}
        </option>
      </select>
      <select
        :value="filters.status"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
        :aria-label="projectText('TASK_STATUS', 'Situação da tarefa')"
        @change="update('status', $event.target.value)"
      >
        <option value="">
          {{ projectText('ALL_STATUSES', 'Todas as situações') }}
        </option>
        <option
          v-for="(label, key) in projectTaskStatuses"
          :key="key"
          :value="key"
        >
          {{ label }}
        </option>
      </select>
      <select
        :value="filters.priority"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
        :aria-label="projectText('PRIORITY', 'Prioridade')"
        @change="update('priority', $event.target.value)"
      >
        <option value="">
          {{ projectText('ALL_PRIORITIES', 'Todas as prioridades') }}
        </option>
        <option v-for="(label, key) in priorities" :key="key" :value="key">
          {{ label }}
        </option>
      </select>
      <select
        :value="filters.due"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
        :aria-label="projectText('DUE_FILTER', 'Prazo')"
        @change="update('due', $event.target.value)"
      >
        <option value="">
          {{ projectText('ALL_DATES', 'Todos os prazos') }}
        </option>
        <option value="overdue">
          {{ projectText('OVERDUE', 'Atrasadas') }}
        </option>
        <option value="today">{{ projectText('TODAY', 'Hoje') }}</option>
        <option value="week">
          {{ projectText('NEXT_WEEK', 'Próximos sete dias') }}
        </option>
        <option value="none">{{ projectText('NO_DATE', 'Sem prazo') }}</option>
      </select>
      <button
        class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
        @click="
          emit('filter', {
            q: '',
            assignee: '',
            status: '',
            priority: '',
            due: '',
            label: '',
          })
        "
      >
        {{ projectText('CLEAR_FILTERS', 'Limpar filtros') }}
      </button>
    </div>
    <div
      class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-11"
    >
      <span
        >{{ filtered.length }}/{{ tasks.length }}
        {{ projectText('TASKS', 'tarefas') }}</span
      ><select
        v-if="labels.length"
        :value="filters.label"
        class="max-w-60 rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1"
        :aria-label="projectText('LABEL', 'Etiqueta')"
        @change="update('label', $event.target.value)"
      >
        <option value="">
          {{ projectText('ALL_LABELS', 'Todas as etiquetas') }}
        </option>
        <option v-for="label in labels" :key="label" :value="label">
          {{ label }}
        </option>
      </select>
    </div>
    <p
      v-if="!editable"
      class="rounded-lg bg-n-slate-3 p-3 text-sm text-n-slate-11"
    >
      {{
        projectText(
          'CLOSED_EXECUTION',
          'Projeto concluído ou cancelado. Reabra em Projeto e aceite para alterar as tarefas.'
        )
      }}
    </p>
    <p v-if="!synced" class="text-sm text-n-slate-11" role="status">
      {{
        projectText(
          'TASK_STATE_UNAVAILABLE',
          'Atualizando as tarefas. Aguarde antes de alterar o quadro.'
        )
      }}
    </p>
    <div
      v-if="filters.boardView === 'board'"
      class="grid auto-cols-[minmax(250px,1fr)] grid-flow-col items-start gap-3 overflow-x-auto pb-3"
    >
      <section
        v-for="column in columns"
        :key="column.id"
        class="min-h-72 rounded-xl border border-n-weak bg-n-slate-2 p-3"
        @dragover.prevent
        @drop="drop($event, column)"
      >
        <header class="mb-3 flex items-center justify-between gap-2">
          <div class="flex min-w-0 items-center gap-2">
            <span
              class="size-2 shrink-0 rounded-full"
              :class="
                column.status_key === 'completed'
                  ? 'bg-emerald-500'
                  : column.status_key === 'review'
                    ? 'bg-amber-500'
                    : column.status_key === 'blocked'
                      ? 'bg-n-ruby-9'
                      : 'bg-n-blue-9'
              "
            />
            <h3 class="truncate text-sm font-semibold">{{ column.name }}</h3>
            <span
              class="rounded-md bg-n-solid-1 px-1.5 py-0.5 text-xs text-n-slate-11"
              >{{ column.total
              }}{{ column.wip_limit ? '/' + column.wip_limit : '' }}</span
            >
          </div>
          <button
            v-if="
              project.capabilities.includes('projects.task.create') &&
              editable &&
              column.status_key !== 'completed'
            "
            class="rounded-md p-1 text-n-slate-11 hover:bg-n-slate-4"
            :disabled="!synced || busy"
            :aria-label="
              projectText('NEW_TASK', 'Nova tarefa') + ': ' + column.name
            "
            @click="emit('openTask', null, column.id)"
          >
            <span class="i-lucide-plus block size-4" />
          </button>
        </header>
        <article
          v-for="task in column.tasks"
          :key="task.id"
          class="mb-3 rounded-lg border border-n-weak bg-n-solid-1 p-3 shadow-sm hover:border-n-blue-7"
          :class="{ 'opacity-60': dragging === task.id }"
          :draggable="task.can_move && editable && synced && !busy"
          @dragstart="dragStart($event, task)"
          @dragend="dragging = null"
        >
          <div class="mb-2 flex items-center justify-between gap-2">
            <span class="text-[10px] text-n-slate-10">#{{ task.id }}</span
            ><span
              class="rounded-md px-2 py-0.5 text-[10px] font-medium"
              :class="priorityTone(task.priority)"
              >{{ priorities[task.priority] }}</span
            >
          </div>
          <button
            class="w-full break-words text-left text-sm font-semibold leading-5 hover:text-n-blue-11"
            @click="emit('openTask', task)"
          >
            {{ task.title }}
          </button>
          <div v-if="task.labels?.length" class="mt-2 flex flex-wrap gap-1">
            <button
              v-for="label in task.labels"
              :key="label"
              class="rounded bg-n-blue-2 px-1.5 py-0.5 text-[10px] text-n-blue-11"
              @click="update('label', label)"
            >
              {{ label }}
            </button>
          </div>
          <div class="my-3 flex items-center gap-2 text-xs text-n-slate-11">
            <span
              class="flex size-6 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-[9px] font-semibold text-n-blue-11"
              >{{ initials(task.assignee?.name) }}</span
            ><span class="truncate">{{
              task.assignee?.name ||
              projectText('UNASSIGNED', 'Sem responsável')
            }}</span>
          </div>
          <div
            class="flex items-center justify-between gap-2 text-[11px] text-n-slate-11"
          >
            <span
              class="flex items-center gap-1"
              :class="{ 'text-n-ruby-11': isOverdue(task, today) }"
              ><span class="i-lucide-calendar-days size-3.5" />{{
                formatDate(task.due_on)
              }}</span
            ><span
              v-if="task.checklist_total"
              class="flex shrink-0 items-center gap-1 whitespace-nowrap"
              ><span class="i-lucide-list-checks size-3.5" />{{
                task.checklist_completed
              }}/{{ task.checklist_total }}</span
            ><span class="flex items-center gap-1"
              ><span class="i-lucide-message-circle size-3.5" />{{
                task.comments_count || 0
              }}</span
            ><span class="flex items-center gap-1"
              ><span class="i-lucide-paperclip size-3.5" />{{
                task.attachments_count || 0
              }}</span
            >
          </div>
          <div v-if="task.checklist_total" class="mt-2 flex items-center gap-2">
            <progress
              :value="taskProgress(task)"
              max="100"
              class="h-1.5 w-full overflow-hidden rounded-full accent-n-blue-9 [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9"
              :aria-label="
                projectText('CHECKLIST_PROGRESS', 'Progresso do checklist')
              "
            /><span class="text-[10px] text-n-slate-11"
              >{{ taskProgress(task) }}%</span
            >
          </div>
          <select
            v-if="task.can_move && editable"
            :value="task.board_column_id"
            class="mt-3 w-full rounded-md border border-n-weak bg-n-solid-1 px-2 py-1 text-xs text-n-slate-11"
            :disabled="busy || !synced"
            :aria-label="
              projectText('MOVE_TASK', 'Mover tarefa') + ': ' + task.title
            "
            @change="move(task, $event.target.value, $event)"
          >
            <option
              v-for="destination in project.columns"
              :key="destination.id"
              :value="destination.id"
            >
              {{ destination.name }}
            </option>
          </select>
          <div
            v-if="editable && (task.can_update || task.can_delete)"
            class="mt-2 flex justify-end gap-2"
          >
            <button
              v-if="task.can_update"
              type="button"
              class="rounded-md px-2 py-1 text-xs text-n-blue-11 hover:bg-n-blue-2"
              :disabled="busy || !synced"
              @click="emit('openTask', task)"
            >
              {{ projectText('EDIT', 'Editar') }}
            </button>
            <button
              v-if="task.can_delete"
              type="button"
              class="rounded-md px-2 py-1 text-xs text-n-ruby-11 hover:bg-n-ruby-2"
              :disabled="busy || !synced"
              @click="removeTask(task)"
            >
              {{ projectText('DELETE', 'Excluir') }}
            </button>
          </div>
        </article>
        <p
          v-if="!column.tasks.length"
          class="py-10 text-center text-xs text-n-slate-10"
        >
          {{ projectText('NO_TASKS_COLUMN', 'Nenhuma tarefa nesta coluna.') }}
        </p>
      </section>
    </div>
    <template v-if="filters.boardView === 'list' || orphaned.length">
      <p
        v-if="orphaned.length && filters.boardView !== 'list'"
        class="text-sm text-n-ruby-11"
      >
        {{
          projectText(
            'TASKS_WITHOUT_COLUMN',
            'Tarefas sem coluna válida: selecione uma coluna para reorganizá-las.'
          )
        }}
      </p>
      <div
        v-if="selected.length"
        class="flex flex-wrap items-center gap-3 rounded-lg border border-n-blue-5 bg-n-blue-2 p-3 text-sm"
      >
        <strong
          >{{ selected.length }}
          {{ projectText('SELECTED_TASKS', 'selecionadas') }}</strong
        ><select
          v-model="bulkColumn"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
          :disabled="busy || !synced"
          :aria-label="projectText('DESTINATION_COLUMN', 'Coluna de destino')"
        >
          <option value="">
            {{ projectText('MOVE_TO', 'Mover para...') }}
          </option>
          <option
            v-for="column in project.columns"
            :key="column.id"
            :value="column.id"
          >
            {{ column.name }}
          </option></select
        ><button
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-white disabled:opacity-50"
          :disabled="!bulkColumn || busy || !synced"
          @click="bulkMove"
        >
          {{ projectText('APPLY', 'Aplicar') }}</button
        ><button class="text-n-blue-11" :disabled="busy" @click="selected = []">
          {{ projectText('CANCEL', 'Cancelar') }}
        </button>
      </div>
      <div
        class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1 shadow-sm"
      >
        <table
          class="w-full min-w-[1020px] text-left text-xs [&_th]:px-3 [&_th]:py-3 [&_th]:font-medium [&_td]:border-t [&_td]:border-n-weak [&_td]:px-3 [&_td]:py-3"
        >
          <thead class="bg-n-slate-2 text-n-slate-11">
            <tr>
              <th>
                <input
                  type="checkbox"
                  :checked="allSelected"
                  :disabled="!selectable.length || busy || !synced"
                  :aria-label="
                    projectText(
                      'SELECT_TASK_PAGE',
                      'Selecionar tarefas desta página'
                    )
                  "
                  @change="toggleAll"
                />
              </th>
              <th>{{ projectText('TASK', 'Tarefa') }}</th>
              <th>{{ projectText('ASSIGNEE', 'Responsável') }}</th>
              <th>{{ projectText('TASK_STATUS', 'Situação') }}</th>
              <th>{{ projectText('PRIORITY', 'Prioridade') }}</th>
              <th>{{ projectText('DUE_FILTER', 'Prazo') }}</th>
              <th>{{ projectText('CHECKLIST', 'Checklist') }}</th>
              <th>{{ projectText('LABEL', 'Etiquetas') }}</th>
              <th>{{ projectText('ACTIONS', 'Ações') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="task in visibleRows"
              :key="task.id"
              class="hover:bg-n-slate-2"
            >
              <td>
                <input
                  type="checkbox"
                  :checked="selected.includes(task.id)"
                  :disabled="!task.can_move || !editable || busy || !synced"
                  :aria-label="
                    projectText('SELECT_TASK', 'Selecionar tarefa') +
                    ': ' +
                    task.title
                  "
                  @change="toggleTask(task.id)"
                />
              </td>
              <td class="min-w-56">
                <span class="block text-[10px] text-n-blue-11"
                  >#{{ task.id }}</span
                ><button
                  class="mt-1 max-w-80 text-left font-semibold hover:text-n-blue-11"
                  @click="emit('openTask', task)"
                >
                  {{ task.title }}</button
                ><span
                  v-if="task.parent_id"
                  class="mt-1 block text-[10px] text-n-slate-10"
                  >{{ projectText('SUBTASK', 'Subtarefa') }} #{{
                    task.parent_id
                  }}</span
                >
              </td>
              <td>
                <select
                  v-if="task.can_update && editable"
                  :value="task.assignee_id || ''"
                  class="max-w-40 rounded border border-transparent bg-transparent py-1 hover:border-n-weak"
                  :disabled="busy || !synced"
                  :aria-label="
                    projectText('ASSIGNEE', 'Responsável') + ': ' + task.title
                  "
                  @change="inlineEdit(task, 'assignee_id', $event)"
                >
                  <option value="">
                    {{ projectText('UNASSIGNED', 'Sem responsável') }}
                  </option>
                  <option
                    v-for="member in project.members"
                    :key="member.user_id"
                    :value="member.user_id"
                  >
                    {{ member.user.name }}
                  </option></select
                ><span v-else>{{
                  task.assignee?.name ||
                  projectText('UNASSIGNED', 'Sem responsável')
                }}</span>
              </td>
              <td>
                <select
                  v-if="task.can_move && editable"
                  :value="task.board_column_id"
                  class="max-w-40 rounded-md border border-transparent px-2 py-1 text-xs"
                  :class="statusTone(task.status)"
                  :disabled="busy || !synced"
                  :aria-label="
                    projectText('MOVE_TASK', 'Mover tarefa') + ': ' + task.title
                  "
                  @change="move(task, $event.target.value, $event)"
                >
                  <option v-if="!task.board_column_id" value="">
                    {{ projectText('NO_COLUMN', 'Sem coluna') }}
                  </option>
                  <option
                    v-for="column in project.columns"
                    :key="column.id"
                    :value="column.id"
                  >
                    {{ column.name }}
                  </option></select
                ><span
                  v-else
                  class="inline-flex rounded-md px-2 py-1"
                  :class="statusTone(task.status)"
                  >{{ projectTaskStatuses[task.status] }}</span
                >
              </td>
              <td>
                <select
                  v-if="task.can_update && editable"
                  :value="task.priority"
                  class="rounded-md border border-transparent px-2 py-1 text-xs"
                  :class="priorityTone(task.priority)"
                  :disabled="busy || !synced"
                  :aria-label="
                    projectText('PRIORITY', 'Prioridade') + ': ' + task.title
                  "
                  @change="inlineEdit(task, 'priority', $event)"
                >
                  <option
                    v-for="(label, key) in priorities"
                    :key="key"
                    :value="key"
                  >
                    {{ label }}
                  </option></select
                ><span
                  v-else
                  class="rounded-md px-2 py-1"
                  :class="priorityTone(task.priority)"
                  >{{ priorities[task.priority] }}</span
                >
              </td>
              <td :class="{ 'text-n-ruby-11': isOverdue(task, today) }">
                <input
                  v-if="task.can_update && editable"
                  type="date"
                  :value="task.due_on"
                  :min="task.starts_on || undefined"
                  class="w-32 rounded border border-transparent bg-transparent py-1 text-xs"
                  :disabled="busy || !synced"
                  :aria-label="
                    projectText('DUE_FILTER', 'Prazo') + ': ' + task.title
                  "
                  @change="inlineEdit(task, 'due_on', $event)"
                /><span v-else>{{ formatDate(task.due_on) }}</span>
              </td>
              <td>
                <div
                  v-if="task.checklist_total"
                  class="flex w-24 items-center gap-2"
                >
                  <progress
                    :value="taskProgress(task)"
                    max="100"
                    class="h-1.5 w-16 overflow-hidden rounded-full accent-n-blue-9 [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9"
                    :aria-label="
                      projectText(
                        'CHECKLIST_PROGRESS',
                        'Progresso do checklist'
                      )
                    "
                  /><span>{{ taskProgress(task) }}%</span>
                </div>
                <span v-else class="text-n-slate-9">—</span>
              </td>
              <td>
                <span
                  v-for="label in task.labels"
                  :key="label"
                  class="mr-1 inline-block rounded bg-n-blue-2 px-1.5 py-0.5 text-[10px] text-n-blue-11"
                  >{{ label }}</span
                >
              </td>
              <td>
                <button
                  class="rounded-md p-1.5 text-n-blue-11 hover:bg-n-blue-3"
                  :aria-label="
                    projectText('OPEN_TASK', 'Abrir tarefa') + ': ' + task.title
                  "
                  @click="emit('openTask', task)"
                >
                  <span class="i-lucide-panel-right-open block size-4" />
                </button>
                <button
                  v-if="task.can_delete && editable"
                  type="button"
                  class="rounded-md p-1.5 text-n-ruby-11 hover:bg-n-ruby-2"
                  :disabled="busy || !synced"
                  :aria-label="
                    projectText('DELETE_TASK', 'Excluir tarefa') +
                    ': ' +
                    task.title
                  "
                  :title="projectText('DELETE_TASK', 'Excluir tarefa')"
                  @click="removeTask(task)"
                >
                  <span class="i-lucide-trash-2 block size-4" />
                </button>
              </td>
            </tr>
            <tr v-if="!visibleRows.length">
              <td colspan="9" class="py-10 text-center text-sm text-n-slate-11">
                {{
                  projectText(
                    'TASK_LIST_EMPTY',
                    'Nenhuma tarefa corresponde aos filtros.'
                  )
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer
        v-if="filters.boardView === 'list' && filtered.length > pageSize"
        class="flex items-center justify-end gap-3 text-sm"
      >
        <button
          class="rounded-lg border border-n-weak px-3 py-1.5 disabled:opacity-40"
          :disabled="page === 1"
          @click="page -= 1"
        >
          {{ projectText('PREVIOUS', 'Anterior') }}</button
        ><span>{{ page }}/{{ Math.ceil(filtered.length / pageSize) }}</span
        ><button
          class="rounded-lg border border-n-weak px-3 py-1.5 disabled:opacity-40"
          :disabled="page * pageSize >= filtered.length"
          @click="page += 1"
        >
          {{ projectText('NEXT', 'Próxima') }}
        </button>
      </footer>
    </template>
  </section>
</template>
