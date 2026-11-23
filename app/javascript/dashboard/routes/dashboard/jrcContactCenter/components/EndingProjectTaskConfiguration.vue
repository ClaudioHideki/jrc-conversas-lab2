<script setup>
import { useEndingAutomationLabels } from '../composables/useEndingAutomationLabels';
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { request } from '../../jrcOperations/api';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  value: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'cancel', 'denied']);
const text = useEndingAutomationLabels();
const clone = value => JSON.parse(JSON.stringify(value));
const values = ref(
  clone(
    props.value || {
      project_id: '',
      due_after_days: null,
      attributes: {
        title: '',
        priority: '',
        estimated_minutes: 0,
        board_column_id: '',
      },
    }
  )
);
const q = ref('');
const page = ref(1);
const pages = ref(0);
const projects = ref([]);
const project = ref(null);
const loading = ref(false);
const listLoading = ref(false);
const error = ref('');
let listGeneration = 0;
let detailGeneration = 0;
const eligible = row =>
  row.capabilities?.includes('projects.task.create') &&
  !['completed', 'canceled'].includes(row.status);
const valid = computed(
  () =>
    project.value &&
    eligible(project.value) &&
    values.value.project_id === String(project.value.id) &&
    values.value.attributes.title.trim() &&
    ['low', 'medium', 'high', 'urgent'].includes(
      values.value.attributes.priority
    ) &&
    Number.isInteger(values.value.attributes.estimated_minutes) &&
    values.value.attributes.estimated_minutes >= 0 &&
    project.value.columns.some(
      column =>
        String(column.id) === values.value.attributes.board_column_id &&
        column.status_key !== 'completed'
    ) &&
    (values.value.due_after_days === null ||
      (Number.isInteger(values.value.due_after_days) &&
        values.value.due_after_days >= 0 &&
        values.value.due_after_days <= 3650))
);
const loadProjects = async () => {
  listGeneration += 1;
  const generation = listGeneration;
  const account = String(props.accountId);
  listLoading.value = true;
  projects.value = [];
  error.value = '';
  try {
    const result = await request(account, 'projects/projects', {
      params: { q: q.value, page: page.value, per_page: 20 },
    });
    if (generation !== listGeneration || account !== String(props.accountId))
      return;
    projects.value = result.data.filter(eligible);
    pages.value = result.meta.pages;
  } catch (failure) {
    if (generation === listGeneration) {
      if ([401, 403].includes(failure?.response?.status)) emit('denied');
      else error.value = 'PROJECT_FAILED';
    }
  } finally {
    if (generation === listGeneration) listLoading.value = false;
  }
};
const selectProject = async id => {
  detailGeneration += 1;
  const generation = detailGeneration;
  const account = String(props.accountId);
  const previous = values.value.project_id;
  values.value.project_id = id;
  project.value = null;
  error.value = '';
  loading.value = false;
  if (previous !== id) {
    values.value.attributes.board_column_id = '';
    delete values.value.attributes.assignee_id;
    delete values.value.attributes.parent_id;
  }
  if (!id) return;
  loading.value = true;
  try {
    const result = await request(account, `projects/projects/${id}`);
    if (generation !== detailGeneration || account !== String(props.accountId))
      return;
    if (String(result.data.id) !== id || !eligible(result.data))
      throw new Error('Destination unavailable');
    project.value = result.data;
  } catch (failure) {
    if (generation === detailGeneration) {
      if ([401, 403, 404].includes(failure?.response?.status)) emit('denied');
      else error.value = 'PROJECT_FAILED';
    }
  } finally {
    if (generation === detailGeneration) loading.value = false;
  }
};
const updateOffset = event => {
  values.value.due_after_days =
    event.target.value === '' ? null : Number(event.target.value);
  if (values.value.due_after_days !== null)
    delete values.value.attributes.due_on;
};
const submit = () => {
  if (props.disabled || !valid.value || loading.value || listLoading.value)
    return;
  emit('save', clone(values.value));
};
watch(q, () => {
  page.value = 1;
});
watch(() => [props.accountId, q.value, page.value], loadProjects, {
  immediate: true,
});
watch(
  () => props.accountId,
  () => {
    values.value.project_id = '';
    project.value = null;
    detailGeneration += 1;
  }
);
if (values.value.project_id) selectProject(values.value.project_id);
onBeforeUnmount(() => {
  listGeneration += 1;
  detailGeneration += 1;
  projects.value = [];
  project.value = null;
});
</script>

