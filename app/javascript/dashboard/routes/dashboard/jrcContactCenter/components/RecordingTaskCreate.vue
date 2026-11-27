<script setup>
import {
  computed,
  defineAsyncComponent,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
import OpsModal from '../../jrcOperations/components/OpsModal.vue';
import { request } from '../../jrcOperations/api';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  authorityKey: { type: String, required: true },
});

const emit = defineEmits(['close', 'changed']);

const TaskEditor = defineAsyncComponent(
  () => import('../../jrcOperations/components/TaskEditor.vue')
);

const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDING_TASKS.NEW'),
  HINT: t('JRC_CONTACT_CENTER.RECORDING_TASKS.CREATE_HINT'),
  SEARCH: t('JRC_CONTACT_CENTER.RECORDING_TASKS.SEARCH'),
  CHOOSE: t('JRC_CONTACT_CENTER.RECORDING_TASKS.CHOOSE'),
  LOADING: t('JRC_CONTACT_CENTER.RECORDING_TASKS.LOADING'),
  EMPTY: t('JRC_CONTACT_CENTER.RECORDING_TASKS.NO_PROJECTS'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDING_TASKS.DENIED'),
  NO_CREATE: t('JRC_CONTACT_CENTER.RECORDING_TASKS.NO_CREATE'),
  SCOPE_UNAVAILABLE: t('JRC_CONTACT_CENTER.RECORDING_TASKS.SCOPE_UNAVAILABLE'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDING_TASKS.ERROR'),
  UNKNOWN: t('JRC_CONTACT_CENTER.RECORDING_TASKS.UNKNOWN'),
  CHANGED: t('JRC_CONTACT_CENTER.RECORDING_TASKS.CHANGED'),
  PREVIOUS: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.NEXT'),
}));
const query = ref('');
const projects = ref([]);
const meta = ref(null);
const selected = ref(null);
const busy = ref(false);
const error = ref('');
let requestId;
let uncertainSignature;
let generation = 0;
let disposed = false;
const identity = () =>
  JSON.stringify([props.accountId, props.recordingId, props.authorityKey]);
const eligible = project =>
  project.capabilities?.includes('projects.task.create') &&
  !['completed', 'canceled'].includes(project.status);
