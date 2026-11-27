<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
});
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.TITLE'),
  LOADING: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.ERROR'),
  DENIED: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.DENIED'),
  EMPTY: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.EMPTY'),
  REVISION: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.REVISION'),
  AUTHOR: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.AUTHOR'),
  ORIGINAL: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.ORIGINAL'),
  HUMAN: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.HUMAN'),
  QUALITY: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.QUALITY'),
  SENTIMENT: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.SENTIMENT'),
  REASON: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.REASON'),
  PREVIOUS: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.NEXT'),
  RETRY: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.RETRY'),
  UNKNOWN: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.UNKNOWN'),
  POSITIVE: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.POSITIVE'),
  NEUTRAL: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.NEUTRAL'),
  NEGATIVE: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.NEGATIVE'),
  SOURCE: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.SOURCE'),
  SOURCE_VERSION: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.SOURCE_VERSION'),
  MODEL: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.MODEL'),
  COLON: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.COLON'),
  SEPARATOR: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.SEPARATOR'),
}));
const rows = ref([]);
const meta = ref(null);
const timezone = ref('');
const page = ref(1);
const loading = ref(false);
const error = ref('');
let generation = 0;
const classes = ['positive', 'neutral', 'negative'];
const positive = value => /^[1-9]\d*$/.test(String(value));
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const validRow = row =>
  row &&
  positive(row.id) &&
  positive(row.actor_id) &&
  Number.isInteger(row.revision) &&
  row.revision > 0 &&
  row.origin === 'human' &&
  hash(row.source_sha256) &&
  Number.isFinite(Date.parse(row.created_at)) &&
  classes.includes(row.values?.classification) &&
  typeof row.values?.adjusted_summary === 'string' &&
  typeof row.values?.justification === 'string' &&
  !!row.values.justification.trim() &&
  row.original &&
  typeof row.original === 'object' &&
  !Array.isArray(row.original) &&
  (row.original.resumo_conversa == null ||
    typeof row.original.resumo_conversa === 'string');
