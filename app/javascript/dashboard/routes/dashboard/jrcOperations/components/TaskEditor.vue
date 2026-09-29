<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import OpsModal from './OpsModal.vue';
import FilesBox from './FilesBox.vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { projectTaskStatuses } from '../../jrcProjects/taskBoard';
import {
  request,
  errorMessage,
  priorities,
  formatDate,
  dateInput,
} from '../api';
const props = defineProps({
  project: { type: Object, required: true },
  task: Object,
  tasks: { type: Array, default: () => [] },
});
const emit = defineEmits(['close', 'changed', 'open']);
const { accountId, projectText } = useProjects();
const busy = ref(false);
const error = ref('');
const detail = ref(null);
const comment = ref('');
const checklistText = ref('');
const tab = ref('details');
const predecessor = ref('');
const labelsText = ref((props.task?.labels || []).join(', '));
const formVersion = ref(props.task?.lock_version);
const projectBase = `projects/projects/${props.project.id}`;
const base = `${projectBase}/tasks`;
const openProject = computed(
  () => !['completed', 'canceled'].includes(props.project.status)
);
const editable = computed(
  () =>
    openProject.value &&
    (props.task
      ? detail.value?.can_update
      : props.project.capabilities.includes('projects.task.create'))
);
const canDependencies = computed(
  () =>
    openProject.value &&
    props.project.capabilities.includes('projects.project.update')
);
const canLogHours = computed(
  () =>
    openProject.value &&
    props.project.capabilities.includes('projects.time_entry.create')
);
const candidates = computed(() =>
  props.tasks.filter(task => task.id !== props.task?.id)
);
const form = reactive({
  title: props.task?.title || '',
  description: props.task?.description || '',
  priority: props.task?.priority || 'medium',
  assignee_id: props.task?.assignee_id || '',
  parent_id: props.task?.parent_id || '',
  estimated_minutes: props.task?.estimated_minutes || 0,
  starts_on: props.task?.starts_on || '',
  due_on: props.task?.due_on || '',
  board_column_id:
    props.task?.board_column_id ||
    props.project.columns.find(x => x.status_key === 'backlog')?.id ||
    props.project.columns[0]?.id,
});
const timeForm = reactive({
  minutes: 60,
  worked_on: dateInput(new Date()),
  notes: '',
});
const hours = minutes =>
  (Number(minutes || 0) / 60).toLocaleString('pt-BR', {
    maximumFractionDigits: 2,
  });
const taskTitle = id =>
  props.tasks.find(task => task.id === id)?.title || `#${id}`;
