<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import EndingTaskState from '../../inbox/EndingTaskState.vue';
import { destinationHistoryRoute } from '../../inbox/endingDestinationHistoryContract';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  authorityKey: { type: String, required: true },
  revision: { type: Number, default: 0 },
});
const emit = defineEmits(['create']);
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDING_TASKS.TITLE'),
  HINT: t('JRC_CONTACT_CENTER.RECORDING_TASKS.HINT'),
  NEW: t('JRC_CONTACT_CENTER.RECORDING_TASKS.NEW'),
  EMPTY: t('JRC_CONTACT_CENTER.RECORDING_TASKS.EMPTY'),
  NO_MODULE: t('JRC_CONTACT_CENTER.RECORDING_TASKS.NO_MODULE'),
  AUTHOR: t('JRC_CONTACT_CENTER.RECORDING_TASKS.AUTHOR'),
  CREATED: t('JRC_CONTACT_CENTER.RECORDING_TASKS.CREATED'),
  CORRELATION: t('JRC_CONTACT_CENTER.RECORDING_TASKS.CORRELATION'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDING_TASKS.DENIED'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDING_TASKS.ERROR'),
  LOADING: t('JRC_CONTACT_CENTER.RECORDING_TASKS.LOADING'),
  OPEN: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.OPEN_TASK'),
  REFRESH: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.REFRESH'),
  UNAVAILABLE: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.TARGET_UNAVAILABLE'),
  PREVIOUS: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.NEXT'),
}));
const rows = ref([]);
const meta = ref(null);
const timezone = ref('UTC');
const available = ref(false);
const loading = ref(false);
const error = ref('');
let generation = 0;
let disposed = false;
const identity = () =>
  JSON.stringify([
    props.accountId,
    props.recordingId,
    props.callSessionId,
    props.callId,
    props.authorityKey,
  ]);
const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
const validRow = row =>
  identifier(row.id) &&
  identifier(row.account_user_id) &&
  typeof row.created_at === 'string' &&
  Number.isFinite(Date.parse(row.created_at)) &&
  typeof row.request_id === 'string' &&
  /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/.test(row.request_id) &&
  (row.target === null ||
    (row.target?.kind === 'project_task' &&
      identifier(row.target.id) &&
      identifier(row.target.project_id)));
const validPage = (body, page) =>
  body?.contract_version === 1 &&
  body.account_id === String(props.accountId) &&
  body.recording_id === String(props.recordingId) &&
  body.call_session_id === String(props.callSessionId) &&
  body.call_id === props.callId &&
  typeof body.timezone === 'string' &&
  typeof body.project_module_available === 'boolean' &&
  Array.isArray(body.items) &&
  body.items.length <= 20 &&
  body.items.every(validRow) &&
  new Set(body.items.map(row => row.id)).size === body.items.length &&
  body.meta?.page === page &&
  body.meta.per_page === 20 &&
  Number.isSafeInteger(body.meta.total) &&
  body.meta.total >= 0 &&
  body.meta.pages === Math.ceil(body.meta.total / 20) &&
  body.items.length ===
    Math.min(20, Math.max(0, body.meta.total - (page - 1) * 20));
