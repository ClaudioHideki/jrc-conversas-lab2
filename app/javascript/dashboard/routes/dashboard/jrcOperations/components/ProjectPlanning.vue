<script setup>
import { ref, computed, watch } from 'vue';
import { useProjects } from '../../jrcProjects/useProjects';
import PlanningGantt from '../../jrcProjects/components/PlanningGantt.vue';
import { request, allPages, errorMessage } from '../api';
import { projectResources } from '../resources';
import ResourceManager from './ResourceManager.vue';
const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
  filteredTasks: { type: Array, default: null },
  filters: { type: Object, default: null },
});
const emit = defineEmits(['changed', 'openTask', 'filter']);
const { accountId, projectText } = useProjects();
const tab = ref('timeline');
const error = ref('');
const busy = ref(false);
const loading = ref(false);
const dependencies = ref([]);
const milestones = ref([]);
const path = ref(null);
const predecessor = ref('');
const successor = ref('');
const base = computed(() => `projects/projects/${props.project.id}`);
const openProject = computed(
  () => !['completed', 'canceled'].includes(props.project.status)
);
const canEdit = computed(
  () =>
    openProject.value &&
    props.project.capabilities.includes('projects.project.update')
);
const canManageResource = computed(
  () =>
    openProject.value &&
    props.project.capabilities.includes(
      tab.value === 'milestones'
        ? 'projects.milestone.manage'
        : 'projects.project.update'
    )
);
const schema = computed(() => {
  const resource = projectResources.find(item => item.key === tab.value);
  if (!resource || resource.key !== 'milestones') return resource;
  return {
    ...resource,
    fields: [
      ...resource.fields,
      {
        key: 'phase_id',
        label: projectText('PHASE', 'Fase'),
        type: 'option',
        source: 'project_phases',
      },
    ],
  };
});
const title = id => props.tasks.find(task => task.id === id)?.title || `#${id}`;
let generation = 0;
async function load() {
  generation += 1;
  const n = generation;
  loading.value = true;
  error.value = '';
  try {
    const [edges, critical, records] = await Promise.all([
      request(accountId.value, `${base.value}/dependencies`),
      request(accountId.value, `${base.value}/critical_path`),
      allPages(accountId.value, `${base.value}/milestones`),
    ]);
    if (n === generation) {
      dependencies.value = edges.data;
      path.value = critical.data;
      milestones.value = records;
    }
  } catch (err) {
    if (n === generation) error.value = errorMessage(err);
  } finally {
    if (n === generation) loading.value = false;
  }
}
watch(
  () => [
    accountId.value,
    props.project.id,
    props.tasks.map(task => `${task.id}:${task.lock_version}`).join(','),
  ],
  load,
  { immediate: true }
);
async function changed() {
  await load();
  emit('changed');
}
async function add() {
  if (busy.value || !canEdit.value) return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${base.value}/dependencies`, {
      method: 'post',
      data: {
        predecessor_id: predecessor.value,
        successor_id: successor.value,
        kind: 'finish_to_start',
      },
    });
    predecessor.value = '';
    successor.value = '';
    await changed();
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function remove(edge) {
  if (
    busy.value ||
    !canEdit.value ||
    !window.confirm(
      projectText('REMOVE_DEPENDENCY_CONFIRM', 'Remover esta dependência?')
    )
  )
    return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${base.value}/dependencies/${edge.id}`, {
      method: 'delete',
    });
    await changed();
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <header>
      <h2 class="m-0 text-lg font-semibold">
        {{ projectText('PLANNING', 'Planejamento') }}
      </h2>
      <p class="mb-0 mt-1 text-sm text-n-slate-11">
        {{
          projectText(
            'PLANNING_SUBTITLE',
            'Organize prazos, dependências e entregas do projeto.'
          )
        }}
      </p>
    </header>
    <nav
      class="flex gap-1 overflow-x-auto border-b border-n-weak pb-3 text-sm [&_button]:whitespace-nowrap [&_button]:rounded-lg [&_button]:px-3 [&_button]:py-2 [&_.active]:bg-n-blue-9 [&_.active]:text-white"
      :aria-label="projectText('PLANNING', 'Planejamento')"
    >
      <button :class="{ active: tab === 'timeline' }" @click="tab = 'timeline'">
        {{ projectText('TIMELINE', 'Cronograma') }}</button
      ><button
        :class="{ active: tab === 'dependencies' }"
        @click="tab = 'dependencies'"
      >
        {{ projectText('DEPENDENCIES', 'Dependências') }}</button
      ><button
        v-for="item in projectResources.filter(item => item.key !== 'members')"
        :key="item.key"
        :class="{ active: tab === item.key }"
        @click="tab = item.key"
      >
        {{ item.title }}
      </button>
    </nav>
    <p v-if="!openProject" class="text-sm text-n-slate-11">
      {{
        projectText(
          'CLOSED_PLANNING',
          'Planejamento somente para consulta. Reabra o projeto para alterar marcos ou dependências.'
        )
      }}
    </p>
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
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <p v-if="loading" role="status">
      {{ projectText('PLANNING_LOADING', 'Carregando planejamento...') }}
    </p>
    <PlanningGantt
      v-if="tab === 'timeline'"
      :project="project"
      :tasks="tasks"
      :filtered-tasks="filteredTasks"
      :filters="filters"
      :milestones="milestones"
      :dependencies="dependencies"
      @open-task="emit('openTask', $event)"
      @filter="emit('filter', $event)"
    />
    <section
      v-else-if="tab === 'dependencies'"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
    >
      <h3>{{ projectText('DEPENDENCIES', 'Dependências') }}</h3>
      <p class="text-n-slate-11 text-sm">
        {{
          projectText(
            'DEPENDENCY_HELP',
            'A conclusão exige predecessoras concluídas ou canceladas.'
          )
        }}
      </p>
      <div
        v-for="edge in dependencies"
        :key="edge.id"
        class="flex flex-wrap items-center gap-3 justify-between"
      >
        <span>{{
          `${title(edge.predecessor_id)} → ${title(edge.successor_id)}`
        }}</span
        ><button
          v-if="canEdit"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs text-n-ruby-11"
          :disabled="busy"
          @click="remove(edge)"
        >
          {{ projectText('REMOVE', 'Remover') }}
        </button>
      </div>
      <p v-if="!dependencies.length" class="text-n-slate-11 text-sm">
        {{ projectText('NO_DEPENDENCIES', 'Nenhuma dependência.') }}
      </p>
      <form
        v-if="canEdit"
        class="flex flex-wrap items-center gap-3"
        @submit.prevent="add"
      >
        <label class="flex flex-col gap-1 min-w-0 flex-1"
          ><span>{{ projectText('PREDECESSOR', 'Predecessora') }}</span
          ><select v-model="predecessor" required>
            <option value="">
              {{ projectText('SELECT_TASK', 'Selecione uma tarefa') }}
            </option>
            <option v-for="task in tasks" :key="task.id" :value="task.id">
              {{ task.title }}
            </option>
          </select></label
        ><label class="flex flex-col gap-1 min-w-0 flex-1"
          ><span>{{ projectText('SUCCESSOR', 'Sucessora') }}</span
          ><select v-model="successor" required>
            <option value="">
              {{ projectText('SELECT_TASK', 'Selecione uma tarefa') }}
            </option>
            <option
              v-for="task in tasks.filter(
                task => task.id !== Number(predecessor)
              )"
              :key="task.id"
              :value="task.id"
            >
              {{ task.title }}
            </option>
          </select></label
        ><button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
          :disabled="busy"
        >
          {{ projectText('ADD_DEPENDENCY', 'Adicionar dependência') }}
        </button>
      </form>
      <div v-if="path" class="text-sm text-n-slate-11">
        <strong
          >{{
            projectText(
              'CRITICAL_PATH',
              'Caminho mais longo estimado (minutos de trabalho)'
            )
          }}: {{ path.duration_minutes }}</strong
        >
        <p>{{ (path.task_ids || []).map(title).join(' → ') || '—' }}</p>
        <p>
          {{
            projectText(
              'CRITICAL_PATH_HELP',
              'Não considera calendário, paralelismo de pessoas ou capacidade. Não equivale ao prazo final contratado.'
            )
          }}
        </p>
      </div>
    </section>
    <ResourceManager
      v-else-if="schema"
      :schema="schema"
      :endpoint="`${base}/${schema.key}`"
      :can-edit="canManageResource"
      :extra-options="{ project_phases: project.phases || [] }"
      @changed="changed"
    />
  </section>
</template>
