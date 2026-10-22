<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useProjects } from '../../jrcProjects/useProjects';
import {
  useProjectPreferences,
  statusTone,
  priorityTone,
} from '../../jrcProjects/projectPresentation';
import { filterProjectTasks } from '../../jrcProjects/taskBoard';
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
import ProjectOverview from '../../jrcProjects/components/ProjectOverview.vue';
import ProjectExecution from '../../jrcProjects/components/ProjectExecution.vue';
import ProjectTeam from '../../jrcProjects/components/ProjectTeam.vue';
import ProjectConfiguration from '../../jrcProjects/components/ProjectConfiguration.vue';
import TaskEditor from '../components/TaskEditor.vue';
import ProjectPlanning from '../components/ProjectPlanning.vue';
import ProjectHours from '../components/ProjectHours.vue';
import FilesBox from '../components/FilesBox.vue';
import OperationsLinks from '../components/OperationsLinks.vue';

const route = useRoute();
const router = useRouter();
const { accountId, userId, status, projectText } = useProjects();
const projectId = computed(() => route.params.projectId);
const project = ref(null);
const tasks = ref([]);
const loading = ref(false);
const error = ref('');
const taskModal = ref(false);
const selectedTask = ref(null);
const initialColumnId = ref(null);
const tasksSynced = ref(false);
const exporting = ref(false);
const preferenceKey = computed(
  () =>
    'jrc:projects:execution:' +
    accountId.value +
    ':' +
    userId.value +
    ':' +
    projectId.value
);
const filters = useProjectPreferences(preferenceKey, {
  q: '',
  assignee: '',
  status: '',
  priority: '',
  due: '',
  label: '',
  boardView: 'board',
});
const filteredTasks = computed(() =>
  filterProjectTasks(tasks.value, filters, dateInput())
);
const can = name => project.value?.capabilities?.includes('projects.' + name);
const editable = computed(
  () => !['completed', 'canceled'].includes(project.value?.status)
);
const tabs = computed(() => [
  [
    'overview',
    projectText('OVERVIEW', 'Visão geral'),
    'i-lucide-layout-dashboard',
  ],
  ['board', projectText('EXECUTION', 'Execução'), 'i-lucide-square-check-big'],
  [
    'planning',
    projectText('PLANNING', 'Planejamento'),
    'i-lucide-calendar-days',
  ],
  ['team', projectText('TEAM', 'Equipe'), 'i-lucide-users'],
  [
    'hours',
    projectText('TIME_BUDGET', 'Horas e orçamento'),
    'i-lucide-clock-3',
  ],
  ['files', projectText('FILES', 'Arquivos'), 'i-lucide-folder-open'],
  ['links', projectText('RELATED_ITEMS', 'Relacionados'), 'i-lucide-link'],
  [
    'settings',
    projectText('PROJECT_ACCEPTANCE', 'Projeto e aceite'),
    'i-lucide-settings',
  ],
]);
const tab = computed(() =>
  tabs.value.some(item => item[0] === route.query.tab)
    ? route.query.tab
    : 'overview'
);
let generation = 0;
let openedQueryTask = null;
function openQueryTask() {
  if (
    !route.query.taskId ||
    !tasksSynced.value ||
    openedQueryTask === String(route.query.taskId)
  )
    return;
  const task = tasks.value.find(
    row => String(row.id) === String(route.query.taskId)
  );
  if (task) {
    selectedTask.value = task;
    taskModal.value = true;
    openedQueryTask = String(task.id);
  } else {
    taskModal.value = false;
    error.value = projectText(
      'LINKED_TASK_UNAVAILABLE',
      'Esta tarefa não está mais disponível neste projeto.'
    );
  }
}
async function load({ throwOnError = false } = {}) {
  generation += 1;
  const current = generation;
  if (!status.value?.projects_enabled || !projectId.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  tasksSynced.value = false;
  error.value = '';
  try {
    const [record, list] = await Promise.all([
      request(accountId.value, 'projects/projects/' + projectId.value),
      allPages(
        accountId.value,
        'projects/projects/' + projectId.value + '/tasks'
      ),
    ]);
    if (current !== generation) return;
    project.value = record.data;
    tasks.value = list;
    tasksSynced.value = true;
    openQueryTask();
  } catch (err) {
    if (current === generation) error.value = errorMessage(err);
    if (throwOnError) throw err;
  } finally {
    if (current === generation) loading.value = false;
  }
}
const refresh = () => load({ throwOnError: true });
watch(
  () => [
    accountId.value,
    userId.value,
    projectId.value,
    status.value?.projects_enabled,
  ],
  () => {
    project.value = null;
    tasks.value = [];
    tasksSynced.value = false;
    taskModal.value = false;
    selectedTask.value = null;
    openedQueryTask = null;
    load();
  },
  { immediate: true }
);
function navigate(value) {
  router.push({ query: { ...route.query, tab: value } });
}
function focusTab(event, index) {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  let next = index;
  if (event.key === 'ArrowLeft')
    next = (index + tabs.value.length - 1) % tabs.value.length;
  if (event.key === 'ArrowRight') next = (index + 1) % tabs.value.length;
  if (event.key === 'Home') next = 0;
  if (event.key === 'End') next = tabs.value.length - 1;
  event.currentTarget.parentElement.children[next].focus();
  navigate(tabs.value[next][0]);
}
function openTask(task = null, columnId = null) {
  selectedTask.value = task;
  initialColumnId.value = columnId;
  taskModal.value = true;
  if (task) {
    openedQueryTask = String(task.id);
    router.replace({ query: { ...route.query, taskId: String(task.id) } });
  }
}
function closeTask() {
  taskModal.value = false;
  openedQueryTask = null;
  const query = { ...route.query };
  delete query.taskId;
  router.replace({ query });
}

watch(
  () => route.query.taskId,
  () => {
    if (!route.query.taskId) {
      taskModal.value = false;
      openedQueryTask = null;
    } else openQueryTask();
  }
);
async function exportTasks() {
  if (exporting.value) return;
  exporting.value = true;
  try {
    await downloadCsv(
      accountId.value,
      'projects/projects/' + projectId.value + '/reports/export',
      project.value.key + '-tarefas.csv'
    );
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    exporting.value = false;
  }
}
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <div class="flex items-center gap-2 text-xs">
      <RouterLink
        class="flex items-center gap-1 text-n-blue-11 hover:underline"
        :to="routeTo('jrc_projects_list', accountId)"
      >
        <span class="i-lucide-chevron-left size-3.5" />{{
          projectText('PROJECTS', 'Projetos')
        }} </RouterLink
      ><span v-if="project" class="text-n-slate-9">/</span
      ><span v-if="project" class="text-n-slate-11">{{ project.key }}</span>
    </div>
    <div
      v-if="error"
      class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm"
      role="alert"
    >
      {{ error
      }}<button class="ml-3 text-n-blue-11 underline" @click="load">
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <div
      v-if="loading && !project"
      class="space-y-4"
      role="status"
      :aria-label="projectText('LOADING_PROJECT', 'Carregando projeto')"
    >
      <div class="h-28 animate-pulse rounded-xl bg-n-slate-3" />
      <div class="grid grid-cols-3 gap-3">
        <div
          v-for="index in 6"
          :key="index"
          class="h-24 animate-pulse rounded-xl bg-n-slate-3"
        />
      </div>
    </div>
    <template v-if="project">
      <header class="flex flex-col gap-4 border-b border-n-weak pb-0">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-3">
              <h1 class="break-words text-2xl font-semibold tracking-tight">
                {{ project.name }}
              </h1>
              <span
                class="rounded-md px-2 py-1 text-xs font-medium"
                :class="statusTone(project.status)"
                >{{ projectStatuses[project.status] }}</span
              ><span
                class="rounded-md px-2 py-1 text-xs font-medium"
                :class="priorityTone(project.priority)"
                >{{ priorities[project.priority] }}</span
              >
            </div>
            <p class="mt-2 text-xs text-n-slate-11">
              {{
                project.contact?.name ||
                projectText('INTERNAL_PROJECT', 'Projeto interno')
              }}
              · {{ projectText('OWNER', 'Responsável') }}:
              {{ project.owner?.name }} ·
              {{ projectText('DELIVERY', 'Entrega') }}:
              {{ formatDate(project.due_on) }}
            </p>
          </div>
          <div class="flex flex-col items-end gap-3">
            <div class="flex gap-2">
              <button
                v-if="can('project.update')"
                class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs"
                @click="navigate('settings')"
              >
                <span class="i-lucide-pencil size-3.5" />{{
                  projectText('EDIT_PROJECT', 'Editar projeto')
                }}</button
              ><button
                v-if="can('report.export')"
                class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs"
                :disabled="exporting"
                @click="exportTasks"
              >
                <span class="i-lucide-download size-3.5" />{{
                  projectText('EXPORT_TASKS', 'Exportar tarefas')
                }}
              </button>
            </div>
            <div class="w-64 max-w-full">
              <div class="mb-1.5 flex justify-between gap-3 text-xs">
                <strong>{{ project.progress }}%</strong
                ><span
                  >{{ project.tasks_completed }}/{{ project.tasks_total }}
                  {{
                    projectText('COMPLETED_TASKS_LABEL', 'tarefas concluídas')
                  }}</span
                >
              </div>
              <progress
                :value="project.progress"
                max="100"
                class="block h-1.5 w-full overflow-hidden rounded-full accent-emerald-500 [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-emerald-500 [&::-moz-progress-bar]:bg-emerald-500"
                :aria-label="
                  projectText('PROJECT_PROGRESS', 'Progresso do projeto')
                "
              />
            </div>
          </div>
        </div>
        <nav
          class="flex gap-1 overflow-x-auto pb-2"
          role="tablist"
          :aria-label="projectText('PROJECT_SECTIONS', 'Abas do projeto')"
        >
          <button
            v-for="(item, index) in tabs"
            :id="'project-tab-' + item[0]"
            :key="item[0]"
            class="flex shrink-0 items-center gap-2 whitespace-nowrap rounded-lg px-3 py-2.5 text-xs font-medium transition"
            :class="
              tab === item[0]
                ? 'bg-n-blue-9 text-white shadow-sm'
                : 'text-n-slate-11 hover:bg-n-slate-3'
            "
            role="tab"
            :aria-selected="tab === item[0]"
            :tabindex="tab === item[0] ? 0 : -1"
            :aria-controls="'project-panel-' + item[0]"
            @click="navigate(item[0])"
            @keydown="focusTab($event, index)"
          >
            <span class="size-4" :class="item[2]" aria-hidden="true" />{{
              item[1]
            }}
          </button>
        </nav>
      </header>
      <div
        :id="'project-panel-' + tab"
        class="min-w-0"
        role="tabpanel"
        :aria-labelledby="'project-tab-' + tab"
        :aria-busy="loading"
      >
        <KeepAlive>
          <ProjectOverview
            v-if="tab === 'overview'"
            :project="project"
            :tasks="tasks"
            @navigate="navigate"
            @open-task="openTask"
          />
          <ProjectExecution
            v-else-if="tab === 'board'"
            :project="project"
            :tasks="tasks"
            :filters="filters"
            :synced="tasksSynced"
            :refresh="refresh"
            @filter="Object.assign(filters, $event)"
            @navigate="navigate"
            @open-task="openTask"
          />
          <ProjectPlanning
            v-else-if="tab === 'planning'"
            :project="project"
            :tasks="tasks"
            :filtered-tasks="filteredTasks"
            :filters="filters"
            @filter="Object.assign(filters, $event)"
            @changed="load"
            @open-task="openTask"
          />
          <ProjectTeam
            v-else-if="tab === 'team'"
            :project="project"
            :tasks="tasks"
            @changed="load"
          />
          <ProjectHours
            v-else-if="tab === 'hours'"
            :project="project"
            :tasks="tasks"
            @changed="load"
          />
          <FilesBox
            v-else-if="tab === 'files'"
            :endpoint="'projects/projects/' + project.id + '/files'"
            :can-edit="can('project.update') && editable"
            @changed="load"
          />
          <OperationsLinks
            v-else-if="tab === 'links'"
            :project-id="project.id"
            :project="project"
            :can-link="can('project.update')"
            @changed="load"
          />
          <ProjectConfiguration
            v-else-if="tab === 'settings'"
            :project="project"
            @changed="load"
          />
        </KeepAlive>
      </div>
      <TaskEditor
        v-if="taskModal"
        :key="selectedTask?.id || 'new'"
        :project="project"
        :task="selectedTask"
        :tasks="tasks"
        :initial-column-id="initialColumnId"
        @open="openTask"
        @close="closeTask"
        @changed="load"
      />
    </template>
  </section>
</template>