const reset = () => {
  generation += 1;
  rows.value = [];
  meta.value = null;
  available.value = false;
  timezone.value = 'UTC';
  loading.value = false;
  error.value = '';
};
const load = async (page = 1) => {
  if (loading.value || disposed) return;
  reset();
  const current = generation;
  const scope = identity();
  loading.value = true;
  try {
    const { data } = await API.recordingTasks(
      props.accountId,
      props.recordingId,
      page
    );
    if (disposed || current !== generation || scope !== identity()) return;
    if (!validPage(data, page))
      throw new TypeError('Invalid native call task page');
    new Intl.DateTimeFormat('pt-BR', { timeZone: data.timezone }).format(
      new Date()
    );
    rows.value = data.items;
    meta.value = data.meta;
    available.value = data.project_module_available;
    timezone.value = data.timezone;
  } catch (failure) {
    if (!disposed && current === generation && scope === identity())
      error.value = [401, 403, 404].includes(failure.response?.status)
        ? 'DENIED'
        : 'ERROR';
  } finally {
    if (!disposed && current === generation && scope === identity())
      loading.value = false;
  }
};
const timestamp = value =>
  new Intl.DateTimeFormat('pt-BR', {
    timeZone: timezone.value,
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
watch(identity, reset, { flush: 'sync' });
watch(
  () => props.revision,
  () => {
    if (!disposed) load(1);
  }
);
onMounted(() => load());
onBeforeUnmount(() => {
  disposed = true;
  reset();
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 p-3 text-sm"
    data-recording-manual-tasks
  >
    <div class="flex min-w-0 flex-wrap items-center justify-between gap-2">
      <h3 class="break-words font-semibold">{{ labels.TITLE }}</h3>
      <button
        v-if="available"
        type="button"
        :disabled="loading"
        data-recording-new-task
        class="max-w-full whitespace-normal rounded-lg bg-n-blue-9 px-3 py-2 text-sm text-white disabled:opacity-50"
        @click="emit('create')"
      >
        {{ labels.NEW }}
      </button>
    </div>
    <p class="break-words text-xs text-n-slate-11">{{ labels.HINT }}</p>
    <p v-if="loading" role="status">{{ labels.LOADING }}</p>
    <p v-if="error" role="alert" class="break-words text-n-ruby-11">
      {{ labels[error] }}
    </p>
    <p v-if="meta && !rows.length && !error" data-no-recording-manual-tasks>
      {{ labels.EMPTY }}
    </p>
    <p v-if="meta && !available" class="text-xs text-n-slate-11">
      {{ labels.NO_MODULE }}
    </p>
    <article
      v-for="row in rows"
      :key="row.id"
      class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
      data-recording-manual-task-row
    >
      <dl class="grid min-w-0 gap-2 sm:grid-cols-2">
        <div class="min-w-0">
          <dt class="text-xs text-n-slate-11">{{ labels.AUTHOR }}</dt>
          <dd class="break-all">{{ row.account_user_id }}</dd>
        </div>
        <div class="min-w-0">
          <dt class="text-xs text-n-slate-11">{{ labels.CREATED }}</dt>
          <dd>
            <time :datetime="row.created_at">{{
              timestamp(row.created_at)
            }}</time>
          </dd>
        </div>
        <div class="min-w-0 sm:col-span-2">
          <dt class="text-xs text-n-slate-11">{{ labels.CORRELATION }}</dt>
          <dd class="break-all">{{ row.request_id }}</dd>
        </div>
      </dl>
      <template v-if="row.target">
        <EndingTaskState
          :account-id="accountId"
          :project-id="row.target.project_id"
          :task-id="row.target.id"
          :authority-key="authorityKey"
        />
        <router-link
          :to="destinationHistoryRoute(row.target, accountId)"
          class="inline-flex max-w-full rounded-lg border border-n-weak px-3 py-2 text-n-blue-11"
          data-open-recording-manual-task
        >
          {{ labels.OPEN }}
        </router-link>
      </template>
      <p v-else class="text-xs text-n-slate-11">{{ labels.UNAVAILABLE }}</p>
    </article>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        :disabled="loading || error === 'DENIED'"
        class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
        @click="load(meta?.page || 1)"
      >
        {{ labels.REFRESH }}
      </button>
      <button
        v-if="meta && meta.pages > 1"
        type="button"
        :disabled="loading || meta.page <= 1"
        class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
        @click="load(meta.page - 1)"
      >
        {{ labels.PREVIOUS }}
      </button>
      <button
        v-if="meta && meta.pages > 1"
        type="button"
        :disabled="loading || meta.page >= meta.pages"
        class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
        @click="load(meta.page + 1)"
      >
        {{ labels.NEXT }}
      </button>
    </div>
  </section>
</template>