const reset = () => {
  generation += 1;
  projects.value = [];
  meta.value = null;
  selected.value = null;
  requestId = undefined;
  uncertainSignature = undefined;
  busy.value = false;
  error.value = '';
};
const denied = failure => [401, 403, 404].includes(failure.response?.status);
const load = async (page = 1) => {
  if (busy.value || disposed) return;
  generation += 1;
  const current = generation;
  const scope = identity();
  busy.value = true;
  projects.value = [];
  meta.value = null;
  error.value = '';
  try {
    const result = await request(props.accountId, 'projects/projects', {
      params: { q: query.value, page, per_page: 20 },
    });
    if (disposed || current !== generation || scope !== identity()) return;
    if (
      !Array.isArray(result.data) ||
      !Number.isSafeInteger(result.meta?.total) ||
      result.meta.total < 0
    )
      throw new TypeError('Invalid native project page');
    projects.value = result.data;
    meta.value = {
      page,
      total: result.meta.total,
      pages: Math.ceil(result.meta.total / 20),
    };
  } catch (failure) {
    if (!disposed && current === generation && scope === identity())
      error.value = denied(failure) ? 'DENIED' : 'ERROR';
  } finally {
    if (!disposed && current === generation && scope === identity())
      busy.value = false;
  }
};
const choose = async project => {
  if (busy.value || disposed || !eligible(project)) return;
  generation += 1;
  const current = generation;
  const scope = identity();
  busy.value = true;
  error.value = '';
  try {
    const result = await request(
      props.accountId,
      `projects/projects/${project.id}`
    );
    if (disposed || current !== generation || scope !== identity()) return;
    if (
      String(result.data?.id) !== String(project.id) ||
      !Array.isArray(result.data.columns) ||
      !Array.isArray(result.data.members)
    )
      throw new TypeError('Invalid native project details');
    if (!eligible(result.data))
      throw new Error('Native task creation unavailable');
    requestId = crypto.randomUUID();
    selected.value = result.data;
  } catch (failure) {
    if (!disposed && current === generation && scope === identity())
      error.value = denied(failure) ? 'DENIED' : 'ERROR';
  } finally {
    if (!disposed && current === generation && scope === identity())
      busy.value = false;
  }
};
const createTask = async payload => {
  const project = selected.value;
  const current = generation;
  const scope = identity();
  if (disposed || !project || !requestId || !eligible(project))
    throw new Error(labels.value.CHANGED);
  const attributes = { ...payload.task };
  delete attributes.lock_version;
  const signature = JSON.stringify(attributes);
  if (uncertainSignature && uncertainSignature !== signature)
    throw new Error(labels.value.UNKNOWN);
  try {
    const { data } = await ContactCenterAPI.createRecordingTask(
      props.accountId,
      props.recordingId,
      {
        project_id: String(project.id),
        request_id: requestId,
        task: attributes,
      }
    );
    if (disposed || current !== generation || scope !== identity())
      throw new Error(labels.value.CHANGED);
    if (
      data?.account_id !== String(props.accountId) ||
      data.recording_id !== String(props.recordingId) ||
      typeof data.link_id !== 'string' ||
      !/^[1-9]\d{0,18}$/.test(data.link_id)
    )
      throw new TypeError('Invalid native task receipt');
    uncertainSignature = undefined;
  } catch (failure) {
    const status = failure.response?.status;
    uncertainSignature =
      !status || status >= 500 || status === 409 ? signature : undefined;
    if (uncertainSignature) throw new Error(labels.value.UNKNOWN);
    if (denied(failure)) throw new Error(labels.value.DENIED);
    if (failure.response?.data?.error === 'recording_task_scope_unavailable')
      throw new Error(labels.value.SCOPE_UNAVAILABLE);
    throw failure;
  }
};
watch(
  identity,
  () => {
    reset();
    emit('close');
  },
  { flush: 'sync' }
);
onMounted(() => load());
onBeforeUnmount(() => {
  disposed = true;
  reset();
});
</script>

<template>
  <TaskEditor
    v-if="selected"
    :project="selected"
    :create-request="createTask"
    @changed="emit('changed')"
    @close="emit('close')"
  />
  <OpsModal v-else :title="labels.TITLE" :busy="busy" @close="emit('close')">
    <div class="min-w-0 space-y-4" data-recording-task-project-picker>
      <p class="break-words text-sm text-n-slate-11">{{ labels.HINT }}</p>
      <form class="flex min-w-0 flex-wrap gap-2" @submit.prevent="load()">
        <input
          v-model="query"
          type="search"
          :aria-label="labels.SEARCH"
          :placeholder="labels.SEARCH"
          :disabled="busy"
          class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
        />
        <button
          type="submit"
          :disabled="busy"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm text-white disabled:opacity-50"
        >
          {{ labels.SEARCH }}
        </button>
      </form>
      <p v-if="error" role="alert" class="break-words text-sm text-n-ruby-11">
        {{ labels[error] }}
      </p>
      <p v-if="busy" role="status" class="text-sm">{{ labels.LOADING }}</p>
      <p v-else-if="!projects.length && !error" class="text-sm">
        {{ labels.EMPTY }}
      </p>
      <article
        v-for="project in projects"
        :key="project.id"
        class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
      >
        <h3 class="break-words text-sm font-medium">{{ project.name }}</h3>
        <button
          type="button"
          :disabled="busy || !eligible(project)"
          :data-create-task-project="project.id"
          class="max-w-full whitespace-normal rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-50"
          @click="choose(project)"
        >
          {{ eligible(project) ? labels.CHOOSE : labels.NO_CREATE }}
        </button>
      </article>
      <div v-if="meta && meta.pages > 1" class="flex flex-wrap gap-2">
        <button
          type="button"
          :disabled="busy || meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="load(meta.page - 1)"
        >
          {{ labels.PREVIOUS }}
        </button>
        <button
          type="button"
          :disabled="busy || meta.page >= meta.pages"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="load(meta.page + 1)"
        >
          {{ labels.NEXT }}
        </button>
      </div>
    </div>
  </OpsModal>
</template>
