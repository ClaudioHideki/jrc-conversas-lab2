<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import OpsModal from './OpsModal.vue';
import FilesBox from './FilesBox.vue';
import TaskCommentRich from '../../jrcProjects/components/TaskCommentRich.vue';
import { commentFormData } from '../../jrcProjects/commentDocument';
import { commentDraft as persistCommentDraft } from '../../jrcProjects/commentDrafts';
import { useProjects } from '../../jrcProjects/useProjects';
import { projectTaskStatuses } from '../../jrcProjects/taskBoard';
import {
  statusTone,
  priorityTone,
  taskProgress,
} from '../../jrcProjects/projectPresentation';
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
  initialColumnId: { type: [Number, String], default: null },
  tasks: { type: Array, default: () => [] },
});
const emit = defineEmits(['close', 'changed', 'open']);
const { accountId, userId, projectText } = useProjects();
const busy = ref(false);
const error = ref('');
const detail = ref(null);
const comment = ref('');
const commentPublished = ref(false);
const newCommentComposer = ref(null);
const editingRichComposer = ref(null);
const commentDraftAvailable = ref(false);
const registerRichEditor = editor => {
  editingRichComposer.value = editor;
};
const checklistText = ref('');
const editingComment = ref(null);
const commentDraft = ref('');
const editingChecklist = ref(null);
const checklistDraft = ref('');
const tab = ref('details');
const predecessor = ref('');
const labelsText = ref((props.task?.labels || []).join(', '));
const formVersion = ref(props.task?.lock_version);
const projectBase = `projects/projects/${props.project.id}`;
const base = `${projectBase}/tasks`;
const commentScope = computed(() => ({
  accountId: accountId.value,
  userId: userId.value,
  projectId: props.project.id,
  taskId: props.task?.id,
}));
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
    props.initialColumnId ||
    props.project.columns.find(x => x.status_key === 'backlog')?.id ||
    props.project.columns[0]?.id,
});
const snapshot = () => JSON.stringify({ ...form, labels: labelsText.value });
const savedSnapshot = ref(snapshot());
const dirty = computed(
  () =>
    snapshot() !== savedSnapshot.value ||
    Boolean(comment.value.trim()) ||
    Boolean(checklistText.value.trim()) ||
    editingComment.value !== null ||
    editingChecklist.value !== null
);
const taskTabs = computed(() => [
  ['details', projectText('DETAILS', 'Detalhes')],
  ['checklist', projectText('CHECKLIST', 'Checklist')],
  ['comments', projectText('COMMENTS', 'Comentários')],
  ['files', projectText('FILES', 'Arquivos')],
  ['dependencies', projectText('DEPENDENCIES', 'Dependências')],
  ['hours', projectText('TASK_HOURS', 'Horas')],
  ['history', projectText('HISTORY', 'Histórico')],
]);
async function requestClose() {
  if (busy.value) return;
  if (!dirty.value) {
    emit('close');
    return;
  }
  if (
    !dirty.value ||
    window.confirm(
      projectText(
        'DISCARD_TASK_CHANGES',
        'Fechar e descartar as alterações ainda não salvas nesta tarefa?'
      )
    )
  ) {
    busy.value = true;
    try {
      await newCommentComposer.value?.discard();
      await editingRichComposer.value?.discard();
      if (
        props.task &&
        commentDraftAvailable.value &&
        !newCommentComposer.value &&
        !editingRichComposer.value
      ) {
        await persistCommentDraft('delete', commentScope.value);
        if (editingComment.value)
          await persistCommentDraft('delete', {
            ...commentScope.value,
            commentId: editingComment.value,
          });
      }
      emit('close');
    } catch (err) {
      error.value = errorMessage(err);
    } finally {
      busy.value = false;
    }
  }
}
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
    Object.keys(form).forEach(field => {
      form[field] = record[field] ?? '';
    });
    labelsText.value = (record.labels || []).join(', ');
    formVersion.value = record.lock_version;
    savedSnapshot.value = snapshot();
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
  if (busy.value || !editable.value) return false;
  if (
    method === 'delete' &&
    !window.confirm(
      projectText(
        'DELETE_ITEM_CONFIRM',
        'Excluir este item? Esta ação é definitiva e será registrada no histórico.'
      )
    )
  )
    return false;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${base}/${props.task.id}/${path}`, {
      method,
      data,
    });
    await load();
    emit('changed');
    return true;
  } catch (err) {
    error.value = errorMessage(err);
    return false;
  } finally {
    busy.value = false;
  }
}
async function removeTask() {
  if (busy.value || !openProject.value || !detail.value?.can_delete) return;
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
  try {
    await request(accountId.value, `${base}/${props.task.id}`, {
      method: 'delete',
      data: { lock_version: detail.value.lock_version },
    });
    emit('close');
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
function canEditComment(entry) {
  return (
    editable.value &&
    (String(entry.user_id) === String(userId.value) ||
      props.project.capabilities.includes('projects.project.update'))
  );
}
async function saveComment() {
  if (!commentDraft.value.trim()) return;
  const saved = await action(`comments/${editingComment.value}`, 'patch', {
    comment: { body: commentDraft.value },
  });
  if (saved) editingComment.value = null;
}
async function saveChecklist() {
  if (!checklistDraft.value.trim()) return;
  const saved = await action(
    `checklist_items/${editingChecklist.value}`,
    'patch',
    {
      item: { text: checklistDraft.value },
    }
  );
  if (saved) editingChecklist.value = null;
}
async function saveRichComment(entry, payload) {
  if (busy.value || !editable.value) return;
  busy.value = true;
  error.value = '';
  commentPublished.value = false;
  try {
    await request(
      accountId.value,
      `${base}/${props.task.id}/comments${entry ? `/${entry.id}` : ''}`,
      {
        method: entry ? 'patch' : 'post',
        data: commentFormData(payload),
        key: payload.requestKey,
      }
    );
    commentPublished.value = true;
    // Clear the acknowledged draft before reload; a failed read must not cause a second POST.
    await payload.onSaved();
    editingComment.value = null;
    comment.value = '';
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function addChecklist() {
  const saved = await action('checklist_items', 'post', {
    item: { text: checklistText.value, completed: false },
  });
  if (saved) checklistText.value = '';
}
async function dependency(edge = null) {
  if (busy.value || !canDependencies.value) return;
  if (
    edge &&
    !window.confirm(
      projectText('REMOVE_DEPENDENCY_CONFIRM', 'Remover esta dependência?')
    )
  )
    return;
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
async function moveTask(event) {
  const column = props.project.columns.find(
    item => String(item.id) === event.target.value
  );
  if (
    ['completed', 'canceled'].includes(column?.status_key) &&
    !window.confirm(
      projectText(
        'CONFIRM_TASK_TRANSITION',
        'Confirmar esta mudança de situação? As dependências e os limites do quadro serão validados.'
      )
    )
  ) {
    event.target.value = detail.value.board_column_id;
    return;
  }
  busy.value = true;
  error.value = '';
  try {
    const result = await request(
      accountId.value,
      base + '/' + props.task.id + '/move',
      {
        method: 'post',
        data: {
          column_id: Number(event.target.value),
          lock_version: formVersion.value,
        },
      }
    );
    detail.value = { ...detail.value, ...result.data };
    formVersion.value = result.data.lock_version;
    const wasDirty = snapshot() !== savedSnapshot.value;
    form.board_column_id = result.data.board_column_id;
    if (!wasDirty) savedSnapshot.value = snapshot();
    emit('changed');
  } catch (err) {
    event.target.value = detail.value.board_column_id;
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
function taskEventLabel(eventAction) {
  const labels = {
    'projects.task.created': ['EVENT_TASK_CREATED', 'Tarefa criada'],
    'projects.task.updated': ['EVENT_TASK_UPDATED', 'Tarefa atualizada'],
    'projects.task.moved': ['EVENT_TASK_MOVED', 'Tarefa movimentada'],
    'projects.task.comment_added': ['EVENT_COMMENT', 'Comentário registrado'],
    'projects.task.comment_updated': [
      'EVENT_COMMENT_UPDATED',
      'Comentário editado',
    ],
    'projects.task.comment_deleted': [
      'EVENT_COMMENT_DELETED',
      'Comentário excluído',
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
    'projects.attachment.added': ['EVENT_ATTACHMENT_ADDED', 'Arquivo enviado'],
    'projects.attachment.removed': [
      'EVENT_ATTACHMENT_REMOVED',
      'Arquivo removido',
    ],
    'projects.task.dependency_added': [
      'EVENT_DEPENDENCY_ADDED',
      'Dependência adicionada',
    ],
    'projects.task.dependency_removed': [
      'EVENT_DEPENDENCY_REMOVED',
      'Dependência removida',
    ],
  };
  const [key, fallback] = labels[eventAction] || [
    'EVENT_REGISTERED',
    'Atividade registrada',
  ];
  return projectText(key, fallback);
}
function openSubtask(id) {
  const task = props.tasks.find(row => row.id === id);
  if (
    task &&
    (!dirty.value ||
      window.confirm(
        projectText(
          'DISCARD_TASK_CHANGES',
          'Descartar alterações não salvas e abrir a subtarefa?'
        )
      ))
  )
    emit('open', task);
}
</script>

<template>
  <OpsModal
    :title="task ? task.title : projectText('NEW_TASK', 'Nova tarefa')"
    :busy="busy"
    drawer
    @close="requestClose"
  >
    <div class="flex flex-col gap-4 text-sm">
      <div
        v-if="error"
        class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
        role="alert"
      >
        {{ error }}
        <button
          v-if="task"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          :disabled="busy"
          @click="refresh"
        >
          {{ projectText('TASK_RELOAD', 'Recarregar tarefa') }}
        </button>
      </div>
      <p v-if="task && !detail && busy" role="status">
        {{ projectText('TASK_LOADING', 'Carregando tarefa...') }}
      </p>
      <section
        v-if="detail"
        class="rounded-xl border border-n-weak bg-n-slate-2 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <span class="text-xs text-n-blue-11"
            >{{ project.key }} / #{{ detail.id }}</span
          ><span
            class="rounded-md px-2 py-1 text-xs font-medium"
            :class="priorityTone(detail.priority)"
            >{{ priorities[detail.priority] }}</span
          >
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-2">
          <select
            v-if="detail.can_move && openProject"
            :value="detail.board_column_id"
            class="rounded-lg border border-n-weak px-2 py-1 text-xs"
            :class="statusTone(detail.status)"
            :disabled="busy"
            :aria-label="projectText('MOVE_TASK', 'Mover tarefa')"
            @change="moveTask($event)"
          >
            <option
              v-for="column in project.columns"
              :key="column.id"
              :value="column.id"
            >
              {{ column.name }}
            </option></select
          ><span
            v-else
            class="rounded-md px-2 py-1 text-xs"
            :class="statusTone(detail.status)"
            >{{ projectTaskStatuses[detail.status] }}</span
          ><span class="text-xs text-n-slate-11"
            >{{ projectText('ESTIMATED_HOURS', 'Horas previstas') }}:
            {{ hours(detail.estimated_minutes) }}
            {{ projectText('HOUR_UNIT', 'h') }} ·
            {{ projectText('LOGGED_HOURS', 'Registradas') }}:
            {{ hours(detail.worked_minutes) }}
            {{ projectText('HOUR_UNIT', 'h') }}</span
          >
        </div>
        <div v-if="detail.checklist_total" class="mt-3 flex items-center gap-2">
          <progress
            :value="taskProgress(detail)"
            max="100"
            class="h-1.5 flex-1 overflow-hidden rounded-full accent-n-blue-9 [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9"
            :aria-label="
              projectText('CHECKLIST_PROGRESS', 'Progresso do checklist')
            "
          /><span class="text-xs">{{ taskProgress(detail) }}%</span>
        </div>
      </section>
      <nav
        v-if="task"
        class="flex gap-1 overflow-x-auto border-b border-n-weak pb-2"
        :aria-label="projectText('TASK_SECTIONS', 'Abas da tarefa')"
      >
        <button
          v-for="item in taskTabs"
          :key="item[0]"
          class="shrink-0 rounded-md px-3 py-2 text-xs font-medium"
          :class="
            tab === item[0]
              ? 'bg-n-blue-9 text-white'
              : 'text-n-slate-11 hover:bg-n-slate-3'
          "
          :aria-pressed="tab === item[0]"
          @click="tab = item[0]"
        >
          {{ item[1] }}
        </button>
      </nav>
      <form
        v-if="tab === 'details'"
        class="flex flex-col gap-4"
        @submit.prevent="submit"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <label class="flex flex-col gap-1 min-w-0 col-span-full"
            ><span>{{ projectText('TASK_TITLE', 'Título') }} *</span
            ><input
              v-model="form.title"
              required
              maxlength="240"
              :disabled="!editable" /></label
          ><label class="flex flex-col gap-1 min-w-0 col-span-full"
            ><span>{{ projectText('DESCRIPTION', 'Descrição') }}</span
            ><textarea v-model="form.description" :disabled="!editable" />
          </label>
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('ASSIGNEE', 'Responsável') }}</span
            ><select v-model="form.assignee_id" :disabled="!editable">
              <option value="">
                {{ projectText('UNASSIGNED', 'Não atribuído') }}
              </option>
              <option
                v-for="member in project.members"
                :key="member.user_id"
                :value="member.user_id"
              >
                {{ member.user.name }}
              </option></select
            ><small>{{
              projectText(
                'TASK_MEMBER_HELP',
                'Inclua o usuário na equipe antes de atribuir tarefas.'
              )
            }}</small></label
          >
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('PRIORITY', 'Prioridade') }}</span
            ><select v-model="form.priority" :disabled="!editable">
              <option
                v-for="(label, key) in priorities"
                :key="key"
                :value="key"
              >
                {{ label }}
              </option>
            </select></label
          >
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('PLANNED_START', 'Início previsto') }}</span
            ><input
              v-model="form.starts_on"
              type="date"
              :disabled="!editable" /></label
          ><label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('DUE_FILTER', 'Prazo') }}</span
            ><input
              v-model="form.due_on"
              type="date"
              :min="form.starts_on || undefined"
              :disabled="!editable"
          /></label>
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{
              projectText('ESTIMATE_MINUTES', 'Estimativa em minutos')
            }}</span
            ><input
              v-model.number="form.estimated_minutes"
              type="number"
              min="0"
              step="1"
              :disabled="!editable"
          /></label>
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{
              projectText('LABELS', 'Etiquetas (separadas por vírgula)')
            }}</span
            ><input
              v-model="labelsText"
              type="text"
              maxlength="2000"
              class="w-full"
              :disabled="!editable"
          /></label>
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('PARENT_TASK', 'Tarefa pai') }}</span
            ><select v-model="form.parent_id" :disabled="!editable">
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
            </select></label
          >
          <label
            v-if="!task"
            class="col-span-full flex min-w-0 flex-col gap-1 md:col-span-1"
            ><span>{{ projectText('INITIAL_COLUMN', 'Coluna inicial') }}</span
            ><select
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
            </select></label
          >
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
          {{
            projectText(
              'TASK_MOVE_HELP',
              'A movimentação preserva os limites do quadro e as dependências da tarefa.'
            )
          }}
        </p>
        <footer class="flex justify-end gap-3 mt-4">
          <button
            v-if="detail?.can_delete && openProject"
            type="button"
            class="mr-auto rounded-md border border-n-weak px-3 py-2 text-sm text-n-ruby-11 hover:bg-n-ruby-2 disabled:opacity-50"
            :disabled="busy"
            @click="removeTask"
          >
            {{ projectText('DELETE_TASK', 'Excluir tarefa') }}
          </button>
          <button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
            type="button"
            :disabled="busy"
            @click="requestClose"
          >
            {{ projectText('CLOSE', 'Fechar') }}</button
          ><button
            v-if="editable"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed bg-n-blue-9 text-white"
            :disabled="busy"
          >
            {{
              task
                ? projectText('SAVE_TASK', 'Salvar tarefa')
                : projectText('CREATE_TASK', 'Criar tarefa')
            }}
          </button>
        </footer>
      </form>
      <section v-else-if="tab === 'checklist'" class="flex flex-col gap-4">
        <h3>{{ projectText('CHECKLIST', 'Checklist') }}</h3>
        <div
          v-for="item in detail?.checklist || []"
          :key="item.id"
          class="flex flex-wrap items-center gap-3 justify-between"
        >
          <form
            v-if="editingChecklist === item.id"
            class="flex w-full flex-wrap items-center gap-2"
            @submit.prevent="saveChecklist"
          >
            <input
              v-model="checklistDraft"
              required
              maxlength="1000"
              class="min-w-0 flex-1 rounded border border-n-weak bg-n-solid-1 p-2"
              :aria-label="projectText('CHECKLIST_ITEM_TEXT', 'Texto do item')"
            />
            <button
              :disabled="busy"
              class="rounded border border-n-weak px-3 py-2"
            >
              {{ projectText('SAVE', 'Salvar') }}
            </button>
            <button
              type="button"
              :disabled="busy"
              class="rounded border border-n-weak px-3 py-2"
              @click="editingChecklist = null"
            >
              {{ projectText('CANCEL', 'Cancelar') }}
            </button>
          </form>
          <label
            v-else
            class="flex min-w-0 flex-1 items-center gap-2 break-words"
            ><input
              type="checkbox"
              :checked="item.completed"
              :disabled="busy || !editable"
              @change="
                action(`checklist_items/${item.id}`, 'patch', {
                  item: { completed: $event.target.checked },
                })
              "
            />{{ item.text }}</label
          >
          <button
            v-if="editable && editingChecklist !== item.id"
            type="button"
            class="ml-auto rounded border border-n-weak px-3 py-2 text-xs"
            :disabled="busy"
            @click="
              editingChecklist = item.id;
              checklistDraft = item.text;
            "
          >
            {{ projectText('EDIT', 'Editar') }}
          </button>
          <button
            v-if="editable && editingChecklist !== item.id"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
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
            :placeholder="
              projectText('NEW_CHECKLIST_ITEM', 'Novo item de verificação')
            "
          /><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
            :disabled="busy"
          >
            {{ projectText('ADD_ITEM', 'Adicionar item') }}
          </button>
        </form>
      </section>
      <section v-else-if="tab === 'comments'" class="flex flex-col gap-4">
        <h3>{{ projectText('INTERNAL_COMMENTS', 'Comentários internos') }}</h3>
        <p v-if="commentPublished" role="status" class="text-n-teal-11">
          {{ projectText('CONFIG_SAVED', 'Alterações salvas com sucesso.') }}
        </p>
        <p
          v-if="!detail?.comments?.length"
          class="py-6 text-center text-n-slate-11"
        >
          {{ projectText('NO_COMMENTS', 'Nenhum comentário nesta tarefa.') }}
        </p>
        <article
          v-for="entry in detail?.comments || []"
          :key="entry.id"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <div class="flex flex-wrap items-center gap-3 justify-between">
            <strong>{{
              entry.user?.name || projectText('TEAM', 'Equipe')
            }}</strong
            ><small>{{ formatDate(entry.created_at) }}</small>
          </div>
          <TaskCommentRich
            v-if="
              editingComment === entry.id && entry.content_format === 'markdown'
            "
            :ref="registerRichEditor"
            :scope="{ ...commentScope, commentId: entry.id }"
            :comment="entry"
            :disabled="busy"
            @submit="saveRichComment(entry, $event)"
            @cancel="editingComment = null"
            @draft-state="commentDraftAvailable = $event"
          />
          <form
            v-else-if="editingComment === entry.id"
            class="mt-3 flex flex-col gap-2"
            @submit.prevent="saveComment"
          >
            <textarea
              v-model="commentDraft"
              required
              maxlength="20000"
              class="w-full rounded border border-n-weak bg-n-solid-1 p-2"
              :aria-label="
                projectText('INTERNAL_COMMENT', 'Comentário interno')
              "
            />
            <div class="flex justify-end gap-2">
              <button
                type="button"
                :disabled="busy"
                class="rounded border border-n-weak px-3 py-2"
                @click="editingComment = null"
              >
                {{ projectText('CANCEL', 'Cancelar') }}
              </button>
              <button
                :disabled="busy"
                class="rounded bg-n-blue-9 px-3 py-2 text-white"
              >
                {{ projectText('SAVE', 'Salvar') }}
              </button>
            </div>
          </form>
          <template v-else>
            <TaskCommentRich
              v-if="entry.content_format === 'markdown'"
              :scope="commentScope"
              :comment="entry"
              readonly
            />
            <p v-else class="whitespace-pre-wrap break-words">
              {{ entry.body }}
            </p>
            <div
              v-if="canEditComment(entry)"
              class="mt-2 flex justify-end gap-2"
            >
              <button
                type="button"
                class="rounded border border-n-weak px-3 py-1 text-xs"
                :disabled="busy"
                @click="
                  editingComment = entry.id;
                  commentDraft = entry.body;
                "
              >
                {{ projectText('EDIT', 'Editar') }}
              </button>
              <button
                type="button"
                class="rounded border border-n-weak px-3 py-1 text-xs text-n-ruby-11"
                :disabled="busy"
                @click="action(`comments/${entry.id}`, 'delete')"
              >
                {{ projectText('DELETE', 'Excluir') }}
              </button>
            </div>
          </template>
        </article>
        <p
          v-if="detail?.comments?.length >= 100"
          class="text-n-slate-11 text-sm"
        >
          {{
            projectText(
              'COMMENTS_LIMIT',
              'Exibindo os 100 comentários mais recentes.'
            )
          }}
        </p>
        <TaskCommentRich
          v-if="editable"
          ref="newCommentComposer"
          :scope="commentScope"
          :disabled="busy"
          @change="comment = $event"
          @submit="saveRichComment(null, $event)"
          @draft-state="commentDraftAvailable = $event"
        />
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
          <span
            >{{ taskTitle(edge.predecessor_id) }}
            <span
              class="i-lucide-arrow-right inline-block size-3"
              aria-hidden="true"
            />
            {{ task.title }}</span
          ><button
            v-if="canDependencies"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
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
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('PREDECESSOR', 'Predecessora') }}</span
            ><select v-model="predecessor" required>
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
            </select></label
          ><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
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
          }}: {{ hours(detail?.worked_minutes) }}
          {{ projectText('HOUR_UNIT', 'h') }}
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
          <label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('TIME_DATE', 'Data') }}</span
            ><input v-model="timeForm.worked_on" type="date" required /></label
          ><label class="flex flex-col gap-1 min-w-0"
            ><span>{{
              projectText('TIME_MINUTES', 'Minutos trabalhados')
            }}</span
            ><input
              v-model.number="timeForm.minutes"
              type="number"
              min="1"
              max="1440"
              step="1"
              required /></label
          ><label class="flex flex-col gap-1 min-w-0"
            ><span>{{ projectText('TIME_NOTES', 'Observação') }}</span
            ><input v-model="timeForm.notes" maxlength="2000" /></label
          ><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed bg-n-blue-9 text-white"
            :disabled="busy"
          >
            {{ projectText('REGISTER_HOURS', 'Registrar horas') }}
          </button>
        </form>
      </section>
      <section v-else-if="tab === 'history'" class="flex flex-col gap-3">
        <h3>{{ projectText('TASK_ACTIVITY', 'Histórico da tarefa') }}</h3>
        <article
          v-for="event in detail?.recent_activity || []"
          :key="event.id"
          class="border-l-2 border-n-blue-5 py-2 pl-4"
        >
          <p class="font-medium">{{ taskEventLabel(event.action) }}</p>
          <p class="mt-1 text-xs text-n-slate-11">
            {{ event.actor?.name || projectText('SYSTEM', 'Sistema') }} ·
            {{ formatDate(event.created_at) }}
          </p>
        </article>
        <p
          v-if="!detail?.recent_activity?.length"
          class="py-6 text-center text-n-slate-11"
        >
          {{ projectText('NO_ACTIVITY', 'Nenhuma atividade registrada.') }}
        </p>
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
