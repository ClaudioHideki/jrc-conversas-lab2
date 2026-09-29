<script setup>
import { ref, computed, watch } from 'vue';
import OpsModal from './OpsModal.vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { request, errorMessage, allPages } from '../api';
const props = defineProps({
  ticketId: [String, Number],
  projectId: [String, Number],
  conversationId: [String, Number],
  dealId: [String, Number],
  initialKind: { type: String, default: '' },
  requireTask: Boolean,
});
const emit = defineEmits(['close', 'linked']);
const { accountId, status, projectText } = useProjects();
const choices = computed(() => {
  const project = {
    value: 'project',
    label: projectText('EXISTING_PROJECT', 'Projeto existente'),
    enabled: status.value?.projects_enabled,
  };
  const ticket = {
    value: 'ticket',
    label: projectText('EXISTING_TICKET', 'Chamado existente'),
    enabled: status.value?.service_desk_enabled,
  };
  const conversation = {
    value: 'conversation',
    label: projectText('EXISTING_CONVERSATION', 'Conversa existente'),
    enabled: true,
  };
  const deal = {
    value: 'deal',
    label: projectText('WON_DEAL', 'Negócio ganho'),
    enabled: status.value?.crm_enabled,
  };
  const options = props.projectId
    ? [ticket, deal, conversation]
    : props.ticketId
      ? [project]
      : props.dealId
        ? [project]
        : [project];
  return options.filter(
    item => item.enabled && (!props.requireTask || item.value === 'project')
  );
});
const kind = ref(
  choices.value.find(item => item.value === props.initialKind)?.value ||
    choices.value[0]?.value ||
    ''
);
const q = ref('');
const results = ref([]);
const selectedId = ref('');
const taskId = ref('');
const tasks = ref([]);
const conversation = ref('');
const error = ref('');
const busy = ref(false);
const searching = ref(false);
const loadingTasks = ref(false);
let generation = 0;
let taskGeneration = 0;
async function search() {
  const current = ++generation;
  results.value = [];
  selectedId.value = '';
  searching.value = false;
  error.value = '';
  if (!kind.value || kind.value === 'conversation') return;
  searching.value = true;
  const searchedKind = kind.value;
  try {
    const path =
      searchedKind === 'ticket'
        ? 'operations/tickets'
        : searchedKind === 'project'
          ? 'projects/projects'
          : 'operations/deals';
    const result = await request(accountId.value, path, {
      params: { q: q.value, per_page: 30 },
    });
    if (current === generation)
      results.value = result.data.filter(record =>
        searchedKind === 'project'
          ? record.capabilities?.includes('projects.project.update')
          : searchedKind === 'ticket'
            ? record.can_update
            : true
      );
  } catch (err) {
    if (current === generation) error.value = errorMessage(err);
  } finally {
    if (current === generation) searching.value = false;
  }
}
watch(
  kind,
  () => {
    q.value = '';
    search();
  },
  { immediate: true }
);
watch(
  () => [kind.value, selectedId.value],
  async () => {
    const current = ++taskGeneration;
    tasks.value = [];
    taskId.value = '';
    loadingTasks.value = false;
    const project =
      props.projectId || (kind.value === 'project' && selectedId.value);
    if (
      !project ||
      !selectedId.value ||
      !(props.ticketId || kind.value === 'ticket')
    )
      return;
    loadingTasks.value = true;
    try {
      const result = await allPages(
        accountId.value,
        `projects/projects/${project}/tasks`
      );
      if (current === taskGeneration)
        tasks.value = result.filter(task => task.can_update);
    } catch (err) {
      if (current === taskGeneration) error.value = errorMessage(err);
    } finally {
      if (current === taskGeneration) loadingTasks.value = false;
    }
  }
);
async function submit() {
  if (
    busy.value ||
    searching.value ||
    loadingTasks.value ||
    (props.requireTask && !taskId.value)
  )
    return;
  busy.value = true;
  error.value = '';
  try {
    const link = {
      ticket_id: props.ticketId || undefined,
      project_id: props.projectId || undefined,
      conversation_display_id: props.conversationId || undefined,
      deal_id: props.dealId || undefined,
    };
    link[
      {
        ticket: 'ticket_id',
        project: 'project_id',
        deal: 'deal_id',
        conversation: 'conversation_display_id',
      }[kind.value]
    ] = kind.value === 'conversation' ? conversation.value : selectedId.value;
    if (taskId.value) link.task_id = taskId.value;
    await request(accountId.value, 'operations/links', {
      method: 'post',
      data: link,
    });
    emit('linked');
    emit('close');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <OpsModal
    :title="projectText('LINK_ORIGIN', 'Vincular registro existente')"
    :busy="busy"
    @close="emit('close')"
  >
    <form class="flex flex-col gap-4" @submit.prevent="submit">
      <p class="text-sm text-n-slate-11">
        {{
          projectText(
            'LINK_HELP',
            'O registro original será preservado. O vínculo não muda a situação nem as permissões de acesso.'
          )
        }}
      </p>
      <div
        v-if="error"
        class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
        role="alert"
      >
        {{ error }}
      </div>
      <label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('LINK_TO', 'Vincular a') }}</span><select v-model="kind" required :disabled="busy">
          <option
            v-for="choice in choices"
            :key="choice.value"
            :value="choice.value"
          >
            {{ choice.label }}
          </option>
        </select></label>
      <label
