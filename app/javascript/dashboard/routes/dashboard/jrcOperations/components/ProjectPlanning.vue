<script setup>
import { ref, computed, watch } from 'vue';
import { useProjects } from '../../jrcProjects/useProjects';
import {
  projectTimeline,
  timelineBar,
} from '../../jrcProjects/planningProjection';
import { request, allPages, errorMessage, formatDate } from '../api';
import { projectResources } from '../resources';
import ResourceManager from './ResourceManager.vue';
const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed', 'openTask']);
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
const timeline = computed(() =>
  projectTimeline(props.project, props.tasks, milestones.value)
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
const kindLabel = kind =>
  ({
    project: projectText('PROJECT', 'Projeto'),
    task: projectText('TASK', 'Tarefa'),
    subtask: projectText('SUBTASK', 'Subtarefa'),
    milestone: projectText('MILESTONE', 'Marco'),
  })[kind];
const bar = row => timelineBar(row, timeline.value.range);
const title = id => props.tasks.find(task => task.id === id)?.title || `#${id}`;
const predecessorsFor = id =>
  dependencies.value.filter(edge => edge.successor_id === id);
let generation = 0;
async function load() {
  const n = ++generation;
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
  <section class="flex flex-col gap-4">
    <nav
      class="flex gap-3 overflow-x-auto py-3 [&_button]:rounded-lg [&_button]:px-3 [&_button]:py-2 [&_a]:px-3 [&_a]:py-2 [&_.active]:bg-n-blue-9 [&_.active]:text-white [&_.router-link-exact-active]:text-n-blue-11"
    >
      <button :class="{ active: tab === 'timeline' }" @click="tab = 'timeline'">
        {{ projectText('TIMELINE', 'Cronograma') }}</button><button
        :class="{ active: tab === 'dependencies' }"
        @click="tab = 'dependencies'"
      >
        {{ projectText('DEPENDENCIES', 'Dependências') }}</button><button
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
    <div
      v-if="tab === 'timeline'"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
    >
      <h3>{{ projectText('TIMELINE', 'Cronograma') }}</h3>
      <p class="text-n-slate-11 text-sm">
        {{
          projectText(
            'TIMELINE_HELP',
            'Projeção das datas do projeto, tarefas, subtarefas e marcos. Para alterar datas, abra o cadastro correspondente.'
          )
        }}
      </p>
      <p v-if="!timeline.range" class="text-sm text-n-slate-11">
        {{
          projectText(
            'TIMELINE_NO_DATES',
            'Os registros ainda não possuem datas previstas.'
          )
        }}
      </p>
      <div
        v-for="row in timeline.rows"
        :key="row.key"
        class="grid grid-cols-[minmax(170px,35%)_1fr] gap-4 py-3 border-t border-n-weak"
      >
        <div>
          <span class="rounded px-2 py-1 text-xs border border-n-weak">{{
            kindLabel(row.kind)
          }}</span>
          <button
            v-if="['task', 'subtask'].includes(row.kind)"
            class="text-n-blue-11 underline"
            @click="emit('openTask', row.record)"
          >
            {{ row.title }}</button><strong v-else>{{ row.title }}</strong>
          <p v-if="row.parent" class="text-n-slate-11 text-sm">
            {{ projectText('PARENT_TASK', 'Tarefa pai') }}:
            {{ row.parent.title }}
          </p>
          <p class="text-n-slate-11 text-sm">
            {{ formatDate(row.record.starts_on) }} →
            {{ formatDate(row.record.due_on) }}
          </p>
          <p
            v-if="
              ['task', 'subtask'].includes(row.kind) &&
              predecessorsFor(row.record.id).length
            "
            class="text-n-slate-11 text-sm"
          >
            {{ projectText('PREDECESSORS', 'Predecessoras') }}:
            {{
              predecessorsFor(row.record.id)
                .map(edge => title(edge.predecessor_id))
                .join(', ')
            }}
          </p>
        </div>
        <svg
          v-if="bar(row)"
          viewBox="0 0 1000 28"
          preserveAspectRatio="none"
          class="w-full h-7"
          role="img"
          :aria-label="`${row.title}: ${formatDate(row.record.starts_on)} → ${formatDate(row.record.due_on)}`"
        >
          <rect
            x="0"
            y="9"
            width="1000"
            height="10"
            rx="5"
            class="fill-current text-n-weak"
          />
          <rect
            :x="bar(row).x"
            y="4"
            :width="bar(row).width"
            height="20"
            rx="4"
            class="fill-current text-n-brand"
          />
        </svg>
        <p v-else class="text-n-slate-11 text-sm">
          {{ projectText('NO_DATE', 'Sem prazo') }}
        </p>
      </div>
    </div>
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
        <span>{{ title(edge.predecessor_id) }} →
          {{ title(edge.successor_id) }}</span><button
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
        <label class="flex flex-col gap-1 min-w-0 flex-1"><span>{{ projectText('PREDECESSOR', 'Predecessora') }}</span><select v-model="predecessor" required>
            <option value="">
              {{ projectText('SELECT_TASK', 'Selecione uma tarefa') }}
            </option>
            <option v-for="task in tasks" :key="task.id" :value="task.id">
              {{ task.title }}
            </option>
          </select></label><label class="flex flex-col gap-1 min-w-0 flex-1"><span>{{ projectText('SUCCESSOR', 'Sucessora') }}</span><select v-model="successor" required>
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
          </select></label><button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
          :disabled="busy"
        >
          {{ projectText('ADD_DEPENDENCY', 'Adicionar dependência') }}
        </button>
      </form>
      <div v-if="path" class="text-sm text-n-slate-11">
        <strong>{{
            projectText(
              'CRITICAL_PATH',
              'Caminho mais longo estimado (minutos de trabalho)'
            )
          }}: {{ path.duration_minutes }}</strong>
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