async function load(syncForm = false) {
  if (!props.task) return;
  const record = (await request(accountId.value, `${base}/${props.task.id}`))
    .data;
  detail.value = record;
  if (syncForm) {
    for (const field of Object.keys(form)) form[field] = record[field] ?? '';
    labelsText.value = (record.labels || []).join(', ');
    formVersion.value = record.lock_version;
  }
}
async function refresh() {
  busy.value = true;
  error.value = '';
  try {
    await load(true);
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
onMounted(refresh);
async function submit() {
  if (busy.value || !editable.value) return;
  busy.value = true;
  error.value = '';
  try {
    const data = {
      task: {
        ...form,
        assignee_id: form.assignee_id || null,
        parent_id: form.parent_id || null,
        labels: labelsText.value
          .split(',')
          .map(label => label.trim())
          .filter(Boolean),
        lock_version: formVersion.value,
      },
    };
    await request(
      accountId.value,
      props.task ? `${base}/${props.task.id}` : base,
      { method: props.task ? 'patch' : 'post', data }
    );
    emit('changed');
    emit('close');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function action(path, method, data) {
  if (busy.value || !editable.value) return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${base}/${props.task.id}/${path}`, {
      method,
      data,
    });
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function addComment() {
  await action('comments', 'post', { comment: { body: comment.value } });
  if (!error.value) comment.value = '';
}
async function addChecklist() {
  await action('checklist_items', 'post', {
    item: { text: checklistText.value, completed: false },
  });
  if (!error.value) checklistText.value = '';
}
async function dependency(edge = null) {
  if (busy.value || !canDependencies.value) return;
  busy.value = true;
  error.value = '';
  try {
    await request(
      accountId.value,
      `${projectBase}/dependencies${edge ? `/${edge.id}` : ''}`,
      {
        method: edge ? 'delete' : 'post',
        data: edge
          ? undefined
          : {
              predecessor_id: predecessor.value,
              successor_id: props.task.id,
              kind: 'finish_to_start',
            },
      }
    );
    predecessor.value = '';
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function logTime() {
  if (busy.value || !canLogHours.value) return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${projectBase}/time_entries`, {
      method: 'post',
      data: { time_entry: { ...timeForm, task_id: props.task.id } },
    });
    timeForm.notes = '';
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function attachmentsChanged() {
  try {
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  }
}
function openSubtask(id) {
  const task = props.tasks.find(row => row.id === id);
  if (task) emit('open', task);
}
</script>

<template>
  <OpsModal
    :title="task ? task.title : 'Nova tarefa'"
    :busy="busy"
    wide
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <div
        v-if="error"
        class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
        role="alert"
      >
        {{ error }}
        <button
          v-if="task"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
          :disabled="busy"
          @click="refresh"
        >
          {{ projectText('TASK_RELOAD', 'Recarregar tarefa') }}
        </button>
      </div>
      <p v-if="task && !detail && busy" role="status">
        {{ projectText('TASK_LOADING', 'Carregando tarefa...') }}
      </p>
      <p v-if="detail" class="flex flex-wrap items-center gap-3">
        <span class="rounded px-2 py-1 text-xs border border-n-weak">{{
          projectTaskStatuses[detail.status]
        }}</span><span>{{ projectText('ESTIMATED_HOURS', 'Horas previstas') }}:
          {{ hours(detail.estimated_minutes) }} h</span><span>{{
            projectText(
              'WORKED_HOURS',
              'Horas registradas (enviadas ou aprovadas)'
            )
          }}: {{ hours(detail.worked_minutes) }} h</span>
      </p>
      <nav
        v-if="task"
        class="flex gap-3 overflow-x-auto py-3 [&_button]:rounded-lg [&_button]:px-3 [&_button]:py-2 [&_a]:px-3 [&_a]:py-2 [&_.active]:bg-n-blue-9 [&_.active]:text-white [&_.router-link-exact-active]:text-n-blue-11"
      >
        <button :class="{ active: tab === 'details' }" @click="tab = 'details'">
          Detalhes</button><button
          :class="{ active: tab === 'history' }"
          @click="tab = 'history'"
        >
          Checklist e comentarios</button><button
          :class="{ active: tab === 'dependencies' }"
          @click="tab = 'dependencies'"
        >
          {{ projectText('DEPENDENCIES', 'Dependências') }}</button><button :class="{ active: tab === 'hours' }" @click="tab = 'hours'">
          {{ projectText('TASK_HOURS', 'Horas da tarefa') }}</button><button :class="{ active: tab === 'files' }" @click="tab = 'files'">
          Arquivos
        </button>
      </nav>
      <form
        v-if="tab === 'details'"
        class="flex flex-col gap-4"
        @submit.prevent="submit"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <label class="flex flex-col gap-1 min-w-0 col-span-full"><span>Titulo *</span><input
              v-model="form.title"
              required
              maxlength="240"
              :disabled="!editable" /></label><label class="flex flex-col gap-1 min-w-0 col-span-full"><span>Descricao</span><textarea v-model="form.description" :disabled="!editable" />
          </label>
          <label class="flex flex-col gap-1 min-w-0"><span>Responsavel</span><select v-model="form.assignee_id" :disabled="!editable">
              <option value="">Nao atribuido</option>
              <option
                v-for="member in project.members"
                :key="member.user_id"
                :value="member.user_id"
              >
                {{ member.user.name }}
              </option></select><small>Inclua o usuario na equipe antes de atribuir tarefas.</small></label>
          <label class="flex flex-col gap-1 min-w-0"><span>Prioridade</span><select v-model="form.priority" :disabled="!editable">
              <option
                v-for="(label, key) in priorities"
                :key="key"
                :value="key"
              >
                {{ label }}
              </option>
            </select></label>
          <label class="flex flex-col gap-1 min-w-0"><span>Inicio previsto</span><input
              v-model="form.starts_on"
              type="date"
              :disabled="!editable" /></label><label class="flex flex-col gap-1 min-w-0"><span>Prazo</span><input
              v-model="form.due_on"
              type="date"
              :min="form.starts_on || undefined"
              :disabled="!editable"
          /></label>
          <label class="flex flex-col gap-1 min-w-0"><span>Estimativa em minutos</span><input
              v-model.number="form.estimated_minutes"
              type="number"
              min="0"
              step="1"
              :disabled="!editable"
          /></label>
          <label class="flex flex-col gap-1 min-w-0"><span>{{
              projectText('LABELS', 'Etiquetas (separadas por vírgula)')
            }}</span><input
v-model="labelsText" :disabled="!editable"
          /></label>
          <label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('PARENT_TASK', 'Tarefa pai') }}</span><select v-model="form.parent_id" :disabled="!editable">
              <option value="">
                {{ projectText('NO_PARENT', 'Sem tarefa pai') }}
              </option>
              <option
                v-for="candidate in candidates"
                :key="candidate.id"
                :value="candidate.id"
              >
                {{ candidate.title }}
              </option>
            </select></label>
          <label
v-if="!task" class="flex flex-col gap-1 min-w-0"
            ><span>Coluna inicial</span><select
              v-model="form.board_column_id"
              required
              :disabled="!editable"
            >
              <option
                v-for="column in project.columns.filter(
                  x => x.status_key !== 'completed'
                )"
                :key="column.id"
                :value="column.id"
              >
                {{ column.name }}
              </option>
            </select></label>
        </div>
        <section v-if="detail?.subtasks?.length" class="flex flex-col gap-4">
          <h3>{{ projectText('SUBTASKS', 'Subtarefas') }}</h3>
          <button
            v-for="child in detail.subtasks"
            :key="child.id"
            class="text-n-blue-11 underline text-left"
            type="button"
            @click="openSubtask(child.id)"
          >
            {{ child.title }} · {{ projectTaskStatuses[child.status] }}
          </button>
        </section>
        <p v-if="task" class="text-n-slate-11 text-sm">
          A movimentacao entre colunas e feita no quadro, preservando limites e
          dependencias.
        </p>
        <footer class="flex justify-end gap-3 mt-4">
          <button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            type="button"
            :disabled="busy"
            @click="emit('close')"
          >
            Fechar</button><button
            v-if="editable"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 bg-n-blue-9 text-white"
            :disabled="busy"
          >
            {{ task ? 'Salvar tarefa' : 'Criar tarefa' }}
          </button>
        </footer>
      </form>
      <section v-else-if="tab === 'history'" class="flex flex-col gap-4">
        <h3>Checklist</h3>
        <div
          v-for="item in detail?.checklist || []"
          :key="item.id"
          class="flex flex-wrap items-center gap-3 justify-between"
        >
          <label class="flex gap-2 items-center"><input
              type="checkbox"
              :checked="item.completed"
              :disabled="busy || !editable"
              @change="
                action(`checklist_items/${item.id}`, 'patch', {
                  item: { completed: $event.target.checked },
                })
              "
            />{{ item.text }}</label><button
            v-if="editable"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
            :disabled="busy"
            @click="action(`checklist_items/${item.id}`, 'delete')"
          >
            {{ projectText('REMOVE', 'Remover') }}
          </button>
        </div>
        <form
          v-if="editable"
          class="flex flex-wrap items-center gap-3"
          @submit.prevent="addChecklist"
        >
          <input
            v-model="checklistText"
            class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[460px]"
            required
            placeholder="Novo item de verificacao"
          /><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            :disabled="busy"
          >
            Adicionar item
          </button>
        </form>
        <h3>Comentarios internos</h3>
        <article
          v-for="entry in detail?.comments || []"
          :key="entry.id"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <div class="flex flex-wrap items-center gap-3 justify-between">
            <strong>{{ entry.user?.name || 'Equipe' }}</strong><small>{{ formatDate(entry.created_at) }}</small>
          </div>
          <p class="whitespace-pre-wrap break-words">{{ entry.body }}</p>
        </article>
        <p
          v-if="detail?.comments?.length >= 100"
          class="text-n-slate-11 text-sm"
        >
          Exibindo os 100 comentarios mais recentes.
        </p>
        <form
          v-if="editable"
          class="flex flex-col gap-4"
          @submit.prevent="addComment"
        >
          <label class="flex flex-col gap-1 min-w-0"><span>Comentario interno</span><textarea v-model="comment" required maxlength="20000" /></label><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            :disabled="busy"
          >
            Registrar comentario
          </button>
        </form>
      </section>
      <section v-else-if="tab === 'dependencies'" class="flex flex-col gap-4">
        <p class="text-sm text-n-slate-11">
          {{
            projectText(
              'DEPENDENCY_HELP',
              'A conclusão exige predecessoras concluídas ou canceladas.'
            )
          }}
        </p>
        <div
          v-for="edge in detail?.dependencies || []"
          :key="edge.id"
          class="flex flex-wrap items-center gap-3 justify-between"
        >
          <span>{{ taskTitle(edge.predecessor_id) }} → {{ task.title }}</span><button
            v-if="canDependencies"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
            :disabled="busy"
            @click="dependency(edge)"
          >
            {{ projectText('REMOVE', 'Remover') }}
          </button>
        </div>
        <p v-if="!detail?.dependencies?.length" class="text-n-slate-11 text-sm">
          {{ projectText('NO_DEPENDENCIES', 'Nenhuma dependência.') }}
        </p>
        <form
          v-if="canDependencies"
          class="flex flex-wrap items-center gap-3"
          @submit.prevent="dependency()"
        >
          <label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('PREDECESSOR', 'Predecessora') }}</span><select v-model="predecessor" required>
              <option value="">
                {{ projectText('SELECT_TASK', 'Selecione uma tarefa') }}
              </option>
              <option
                v-for="candidate in candidates"
                :key="candidate.id"
                :value="candidate.id"
              >
                {{ candidate.title }}
              </option>
            </select></label><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            :disabled="busy"
          >
            {{ projectText('ADD_DEPENDENCY', 'Adicionar dependência') }}
          </button>
        </form>
      </section>
      <section v-else-if="tab === 'hours'" class="flex flex-col gap-4">
        <p>
          {{
            projectText(
              'WORKED_HOURS',
              'Horas registradas (enviadas ou aprovadas)'
            )
          }}: {{ hours(detail?.worked_minutes) }} h
        </p>
        <p v-if="!openProject" class="text-sm text-n-slate-11">
          {{
            projectText(
              'CLOSED_TIME',
              'Reabra o projeto para registrar novas horas.'
            )
          }}
        </p>
        <form
          v-if="canLogHours"
          class="flex flex-col gap-4"
          @submit.prevent="logTime"
        >
          <label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('TIME_DATE', 'Data') }}</span><input v-model="timeForm.worked_on" type="date" required /></label><label class="flex flex-col gap-1 min-w-0"><span>{{
              projectText('TIME_MINUTES', 'Minutos trabalhados')
            }}</span><input
              v-model.number="timeForm.minutes"
              type="number"
              min="1"
              max="1440"
              step="1"
              required /></label><label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('TIME_NOTES', 'Observação') }}</span><input v-model="timeForm.notes" maxlength="2000" /></label><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 bg-n-blue-9 text-white"
            :disabled="busy"
          >
            {{ projectText('REGISTER_HOURS', 'Registrar horas') }}
          </button>
        </form>
      </section>
      <FilesBox
        v-else-if="task && tab === 'files'"
        :endpoint="`${base}/${task.id}/files`"
        :can-edit="Boolean(editable)"
        @changed="attachmentsChanged"
      />
    </div>
  </OpsModal>
</template>
