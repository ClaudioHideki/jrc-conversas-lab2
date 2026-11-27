<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import EndingAttemptHistory from 'dashboard/routes/dashboard/inbox/EndingAttemptHistory.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  authorityKey: { type: String, required: true },
});
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.TITLE'),
  SOURCE: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.SOURCE'),
  LOAD: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.LOAD'),
  LOADING: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.LOADING'),
  EMPTY: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.EMPTY'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.DENIED'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.ERROR'),
  ATTENDANCE: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.ATTENDANCE'),
  ACW_COMPLETED: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.ACW_COMPLETED'),
  ACW_PENDING: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.ACW_PENDING'),
  ACW_NOT_STARTED: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.ACW_NOT_STARTED'),
  OPEN: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.OPEN'),
  PREVIOUS: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.NEXT'),
  LIMIT: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.LIMIT'),
}));
const text = key => labels.value[key];
const items = ref([]);
const meta = ref(null);
const selected = ref('');
const error = ref('');
const loading = ref(false);
const acwState = row => {
  if (row.completed_at) return 'ACW_COMPLETED';
  return row.started_at ? 'ACW_PENDING' : 'ACW_NOT_STARTED';
};
const attendanceLabel = row =>
  `${text('ATTENDANCE')} #${row.id} · ${text(acwState(row))}`;
const paginationLabel = computed(() =>
  meta.value
    ? `${meta.value.page} / ${Math.max(meta.value.pages, 1)} · ${meta.value.total}`
    : ''
);
const identity = computed(() =>
  JSON.stringify([
    props.accountId,
    props.recordingId,
    props.callSessionId,
    props.callId,
    props.authorityKey,
  ])
);
let generation = 0;
let disposed = false;
const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
const timestamp = value =>
  value === null ||
  (typeof value === 'string' && Number.isFinite(Date.parse(value)));
const validPage = (body, page) =>
  body?.contract_version === 1 &&
  body.account_id === String(props.accountId) &&
  body.recording_id === String(props.recordingId) &&
  body.call_session_id === String(props.callSessionId) &&
  body.call_id === props.callId &&
  Array.isArray(body.items) &&
  body.items.length <= 20 &&
  new Set(body.items.map(row => row.id)).size === body.items.length &&
  body.items.every(
    row =>
      identifier(row.id) &&
      identifier(row.account_user_id) &&
      timestamp(row.started_at) &&
      timestamp(row.completed_at)
  ) &&
  body.meta?.page === page &&
  body.meta.per_page === 20 &&
  Number.isSafeInteger(body.meta.total) &&
  body.meta.total >= 0 &&
  body.meta.pages === Math.ceil(body.meta.total / 20) &&
  body.items.length ===
    Math.min(20, Math.max(0, body.meta.total - (page - 1) * 20));
const reset = () => {
  generation += 1;
  items.value = [];
  meta.value = null;
  selected.value = '';
  error.value = '';
  loading.value = false;
};
async function load(page = 1) {
  if (loading.value || disposed) return;
  reset();
  const own = generation;
  const scope = identity.value;
  loading.value = true;
  try {
    const { data } = await API.recordingEndingContext(
      props.accountId,
      props.recordingId,
      page
    );
    if (disposed || own !== generation || scope !== identity.value) return;
    if (!validPage(data, page))
      throw new Error('recording_ending_context_identity_mismatch');
    items.value = data.items;
    meta.value = data.meta;
  } catch (failure) {
    if (disposed || own !== generation || scope !== identity.value) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? 'DENIED'
      : 'ERROR';
  } finally {
    if (!disposed && own === generation) loading.value = false;
  }
}
watch(identity, reset, { flush: 'sync' });
onBeforeUnmount(() => {
  disposed = true;
  reset();
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-violet-6 p-3 text-sm text-n-slate-12"
    data-recording-ending-actions
  >
    <h3 class="font-semibold">{{ text('TITLE') }}</h3>
    <p class="text-xs text-n-slate-11">{{ text('SOURCE') }}</p>
    <button
      type="button"
      :disabled="loading"
      class="rounded-lg border border-n-violet-6 px-3 py-2 text-n-violet-11"
      data-recording-actions-load
      @click="load(1)"
    >
      {{ text(loading ? 'LOADING' : 'LOAD') }}
    </button>
    <p v-if="loading" role="status">{{ text('LOADING') }}</p>
    <p v-else-if="error" role="alert" class="text-n-ruby-11">
      {{ text(error) }}
    </p>
    <p
      v-else-if="meta && !items.length"
      role="status"
      data-recording-actions-empty
    >
      {{ text('EMPTY') }}
    </p>
    <div
      v-for="row in items"
      :key="row.id"
      class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
    >
      <p class="break-words">
        {{ attendanceLabel(row) }}
      </p>
      <button
        type="button"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
        :data-recording-actions-select="row.id"
        :aria-expanded="selected === row.id"
        @click="selected = selected === row.id ? '' : row.id"
      >
        {{ text('OPEN') }}
      </button>
      <EndingAttemptHistory
        v-if="selected === row.id"
        :key="`${identity}-${row.id}`"
        :account-id="accountId"
        :qualification-id="row.id"
        :authority-key="identity"
        read-only
      />
    </div>
    <div v-if="meta" class="flex flex-wrap gap-2">
      <button
        type="button"
        :disabled="loading || meta.page <= 1"
        class="rounded-lg border border-n-weak px-3 py-2"
        data-recording-actions-previous
        @click="load(meta.page - 1)"
      >
        {{ text('PREVIOUS') }}
      </button>
      <span class="py-2">{{ paginationLabel }}</span>
      <button
        type="button"
        :disabled="loading || meta.page >= meta.pages"
        class="rounded-lg border border-n-weak px-3 py-2"
        data-recording-actions-next
        @click="load(meta.page + 1)"
      >
        {{ text('NEXT') }}
      </button>
    </div>
    <p class="text-xs text-n-slate-11">{{ text('LIMIT') }}</p>
  </section>
</template>