const display = value => value ?? labels.value.UNKNOWN;
const timestamp = value =>
  new Intl.DateTimeFormat('pt-BR', {
    timeZone: timezone.value,
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
const footer = computed(() =>
  t('JRC_CONTACT_CENTER.QUALITY_HISTORY.PAGE', {
    page: meta.value?.page || page.value,
    total: meta.value?.total || 0,
  })
);
async function load(requested = 1) {
  generation += 1;
  const own = generation;
  const account = String(props.accountId);
  const recording = String(props.recordingId);
  page.value = requested;
  rows.value = [];
  meta.value = null;
  error.value = '';
  loading.value = true;
  try {
    const { data } = await API.qualityReviewHistory(account, recording, {
      page: requested,
      per_page: 20,
    });
    if (own !== generation) return;
    const valid =
      String(data.account_id) === account &&
      String(data.recording_id) === recording &&
      typeof data.timezone === 'string' &&
      data.meta?.page === requested &&
      data.meta?.per_page === 20 &&
      Number.isInteger(data.meta?.total) &&
      data.meta.total >= 0 &&
      Array.isArray(data.items) &&
      data.items.length <= 20 &&
      data.items.length ===
        Math.min(20, Math.max(0, data.meta.total - (requested - 1) * 20)) &&
      data.items.every(validRow) &&
      new Set(data.items.map(row => String(row.id))).size === data.items.length;
    if (!valid) throw new Error('native_quality_history_identity_mismatch');
    new Intl.DateTimeFormat('pt-BR', { timeZone: data.timezone }).format();
    timezone.value = data.timezone;
    rows.value = data.items;
    meta.value = data.meta;
  } catch (failure) {
    if (own !== generation) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? 'DENIED'
      : 'ERROR';
  } finally {
    if (own === generation) loading.value = false;
  }
}
watch(
  () => [props.accountId, props.recordingId],
  () => load(1),
  { immediate: true, flush: 'pre' }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-violet-6 p-3 text-n-slate-12"
    data-quality-review-history
  >
    <h3 class="font-semibold">{{ labels.TITLE }}</h3>
    <p v-if="loading" role="status">{{ labels.LOADING }}</p>
    <div v-else-if="error" class="space-y-2">
      <p role="alert" class="text-n-ruby-11">{{ labels[error] }}</p>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2"
        data-quality-history-retry
        @click="load(page)"
      >
        {{ labels.RETRY }}
      </button>
    </div>
    <template v-else-if="meta">
      <p
        class="break-words text-xs text-n-slate-11"
        data-quality-history-source
      >
        {{ labels.SOURCE }} {{ timezone }}
      </p>
      <p v-if="!rows.length" data-quality-history-empty>{{ labels.EMPTY }}</p>
      <div class="max-h-96 min-w-0 space-y-2 overflow-y-auto">
        <details
          v-for="(row, index) in rows"
          :key="row.id"
          :open="index === 0"
          class="min-w-0 rounded-lg border border-n-weak p-3"
          :data-quality-history-revision="row.revision"
        >
          <summary class="cursor-pointer break-words font-semibold">
            {{ labels.REVISION }} {{ row.revision }} {{ labels.SEPARATOR }}
            {{ labels[row.values.classification.toUpperCase()] }}
            <span class="block text-xs font-normal text-n-slate-11">
              {{ labels.AUTHOR }} {{ row.actor_id }} {{ labels.SEPARATOR }}
              {{ timestamp(row.created_at) }}
            </span>
          </summary>
          <div class="mt-3 grid min-w-0 gap-3 sm:grid-cols-2">
            <div
              class="min-w-0 rounded-lg border border-n-weak bg-n-alpha-1 p-3"
            >
              <h4 class="mb-2 font-semibold">{{ labels.ORIGINAL }}</h4>
              <p
                class="whitespace-pre-wrap break-words"
                data-quality-history-original
              >
                {{ display(row.original.resumo_conversa) }}
              </p>
              <p class="break-words">
                {{ labels.SENTIMENT }}{{ labels.COLON }}
                {{ display(row.original.sentimento_cliente) }}
              </p>
              <p data-quality-history-quality>
                {{ labels.QUALITY }}{{ labels.COLON }}
                {{ display(row.original.nota_final) }}
              </p>
              <p class="break-words">
                {{ labels.MODEL }}{{ labels.COLON }}
                {{ display(row.original.model) }}
              </p>
            </div>
            <div class="min-w-0 rounded-lg border border-n-violet-6 p-3">
              <h4 class="mb-2 font-semibold">{{ labels.HUMAN }}</h4>
              <p
                class="whitespace-pre-wrap break-words"
                data-quality-history-adjusted
              >
                {{ row.values.adjusted_summary }}
              </p>
              <p
                class="mt-2 whitespace-pre-wrap break-words"
                data-quality-history-reason
              >
                {{ labels.REASON }}{{ labels.COLON }}
                {{ row.values.justification }}
              </p>
            </div>
          </div>
          <p
            class="mt-2 break-all text-xs text-n-slate-11"
            data-quality-history-source-version
          >
            {{ labels.SOURCE_VERSION }} {{ row.source_sha256 }}
          </p>
        </details>
      </div>
      <footer class="flex flex-wrap items-center gap-2">
        <span class="text-xs text-n-slate-11">{{ footer }}</span>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          :disabled="loading || meta.page <= 1"
          data-quality-history-previous
          @click="load(meta.page - 1)"
        >
          {{ labels.PREVIOUS }}
        </button>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          :disabled="loading || meta.page * meta.per_page >= meta.total"
          data-quality-history-next
          @click="load(meta.page + 1)"
        >
          {{ labels.NEXT }}
        </button>
      </footer>
    </template>
  </section>
</template>
