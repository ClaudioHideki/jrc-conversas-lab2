<script setup>
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
const { enabled: hasCustomerMaster, accountScopedRoute: masterRoute } =
  useCustomerMaster();
import { ref, reactive, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useProjects } from '../../jrcProjects/useProjects';
import {
  request,
  allPages,
  errorMessage,
  routeTo,
  projectStatuses,
  priorities,
  formatDate,
  downloadCsv,
  dateInput,
} from '../api';
import { projectResources } from '../resources';
import {
  filterProjectTasks,
  persistTaskMove,
  projectTaskStatuses,
} from '../../jrcProjects/taskBoard';
import ContactPicker from '../components/ContactPicker.vue';
import TaskEditor from '../components/TaskEditor.vue';
import ProjectPlanning from '../components/ProjectPlanning.vue';
import ProjectHours from '../components/ProjectHours.vue';
import FilesBox from '../components/FilesBox.vue';
import ResourceManager from '../components/ResourceManager.vue';
import OperationsLinks from '../components/OperationsLinks.vue';
const route = useRoute();
const { accountId, status, projectText } = useProjects();
const projectId = computed(() => route.params.projectId);
const ownerOptions = ref([]);
const project = ref(null);
const tasks = ref([]);
const loading = ref(false);
const error = ref('');
const success = ref('');
const busy = ref(false);
const tab = ref('overview');
const taskModal = ref(false);
const selectedTask = ref(null);
const dragging = ref(null);
const q = ref('');
const assignee = ref('');
const boardView = ref('board');
const revision = ref(0);
const taskFilters = reactive({ status: '', priority: '', due: '', label: '' });
const tasksSynced = ref(false);
const labelOptions = computed(() =>
  [...new Set(tasks.value.flatMap(task => task.labels || []))].sort()
);
const settings = reactive({
  name: '',
  description: '',
  status: '',
  priority: 'medium',
  visibility: 'members',
  company_id: null,
  contact_id: null,
  owner_id: null,
  starts_on: '',
  due_on: '',
  acceptance_notes: '',
});
const can = name => project.value?.capabilities?.includes(`projects.${name}`);
const editable = computed(
  () => !['completed', 'canceled'].includes(project.value?.status)
);
const filteredTasks = computed(() =>
  filterProjectTasks(
    tasks.value,
    { ...taskFilters, q: q.value, assignee: assignee.value },
    dateInput(new Date())
  )
);
const orphanedTasks = computed(() =>
  filteredTasks.value.filter(
    task =>
      !project.value?.columns?.some(
        column => column.id === task.board_column_id
      )
  )
);
const columns = computed(() =>
  (project.value?.columns || []).map(column => ({
    ...column,
    tasks: filteredTasks.value.filter(
      task => task.board_column_id === column.id
    ),
    count: tasks.value.filter(task => task.board_column_id === column.id)
      .length,
  }))
);
const tabs = computed(() => [
  ['overview', projectText('OVERVIEW', 'Visão Geral')],
  ['board', 'Execucao'],
  ['planning', 'Planejamento'],
  ['team', 'Equipe'],
  ['hours', 'Horas e orcamento'],
  ['files', 'Arquivos'],
  ['links', projectText('RELATED_ORIGIN', 'Origem / Itens relacionados')],
  ['settings', 'Projeto e aceite'],
]);
const columnSchema = {
  key: 'columns',
  title: 'Colunas do quadro',
  help: 'Nao exclua colunas em uso. O status de uma coluna com tarefas nao pode ser alterado.',
  fields: [
    { key: 'name', label: 'Nome', type: 'text', required: true },
    {
      key: 'status_key',
      label: 'Situacao das tarefas',
      type: 'select',
      required: true,
      choices: {
        backlog: 'A fazer',
        in_progress: 'Em andamento',
        review: 'Em validacao',
        completed: 'Concluido',
        blocked: 'Bloqueado',
        canceled: 'Cancelado',
      },
    },
    { key: 'position', label: 'Ordem', type: 'number', min: 0, default: 4 },
    {
      key: 'wip_limit',
      label: 'Limite de tarefas (vazio = sem limite)',
      type: 'number',
      min: 1,
      default: '',
    },
  ],
};
const hours = minutes =>
  (Number(minutes || 0) / 60).toLocaleString('pt-BR', {
    maximumFractionDigits: 2,
  });
