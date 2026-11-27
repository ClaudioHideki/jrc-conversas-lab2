<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDate, request } from '../jrcOperations/api';
import { projectTaskStatuses } from '../jrcProjects/taskBoard';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  projectId: { type: [String, Number], required: true },
  taskId: { type: [String, Number], required: true },
  authorityKey: { type: String, required: true },
});
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.TITLE'),
  HINT: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.HINT'),
  LOAD: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.LOAD'),
  REFRESH: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.REFRESH'),
  LOADING: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.LOADING'),
  STATUS: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.STATUS'),
  ASSIGNEE: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.ASSIGNEE'),
  DUE: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.DUE'),
  UNASSIGNED: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.UNASSIGNED'),
  NO_DUE: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.NO_DUE'),
  DENIED: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.DENIED'),
  ERROR: t('JRC_CONTACT_CENTER.ENDING_TASK_STATE.ERROR'),
}));
const state = ref(null);
const busy = ref(false);
const error = ref('');
let generation = 0;
let controller;
let disposed = false;
const identity = () =>
  JSON.stringify([
    props.accountId,
    props.projectId,
    props.taskId,
    props.authorityKey,
  ]);
const identifier = value =>
  /^[1-9]\d{0,18}$/.test(String(value)) &&
  (typeof value !== 'number' || Number.isSafeInteger(value));
const validTask = task =>
  task &&
  String(task.id) === String(props.taskId) &&
  String(task.project_id) === String(props.projectId) &&
  Object.hasOwn(projectTaskStatuses, task.status) &&
  (task.due_on === null || /^\d{4}-\d{2}-\d{2}$/.test(task.due_on)) &&
  (task.assignee_id === null
    ? task.assignee === null
    : identifier(task.assignee_id) &&
      String(task.assignee?.id) === String(task.assignee_id) &&
      typeof task.assignee.name === 'string');
const reset = () => {
  generation += 1;
  controller?.abort();
  controller = undefined;
  state.value = null;
  busy.value = false;
  error.value = '';
};
const load = async () => {
  if (busy.value || disposed) return;
  reset();
  const current = generation;
  const scope = identity();
  busy.value = true;
  controller = new AbortController();
  try {
    if (![props.accountId, props.projectId, props.taskId].every(identifier))
      throw new TypeError('Invalid native task identity');
    const { data } = await request(
      props.accountId,
      `projects/projects/${props.projectId}/tasks/${props.taskId}`,
      { signal: controller.signal }
    );
    if (disposed || current !== generation || scope !== identity()) return;
    if (!validTask(data)) throw new TypeError('Invalid native task response');
    // Retain only the requested live state, never comments, files, descriptions,
    // provider data or a copied version of the immutable execution receipt.
    state.value = {
      status: data.status,
      assignee: data.assignee?.name ?? null,
      dueOn: data.due_on,
    };
  } catch (failure) {
    if (disposed || current !== generation || scope !== identity()) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? 'DENIED'
      : 'ERROR';
  } finally {
    if (!disposed && current === generation && scope === identity()) {
      busy.value = false;
      controller = undefined;
    }
  }
};
const statusLabel = computed(() => projectTaskStatuses[state.value?.status]);
watch(identity, reset, { flush: 'sync' });
onBeforeUnmount(() => {
  disposed = true;
  reset();
});
</script>

<template>
  <section
    class="my-3 min-w-0 space-y-2 rounded-lg border border-n-weak bg-n-solid-1 p-3"
    data-ending-task-current-state
  >
    <h5 class="break-words text-sm font-semibold">
      {{ labels.TITLE }}
    </h5>
    <p class="break-words text-xs text-n-slate-11">{{ labels.HINT }}</p>
    <p v-if="busy" role="status" class="text-sm">
      {{ labels.LOADING }}
    </p>
    <p v-if="error" role="alert" class="break-words text-sm text-n-ruby-11">
      {{ labels[error] }}
    </p>
    <dl v-if="state" class="grid min-w-0 gap-2 text-sm sm:grid-cols-3">
      <div class="min-w-0">
        <dt class="text-xs text-n-slate-11">{{ labels.STATUS }}</dt>
        <dd class="break-words font-medium" data-native-task-status>
          {{ statusLabel }}
        </dd>
      </div>
      <div class="min-w-0">
        <dt class="text-xs text-n-slate-11">{{ labels.ASSIGNEE }}</dt>
        <dd class="break-words" data-native-task-assignee>
          {{ state.assignee || labels.UNASSIGNED }}
        </dd>
      </div>
      <div class="min-w-0">
        <dt class="text-xs text-n-slate-11">{{ labels.DUE }}</dt>
        <dd class="break-words" data-native-task-due>
          <time v-if="state.dueOn" :datetime="state.dueOn">{{
            formatDate(state.dueOn)
          }}</time>
          <span v-else>{{ labels.NO_DUE }}</span>
        </dd>
      </div>
    </dl>
    <button
      type="button"
      :disabled="busy || error === 'DENIED'"
      class="max-w-full whitespace-normal rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-50"
      data-load-native-task-state
      @click="load"
    >
      {{ state ? labels.REFRESH : labels.LOAD }}
    </button>
  </section>
</template>
