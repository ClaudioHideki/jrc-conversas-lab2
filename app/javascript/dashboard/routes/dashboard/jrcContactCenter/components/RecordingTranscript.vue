<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
});
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.TITLE'),
  SEARCH: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.SEARCH'),
  ORIGINAL: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.ORIGINAL'),
  NO_TIMESTAMPS: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.NO_TIMESTAMPS'),
  EMPTY: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.EMPTY'),
  NO_MATCHES: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.NO_MATCHES'),
  SOURCE: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.SOURCE'),
  LOADING: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.ERROR'),
  UNAVAILABLE: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.UNAVAILABLE'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.DENIED'),
  RETRY: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.RETRY'),
}));
const source = ref(null);
const loading = ref(false);
const error = ref('');
const query = ref('');
let generation = 0;
const original = computed(() => source.value?.text || '');
const filtered = computed(() => {
  const value = query.value.trim().toLocaleLowerCase('pt-BR');
  return original.value
    .split('\n')
    .filter(line => line.toLocaleLowerCase('pt-BR').includes(value));
});
async function load() {
  generation += 1;
  const own = generation;
  const account = String(props.accountId);
  const recording = String(props.recordingId);
  const call = props.callId;
  source.value = null;
  error.value = '';
  loading.value = true;
  try {
    const { data } = await API.recordingTranscript(account, recording);
    if (own !== generation) return;
    const valid =
      String(data.account_id) === account &&
      String(data.recording_id) === recording &&
      data.call_id === call &&
      (data.text === null || typeof data.text === 'string') &&
      typeof data.source_sha256 === 'string' &&
      /^[0-9a-f]{64}$/.test(data.source_sha256) &&
      Array.isArray(data.segments) &&
      !data.segments.length &&
      data.temporal_alignment === 'not_supplied_by_native_source';
    if (!valid) throw new Error('transcript_source_identity_mismatch');
    source.value = data;
  } catch (failure) {
    if (own !== generation) return;
    const status = failure.response?.status;
    if ([401, 403, 404].includes(status)) error.value = 'DENIED';
    else if (
      status === 503 ||
      failure.response?.data?.error === 'quality_analysis_source_unavailable'
    )
      error.value = 'UNAVAILABLE';
    else error.value = 'ERROR';
  } finally {
    if (own === generation) loading.value = false;
  }
}
watch(
  () => [props.accountId, props.recordingId, props.callId],
  () => {
    query.value = '';
    load();
  },
  { immediate: true, flush: 'pre' }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-violet-6 p-3 text-n-slate-12"
    data-recording-transcript
  >
    <h3 class="font-semibold">{{ labels.TITLE }}</h3>
    <p v-if="loading" role="status">{{ labels.LOADING }}</p>
    <div v-else-if="error" class="space-y-2">
      <p role="alert" class="text-n-ruby-11">{{ labels[error] }}</p>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2"
        data-transcript-retry
        @click="load"
      >
        {{ labels.RETRY }}
      </button>
    </div>
    <template v-else-if="source">
      <p class="text-xs text-n-slate-11">{{ labels.ORIGINAL }}</p>
      <p
        class="rounded-lg bg-n-alpha-1 p-3 text-n-slate-11"
        data-transcript-timing-limit
      >
        {{ labels.NO_TIMESTAMPS }}
      </p>
      <p v-if="!original.trim()" data-transcript-empty>{{ labels.EMPTY }}</p>
      <template v-else>
        <label class="block min-w-0">
          <span class="mb-1 block text-xs text-n-slate-11">{{
            labels.SEARCH
          }}</span>
          <input
            v-model="query"
            type="search"
            maxlength="100"
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-n-slate-12"
            data-transcript-search
          />
        </label>
        <div
          class="max-h-72 min-w-0 overflow-y-auto rounded-lg border border-n-weak p-3"
          data-transcript-text
        >
          <p v-if="!query.trim()" class="m-0 whitespace-pre-wrap break-words">
            {{ original }}
          </p>
          <template v-else>
            <p v-if="!filtered.length" data-transcript-no-matches>
              {{ labels.NO_MATCHES }}
            </p>
            <p
              v-for="(line, index) in filtered"
              :key="index"
              class="whitespace-pre-wrap break-words"
              data-transcript-block
            >
              {{ line }}
            </p>
          </template>
        </div>
      </template>
      <p class="break-all text-xs text-n-slate-11" data-transcript-source>
        {{ `${labels.SOURCE}: ${source.source_sha256}` }}
      </p>
    </template>
  </section>
</template>