const money = cents =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: project.value?.budget?.currency || 'BRL',
  }).format(Number(cents || 0) / 100);
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
let generation = 0;
let openedQueryTask = null;
async function load({ throwOnError = false } = {}) {
  const n = ++generation;
  if (!status.value?.projects_enabled || !projectId.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  error.value = '';
  tasksSynced.value = false;
  try {
    const [record, list] = await Promise.all([
      request(accountId.value, `projects/projects/${projectId.value}`),
      allPages(accountId.value, `projects/projects/${projectId.value}/tasks`),
    ]);
    if (n !== generation) return;
    project.value = record.data;
    tasks.value = list;
    tasksSynced.value = true;
    for (const field of Object.keys(settings))
      settings[field] = project.value[field] ?? '';
    ownerOptions.value = project.value.members.map(member => member.user);
    if (can('project.transfer')) {
      const options = await request(accountId.value, 'operations/options');
      if (n !== generation) return;
      ownerOptions.value = options.data.users;
    }
    openQueryTask();
  } catch (err) {
    if (n === generation) {
      error.value = errorMessage(err);
      tasksSynced.value = false;
    }
    if (throwOnError) throw err;
  } finally {
    if (n === generation) loading.value = false;
  }
}
watch(
  () => [accountId.value, projectId.value, status.value?.projects_enabled],
  () => {
    project.value = null;
    tasks.value = [];
    ownerOptions.value = [];
    tasksSynced.value = false;
    Object.assign(taskFilters, {
      status: '',
      priority: '',
      due: '',
      label: '',
    });
    q.value = '';
    assignee.value = '';
    tab.value = 'overview';
    taskModal.value = false;
    selectedTask.value = null;
    openedQueryTask = null;
    success.value = '';
    load();
  },
  { immediate: true }
);
function openQueryTask() {
  if (!route.query.taskId || !tasksSynced.value) return;
  const key = `${accountId.value}:${projectId.value}:${route.query.taskId}`;
  if (openedQueryTask === key) return;
  const task = tasks.value.find(
    row => String(row.id) === String(route.query.taskId)
  );
  if (task) {
    openTask(task);
    openedQueryTask = key;
  } else {
    taskModal.value = false;
    error.value = projectText(
      'LINKED_TASK_UNAVAILABLE',
      'Esta tarefa não está mais disponível neste projeto.'
    );
  }
}
watch(
  () => route.query.taskId,
  () => {
    openedQueryTask = null;
    taskModal.value = false;
    openQueryTask();
  }
);
function openTask(task = null) {
  selectedTask.value = task;
  taskModal.value = true;
}
async function move(task, columnId) {
  if (busy.value || !tasksSynced.value || !task.can_move || !editable.value)
    return;
  busy.value = true;
  error.value = '';
  try {
    await persistTaskMove(
      () =>
        request(
          accountId.value,
          `projects/projects/${projectId.value}/tasks/${task.id}/move`,
          {
            method: 'post',
            data: {
              column_id: Number(columnId),
              lock_version: task.lock_version,
            },
          }
        ),
      () => load({ throwOnError: true })
    );
  } catch (err) {
    error.value = Array.isArray(err.errors)
      ? err.errors.map(errorMessage).join(' | ')
      : errorMessage(err);
  } finally {
    busy.value = false;
    dragging.value = null;
    revision.value += 1;
  }
}
function dragStart(event, task) {
  dragging.value = task.id;
  event.dataTransfer.setData('text/plain', String(task.id));
  event.dataTransfer.effectAllowed = 'move';
}
function drop(event, column) {
  event.preventDefault();
  const task = tasks.value.find(x => x.id === dragging.value);
  if (task) move(task, column.id);
}
async function saveProject() {
  if (busy.value) return;
  if (
    settings.status === 'completed' &&
    !window.confirm(
      'Registrar o aceite e concluir o projeto? Chamados e conversas vinculados permanecerao independentes.'
    )
  )
    return;
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    const values = { ...settings, lock_version: project.value.lock_version };
    if (!hasCustomerMaster.value) delete values.company_id;
    if (!can('project.transfer')) delete values.owner_id;
    await request(accountId.value, `projects/projects/${projectId.value}`, {
      method: 'patch',
      data: { project: values },
    });
    await load();
    success.value =
      'Projeto atualizado. Os registros de origem foram preservados.';
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function changed() {
  revision.value += 1;
  await load();
}
async function exportTasks() {
  try {
    await downloadCsv(
      accountId.value,
      `projects/projects/${projectId.value}/reports/export`,
      `${project.value.key}-tarefas.csv`
    );
  } catch (err) {
    error.value = errorMessage(err);
  }
}
</script>

<template>
  <section class="flex flex-col gap-4">
    <RouterLink
      class="text-n-blue-11 underline"
      :to="routeTo('jrc_projects_list', accountId)"
    >
      ← Projetos
    </RouterLink>
    <div
      v-if="error"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
      role="alert"
    >
      {{ error }}
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
        @click="load"
      >
        Atualizar dados
      </button>
    </div>
    <div
      v-if="success"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3 info"
      role="status"
    >
      {{ success }}
    </div>
    <p v-if="loading && !project" class="p-4 text-n-slate-11" role="status">
      Carregando projeto...
    </p>
    <template v-if="project">
      <header
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
      >
        <div class="flex flex-wrap items-center gap-3 justify-between">
          <div>
            <p class="text-sm text-n-blue-11">{{ project.key }}</p>
            <h1>{{ project.name }}</h1>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <span class="rounded px-2 py-1 text-xs border border-n-weak">{{
              projectStatuses[project.status]
            }}</span><span class="rounded px-2 py-1 text-xs border border-n-weak">{{
              priorities[project.priority]
            }}</span><button
              v-if="can('project.update')"
              class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
              @click="tab = 'settings'"
            >
              {{ projectText('EDIT_PROJECT', 'Editar projeto') }}</button><button
              v-if="can('report.export')"
              class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
              @click="exportTasks"
            >
              Exportar tarefas
            </button>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-3 justify-between">
          <p class="text-n-slate-11 text-sm">
            {{ project.contact?.name || 'Projeto interno' }} · Responsavel:
            {{ project.owner?.name }} · Entrega:
            {{ formatDate(project.due_on) }}
          </p>
          <strong>{{ project.progress }}% · {{ project.tasks_completed }}/{{
              project.tasks_total
            }}
            tarefas concluidas</strong>
        </div>
        <nav
          class="flex gap-3 overflow-x-auto py-3 [&_button]:rounded-lg [&_button]:px-3 [&_button]:py-2 [&_a]:px-3 [&_a]:py-2 [&_.active]:bg-n-blue-9 [&_.active]:text-white [&_.router-link-exact-active]:text-n-blue-11"
        >
          <button
            v-for="item in tabs"
            :key="item[0]"
            :class="{ active: tab === item[0] }"
            @click="tab = item[0]"
          >
            {{ item[1] }}
          </button>
        </nav>
      </header>
      <section
        v-if="tab === 'overview' && project.overview"
        class="flex flex-col gap-4"
      >
        <h2>{{ projectText('OVERVIEW', 'Visão Geral') }}</h2>
        <div class="grid grid-cols-2 xl:grid-cols-4 gap-3">
          <div
            class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
          >
            <strong>{{ project.tasks_total }}</strong><span>{{ projectText('TASKS_TOTAL', 'Total de tarefas') }}</span>
          </div>
          <div
            class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
          >
            <strong>{{ project.tasks_completed }}</strong><span>{{
              projectText('TASKS_COMPLETED', 'Tarefas concluídas')
            }}</span>
          </div>
          <div
            class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
          >
            <strong>{{ project.overview.overdue_tasks }}</strong><span>{{ projectText('OVERDUE', 'Atrasadas') }}</span>
          </div>
          <div
            class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
          >
            <strong>{{ project.overview.team_size }}</strong><span>{{
              projectText('PROJECT_TEAM', 'Equipe (inclui proprietário)')
            }}</span>
          </div>
          <div
            class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
          >
            <strong>{{ hours(project.overview.estimated_minutes) }} h</strong><span>{{
              projectText('ESTIMATED_HOURS', 'Horas previstas')
            }}</span>
          </div>
          <div
            class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
          >
            <strong>{{ hours(project.overview.worked_minutes) }} h</strong><span>{{
              projectText(
                'WORKED_HOURS',
                'Horas registradas (enviadas ou aprovadas)'
              )
            }}</span>
          </div>
        </div>
        <section
          v-if="can('budget.view') && project.budget"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
        >
          <h3>{{ projectText('BUDGET', 'Orçamento e custo de horas') }}</h3>
          <div class="grid grid-cols-2 xl:grid-cols-4 gap-3">
            <div
              class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
            >
              <strong>{{ money(project.budget.planned_cents) }}</strong><span>{{ projectText('BUDGET_PLANNED', 'Previsto') }}</span>
            </div>
            <div
              class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
            >
              <strong>{{ money(project.budget.committed_cents) }}</strong><span>{{
                projectText('BUDGET_COMMITTED', 'Comprometido informado')
              }}</span>
            </div>
            <div
              class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
            >
              <strong>{{ money(project.budget.actual_cents) }}</strong><span>{{
                projectText('BUDGET_ACTUAL', 'Custo das horas aprovadas')
              }}</span>
            </div>
            <div
              class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
            >
              <strong>{{ money(project.budget.remaining_cents) }}</strong><span>{{
                projectText(
                  'BUDGET_REMAINING',
                  'Saldo previsto menos realizado'
                )
              }}</span>
            </div>
          </div>
          <p class="text-sm text-n-slate-11">
            {{
              projectText(
                'BUDGET_HELP',
                'O custo considera horas aprovadas com custo/hora. Não representa despesas externas, faturamento ou lucro.'
              )
            }}
          </p>
        </section>
        <section
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
        >
          <h3>
            {{ projectText('UPCOMING_MILESTONES', 'Próximos marcos abertos') }}
          </h3>
          <div
            v-for="milestone in project.overview.upcoming_milestones"
            :key="milestone.id"
            class="flex flex-wrap items-center gap-3 justify-between"
          >
            <strong>{{ milestone.name }}</strong><span>{{ formatDate(milestone.due_on) }}</span>
          </div>
          <p
            v-if="!project.overview.upcoming_milestones.length"
            class="text-n-slate-11 text-sm"
          >
            {{
              projectText(
                'NO_UPCOMING_MILESTONES',
                'Nenhum marco aberto com prazo definido.'
              )
            }}
          </p>
          <button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
            @click="tab = 'planning'"
          >
            {{ projectText('OPEN_PLANNING', 'Abrir planejamento') }}
          </button>
        </section>
        <section
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
        >
          <h3>{{ projectText('RECENT_ACTIVITY', 'Atividade recente') }}</h3>
          <article
            v-for="event in project.recent_activity"
            :key="event.id"
            class="flex flex-wrap items-center gap-3 justify-between"
          >
            <div>
              <strong>{{ activityLabel(event.action) }}</strong>
              <p class="text-n-slate-11 text-sm">
                {{ event.actor?.name || projectText('SYSTEM', 'Sistema') }}
              </p>
            </div>
            <time :datetime="event.created_at">{{
              formatDate(event.created_at)
            }}</time>
          </article>
          <p
            v-if="!project.recent_activity.length"
            class="text-n-slate-11 text-sm"
          >
            {{ projectText('NO_ACTIVITY', 'Nenhuma atividade registrada.') }}
          </p>
        </section>
      </section>
      <section v-if="tab === 'board'" class="flex flex-col gap-4">
        <div class="flex flex-wrap items-center gap-3 justify-between">
          <div class="flex flex-wrap items-center gap-3">
            <input
              v-model="q"
              class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[270px]"
              placeholder="Filtrar tarefas"
              aria-label="Filtrar tarefas"
            /><select
              v-model="assignee"
              class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[220px]"
              aria-label="Filtrar por responsavel"
            >
              <option value="">Todos os responsaveis</option>
              <option
                v-for="member in project.members"
                :key="member.user_id"
                :value="member.user_id"
              >
                {{ member.user.name }}
              </option></select><select
              v-model="taskFilters.status"
              class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[200px]"
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
              </option></select><select
              v-model="taskFilters.priority"
              class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[200px]"
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
              </option></select><select
              v-model="taskFilters.due"
              class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[200px]"
              :aria-label="projectText('DUE_FILTER', 'Prazo')"
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
              <option value="none">
                {{ projectText('NO_DATE', 'Sem prazo') }}
              </option></select><select
              v-model="taskFilters.label"
              class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[200px]"
              :aria-label="projectText('LABEL', 'Etiqueta')"
            >
              <option value="">
                {{ projectText('ALL_LABELS', 'Todas as etiquetas') }}
              </option>
              <option v-for="label in labelOptions" :key="label" :value="label">
                {{ label }}
              </option></select><button
              class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
              @click="boardView = boardView === 'board' ? 'list' : 'board'"
            >
              {{ boardView === 'board' ? 'Ver lista' : 'Ver quadro' }}
            </button>
          </div>
          <button
            v-if="can('task.create') && editable && tasksSynced"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed bg-n-blue-9 text-white"
            @click="openTask()"
          >
            Nova tarefa
          </button>
        </div>
        <p v-if="!editable" class="text-sm text-n-slate-11">
          Este projeto esta concluido ou cancelado. Reabra-o em Projeto e aceite
          para alterar tarefas.
        </p>
        <p
          v-if="orphanedTasks.length"
          class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3 info"
        >
          Existem tarefas sem coluna valida. Elas estao na lista abaixo e podem
          ser movidas para uma coluna existente.
        </p>
        <p v-if="!tasksSynced && !loading" class="text-sm text-n-slate-11">
          {{
            projectText(
              'TASK_STATE_UNAVAILABLE',
              'Não foi possível atualizar o quadro. Atualize os dados antes de mover tarefas.'
            )
          }}
        </p>
        <div
          v-if="boardView === 'board'"
          :key="`board-${revision}`"
          class="grid grid-flow-col auto-cols-[minmax(245px,1fr)] gap-4 overflow-x-auto items-start pb-3"
        >
          <section
            v-for="column in columns"
            :key="column.id"
            class="p-3 bg-n-background border border-n-weak rounded-xl min-h-[260px]"
            @dragover.prevent
            @drop="drop($event, column)"
          >
            <header class="flex flex-wrap items-center gap-3 justify-between">
              <h3>{{ column.name }}</h3>
              <span class="rounded px-2 py-1 text-xs border border-n-weak">{{ column.count
                }}{{ column.wip_limit ? ` / ${column.wip_limit}` : '' }}</span>
            </header>
            <article
              v-for="task in column.tasks"
              :key="task.id"
              class="bg-n-solid-1 border border-n-weak rounded-lg p-3 mt-3 hover:border-n-blue-9 [&[draggable=true]]:cursor-grab [&_p]:my-2"
              :draggable="task.can_move && editable && tasksSynced && !busy"
              @dragstart="dragStart($event, task)"
              @dragend="dragging = null"
            >
              <button
                class="text-left font-semibold text-n-slate-12"
                @click="openTask(task)"
              >
                {{ task.title }}
              </button>
              <p>
                <span class="rounded px-2 py-1 text-xs border border-n-weak">{{
                  priorities[task.priority]
                }}</span>
              </p>
              <p class="text-n-slate-11 text-sm">
                {{ task.assignee?.name || 'Sem responsavel' }}
              </p>
              <p class="text-n-slate-11 text-sm">
                Prazo: {{ formatDate(task.due_on) }}
              </p>
              <p class="flex flex-wrap items-center gap-3">
                <span
                  v-for="label in task.labels"
                  :key="label"
                  class="rounded px-2 py-1 text-xs border border-n-weak"
                  >{{ label }}</span>
              </p>
              <label
                v-if="task.can_move && editable"
                class="flex flex-col gap-1 min-w-0"
                ><span>Mover para</span><select
                  :value="task.board_column_id"
                  :disabled="busy || !tasksSynced"
                  @change="move(task, $event.target.value)"
                >
                  <option
                    v-for="destination in project.columns"
                    :key="destination.id"
                    :value="destination.id"
                  >
                    {{ destination.name }}
                  </option>
                </select></label>
            </article>
            <p v-if="!column.tasks.length" class="text-n-slate-11 text-sm pt-4">
              Nenhuma tarefa neste filtro.
            </p>
          </section>
        </div>
        <div
          v-if="boardView === 'list' || orphanedTasks.length"
          :key="`list-${revision}`"
          class="overflow-x-auto"
        >
          <table
            class="w-full text-sm text-left [&_th]:p-3 [&_td]:p-3 [&_td]:border-t [&_td]:border-n-weak"
          >
            <thead>
              <tr>
                <th>Tarefa</th>
                <th>Responsavel</th>
                <th>{{ projectText('TASK_STATUS', 'Situação') }}</th>
                <th>{{ projectText('PRIORITY', 'Prioridade') }}</th>
                <th>{{ projectText('LABEL', 'Etiqueta') }}</th>
                <th>Prazo</th>
                <th>Coluna</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="task in boardView === 'list'
                  ? filteredTasks
                  : orphanedTasks"
                :key="task.id"
              >
                <td class="wrap">
                  <button
                    class="text-left font-semibold text-n-slate-12"
                    @click="openTask(task)"
                  >
                    {{ task.title }}
                  </button>
                </td>
                <td>{{ task.assignee?.name || 'Nao atribuido' }}</td>
                <td>{{ projectTaskStatuses[task.status] }}</td>
                <td>{{ priorities[task.priority] }}</td>
                <td>{{ (task.labels || []).join(', ') }}</td>
                <td>{{ formatDate(task.due_on) }}</td>
                <td>
                  <select
                    v-if="task.can_move && editable"
                    class="rounded border border-n-weak bg-n-solid-1 p-2"
                    :value="task.board_column_id"
                    :disabled="busy || !tasksSynced"
                    @change="move(task, $event.target.value)"
                  >
                    <option v-if="!task.board_column_id" value="">
                      Sem coluna
                    </option>
                    <option
                      v-for="column in project.columns"
                      :key="column.id"
                      :value="column.id"
                    >
                      {{ column.name }}
                    </option></select><span v-else>{{
                    project.columns.find(x => x.id === task.board_column_id)
                      ?.name || 'Sem coluna'
                  }}</span>
                </td>
              </tr>
              <tr v-if="!filteredTasks.length">
                <td colspan="7" class="p-6 text-center text-n-slate-11">
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
      </section>
      <ProjectPlanning
        v-else-if="tab === 'planning'"
        :key="project.id"
        :project="project"
        :tasks="tasks"
        @changed="changed"
        @open-task="openTask"
      />
      <section v-else-if="tab === 'team'" class="flex flex-col gap-4">
        <aside class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <h3>
            {{ projectText('OWNER', 'Proprietário do projeto') }}:
            {{ project.owner.name }}
          </h3>
          <p class="text-n-slate-11 text-sm">
            {{
              projectText(
                'TEAM_OWNER_HELP',
                'O proprietário é protegido nesta tela. Transfira a responsabilidade em Projeto e aceite.'
              )
            }}
          </p>
        </aside>
        <ResourceManager
          :schema="projectResources[0]"
          :endpoint="`projects/projects/${project.id}/members`"
          :owner-id="project.owner_id"
          :can-edit="can('member.manage')"
          @changed="changed"
        />
      </section>
      <ProjectHours
        v-else-if="tab === 'hours'"
        :key="project.id"
        :project="project"
        :tasks="tasks"
        @changed="changed"
      />
      <FilesBox
        v-else-if="tab === 'files'"
        :endpoint="`projects/projects/${project.id}/files`"
        :can-edit="can('project.update')"
        @changed="changed"
      />
      <OperationsLinks
        v-else-if="tab === 'links'"
        :project-id="project.id"
        :can-link="can('project.update')"
        @changed="changed"
      />
      <section v-else-if="tab === 'settings'" class="flex flex-col gap-4">
        <form
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
          @submit.prevent="saveProject"
        >
          <h3>Projeto e aceite</h3>
          <fieldset
            class="grid grid-cols-1 md:grid-cols-2 gap-4"
            :disabled="!can('project.update') || busy"
          >
            <label class="flex flex-col gap-1 min-w-0 col-span-full"
              ><span>Nome *</span
              ><input v-model="settings.name" required maxlength="240" /></label
            ><label class="flex flex-col gap-1 min-w-0 col-span-full"
              ><span>Escopo</span><textarea v-model="settings.description" />
            </label>
            <div v-if="hasCustomerMaster" class="col-span-full">
              <p class="mb-1 text-sm">Empresa do projeto</p>
              <CompanyPicker
                v-model="settings.company_id"
                :disabled="!can('project.update') || busy"
              /><RouterLink
                v-if="project.company"
                class="text-n-brand underline text-sm"
                :to="
                  masterRoute('jrc_customer_company', {
                    companyId: project.company.id,
                  })
                "
                >Abrir ficha 360</RouterLink
              >
            </div>
            <ContactPicker
              v-model="settings.contact_id"
              :disabled="
                project.contact_locked || !can('project.update') || busy
              "
            />
            <p v-if="project.contact_locked" class="text-sm text-n-slate-11">
              {{
                projectText(
                  'CUSTOMER_LINKED',
                  'O cliente é preservado porque o projeto possui registros de origem vinculados.'
                )
              }}
            </p>
            <label class="flex flex-col gap-1 min-w-0"><span>{{
                projectText('OWNER', 'Responsável pelo projeto')
              }}</span><select
                v-model="settings.owner_id"
                :disabled="!can('project.transfer')"
              >
                <option
                  v-if="
                    !ownerOptions.some(user => user.id === project.owner_id)
                  "
                  :value="project.owner_id"
                >
                  {{ project.owner.name }}
                </option>
                <option
                  v-for="user in ownerOptions"
                  :key="user.id"
                  :value="user.id"
                >
                  {{ user.name }}
                </option></select><small>{{
                projectText(
                  'OWNER_TRANSFER_HELP',
                  'Somente o proprietário atual ou um administrador pode transferir a responsabilidade.'
                )
              }}</small></label><label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('PRIORITY', 'Prioridade') }}</span><select v-model="settings.priority">
                <option
                  v-for="(label, value) in priorities"
                  :key="value"
                  :value="value"
                >
                  {{ label }}
                </option>
              </select></label><label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('VISIBILITY', 'Visibilidade') }}</span><select v-model="settings.visibility">
                <option value="members">
                  {{
                    projectText('MEMBERS', 'Participantes e administradores')
                  }}
                </option>
                <option value="account">
                  {{ projectText('ACCOUNT', 'Toda a conta pode consultar') }}
                </option>
                <option value="private">
                  {{ projectText('PRIVATE', 'Privado') }}
                </option>
              </select></label><label class="flex flex-col gap-1 min-w-0"><span>Inicio</span><input v-model="settings.starts_on" type="date" /></label><label class="flex flex-col gap-1 min-w-0"><span>Prazo</span><input
                v-model="settings.due_on"
                type="date"
                :min="settings.starts_on || undefined" /></label><label class="flex flex-col gap-1 min-w-0"><span>Situacao</span><select v-model="settings.status">
                <option
                  v-for="(label, value) in projectStatuses"
                  :key="value"
                  :value="value"
                >
                  {{ label }}
                </option>
              </select></label><label class="flex flex-col gap-1 min-w-0 col-span-full"><span>Registro do aceite / validacao da entrega</span><textarea
                v-model="settings.acceptance_notes"
                :required="settings.status === 'completed'"
                placeholder="Quem validou a entrega, o que foi aceito e a evidencia correspondente."
              />
            </label>
          </fieldset>
          <p class="text-sm text-n-slate-11">
            Concluir exige que as tarefas estejam concluidas ou canceladas e que
            o aceite esteja registrado. O sistema nao fecha chamados, conversas
            ou negocios automaticamente.
          </p>
          <button
            v-if="can('project.update')"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed bg-n-blue-9 text-white"
            :disabled="busy"
          >
            Salvar projeto
          </button>
        </form>
        <ResourceManager
          v-if="can('board.manage') && editable && project.columns.length"
          :schema="columnSchema"
          :endpoint="`projects/projects/${project.id}/boards/${project.columns[0].board_id}/columns`"
          payload-key="board_column"
          @changed="changed"
        />
      </section>
      <TaskEditor
        v-if="taskModal"
        :key="selectedTask?.id || 'new'"
        :project="project"
        :task="selectedTask"
        :tasks="tasks"
        @open="openTask"
        @close="taskModal = false"
        @changed="changed"
      />
    </template>
  </section>
</template>