v-if="kind === 'conversation'" class="flex flex-col gap-1 min-w-0"
        ><span>{{
          projectText('CONVERSATION_NUMBER', 'Número da conversa *')
        }}</span><input
          v-model="conversation"
          type="number"
          min="1"
          required
          :disabled="busy"
        /><small>{{
          projectText(
            'CONVERSATION_NUMBER_HELP',
            'Use o número exibido na conversa, não o ID interno do banco. Seu acesso será validado.'
          )
        }}</small></label>
      <template v-else>
        <div class="flex flex-wrap items-center gap-3">
          <input
            v-model="q"
            class="rounded border border-n-weak bg-n-solid-1 p-2 flex-1"
            :placeholder="
              projectText('SEARCH_RELATED', 'Pesquisar por nome ou assunto')
            "
            :aria-label="
              projectText('SEARCH_RELATED', 'Pesquisar por nome ou assunto')
            "
            :disabled="busy"
            @keydown.enter.prevent="search"
          /><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            type="button"
            :disabled="searching || busy"
            @click="search"
          >
            {{ projectText('SEARCH', 'Pesquisar') }}
          </button>
        </div>
        <label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('RELATED_RECORD', 'Registro *') }}</span><select v-model="selectedId" required :disabled="busy || searching">
            <option value="">
              {{
                projectText(
                  'SELECT_AUTHORIZED',
                  'Selecione um registro autorizado'
                )
              }}
            </option>
            <option
              v-for="record in results"
              :key="record.id"
              :value="record.id"
            >
              {{ record.number || record.key || record.id }} ·
              {{ record.title || record.name }}
            </option></select><small>{{
            projectText(
              'LINK_PERMISSION_HELP',
              'Até 30 resultados por busca. O servidor valida permissão para alterar os dois lados do vínculo.'
            )
          }}</small></label>
      </template>
      <label
        v-if="tasks.length || requireTask"
        class="flex flex-col gap-1 min-w-0"
        ><span>{{
          requireTask
            ? projectText('REQUIRED_TASK', 'Tarefa *')
            : projectText('OPTIONAL_TASK', 'Tarefa específica (opcional)')
        }}</span><select
          v-model="taskId"
          :required="requireTask"
          :disabled="busy || loadingTasks"
        >
          <option value="">
            {{
              requireTask
                ? projectText('SELECT_TASK', 'Selecione uma tarefa')
                : projectText('LINK_TO_PROJECT', 'Vincular ao projeto')
            }}
          </option>
          <option v-for="task in tasks" :key="task.id" :value="task.id">
            {{ task.title }}
          </option></select><small
          v-if="requireTask && selectedId && !loadingTasks && !tasks.length"
          >{{
            projectText(
              'NO_AUTHORIZED_TASKS',
              'Não há tarefas disponíveis para vincular neste projeto.'
            )
          }}</small></label>
      <footer class="flex justify-end gap-3 mt-4">
        <button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          type="button"
          :disabled="busy"
          @click="emit('close')"
        >
          {{ projectText('CANCEL', 'Cancelar') }}</button><button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 bg-n-blue-9 text-white"
          :disabled="
            busy || searching || loadingTasks || (requireTask && !taskId)
          "
        >
          {{ projectText('LINK', 'Vincular') }}
        </button>
      </footer>
    </form>
  </OpsModal>
</template>