<template>
  <form
    class="min-w-0 space-y-4"
    data-ending-project-configuration
    @submit.prevent="submit"
  >
    <h3 class="text-base font-semibold">{{ text('PROJECT_CONFIGURE') }}</h3>
    <p class="text-sm text-n-slate-11">{{ text('PROJECT_AUTHORITY') }}</p>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ text(error) }}
    </p>
    <fieldset :disabled="disabled" class="grid min-w-0 gap-3 sm:grid-cols-2">
      <label class="min-w-0 text-sm">
        {{ text('PROJECT_SEARCH') }}
        <input
          v-model="q"
          maxlength="100"
          type="search"
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-project-search
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ text('PROJECT') }}
        <select
          :value="values.project_id"
          :disabled="listLoading || loading"
          required
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-project
          @change="selectProject($event.target.value)"
        >
          <option value="">{{ text('SELECT') }}</option>
          <option
            v-if="
              project &&
              !projects.some(row => String(row.id) === values.project_id)
            "
            :value="values.project_id"
          >
            {{ project.name }}
          </option>
          <option v-for="row in projects" :key="row.id" :value="String(row.id)">
            {{ row.name }}
          </option>
        </select>
      </label>
      <div class="flex flex-wrap gap-2 sm:col-span-2">
        <button
          type="button"
          :disabled="listLoading || page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-40"
          @click="page -= 1"
        >
          {{ text('PREVIOUS') }}
        </button>
        <button
          type="button"
          :disabled="listLoading || page >= pages"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-40"
          @click="page += 1"
        >
          {{ text('NEXT') }}
        </button>
      </div>
      <label class="min-w-0 text-sm sm:col-span-2">
        {{ text('TASK_TITLE') }}
        <input
          v-model="values.attributes.title"
          maxlength="240"
          required
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-task-title
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ text('COLUMN') }}
        <select
          v-model="values.attributes.board_column_id"
          required
          :disabled="loading || !project"
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-task-column
        >
          <option value="">{{ text('SELECT') }}</option>
          <option
            v-for="column in project?.columns.filter(
              row => row.status_key !== 'completed'
            ) || []"
            :key="column.id"
            :value="String(column.id)"
          >
            {{ column.name }}
          </option>
        </select>
      </label>
      <label class="min-w-0 text-sm">
        {{ text('PRIORITY') }}
        <select
          v-model="values.attributes.priority"
          required
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-task-priority
        >
          <option value="">{{ text('SELECT') }}</option>
          <option
            v-for="priority in ['low', 'medium', 'high', 'urgent']"
            :key="priority"
            :value="priority"
          >
            {{ text(`PRIORITIES.${priority}`) }}
          </option>
        </select>
      </label>
      <label class="min-w-0 text-sm">
        {{ text('ESTIMATE') }}
        <input
          v-model.number="values.attributes.estimated_minutes"
          type="number"
          min="0"
          max="2147483647"
          required
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ text('DUE_OFFSET') }}
        <input
          :value="values.due_after_days ?? ''"
          type="number"
          min="0"
          max="3650"
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-task-due
          @input="updateOffset"
        />
      </label>
      <label
        v-if="project?.capabilities.includes('projects.task.assign')"
        class="min-w-0 text-sm sm:col-span-2"
      >
        {{ text('ASSIGNEE') }}
        <select
          v-model="values.attributes.assignee_id"
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-task-assignee
        >
          <option :value="undefined">{{ text('UNASSIGNED') }}</option>
          <option
            v-for="member in project.members || []"
            :key="member.user_id"
            :value="String(member.user_id)"
          >
            {{ member.user.name }}
          </option>
        </select>
      </label>
    </fieldset>
    <details
      v-if="value"
      class="min-w-0 rounded-lg border border-n-weak p-3 text-sm"
    >
      <summary>{{ text('EXISTING_PARAMETERS') }}</summary>
      <pre class="mt-2 whitespace-pre-wrap break-all">{{
        JSON.stringify(values, null, 2)
      }}</pre>
    </details>
    <p
      v-if="loading || listLoading"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ text('LOADING') }}
    </p>
    <div class="flex flex-wrap gap-3">
      <button
        type="submit"
        :disabled="disabled || !valid || loading || listLoading"
        class="rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
        data-ending-task-apply
      >
        {{ text('APPLY') }}
      </button>
      <button
        type="button"
        :disabled="disabled"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
        @click="emit('cancel')"
      >
        {{ text('BACK') }}
      </button>
    </div>
  </form>
</template>
