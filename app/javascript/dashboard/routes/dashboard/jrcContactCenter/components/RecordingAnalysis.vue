<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
});
const { t } = useI18n();
const labels = computed(() => ({
  UNKNOWN: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.UNKNOWN'),
  IMMUTABLE_ORIGINAL: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.IMMUTABLE_ORIGINAL'),
  LOADING: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.LOADING'),
  DENIED: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.DENIED'),
  SOURCE_UNAVAILABLE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SOURCE_UNAVAILABLE'),
  ERROR: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ERROR'),
  RETRY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.RETRY'),
  ORIGINAL_CLASS: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_CLASS'),
  ORIGINAL_QUALITY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_QUALITY'),
  SENTIMENT_CONFIDENCE: t(
    'JRC_CONTACT_CENTER.QUALITY_REVIEW.SENTIMENT_CONFIDENCE'
  ),
  MODEL: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.MODEL'),
  ORIGINAL_SUMMARY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_SUMMARY'),
  ORIGINAL_THEMES: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_THEMES'),
  RECOMMENDATIONS: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.RECOMMENDATIONS'),
  SUGGESTIONS_ONLY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SUGGESTIONS_ONLY'),
  NO_RECOMMENDATIONS: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.NO_RECOMMENDATIONS'),
  HUMAN_ORIGIN: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.HUMAN_ORIGIN'),
  OLDER_SOURCE_REVIEW: t(
    'JRC_CONTACT_CENTER.QUALITY_REVIEW.OLDER_SOURCE_REVIEW'
  ),
  REVISION: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.REVISION'),
}));
const text = key => labels.value[key];
const source = ref(null);
const loading = ref(false);
const error = ref('');
let generation = 0;
const original = computed(() => source.value?.original || {});
const shown = value =>
  value === null || value === undefined || value === ''
    ? text('UNKNOWN')
    : value;
const sameOrigin = data =>
  String(data.account_id) === String(props.accountId) &&
  String(data.recording_id) === String(props.recordingId);

async function load() {
  generation += 1;
  const own = generation;
  source.value = null;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await ContactCenterAPI.qualityReview(
      props.accountId,
      props.recordingId
    );
    if (own !== generation) return;
    if (!sameOrigin(data)) throw new Error('quality_source_identity_mismatch');
    source.value = data;
  } catch (failure) {
    if (own !== generation) return;
    const status = failure.response?.status;
    if ([401, 403, 404].includes(status)) error.value = 'DENIED';
    else if (status === 503) error.value = 'SOURCE_UNAVAILABLE';
    else error.value = 'ERROR';
  } finally {
    if (own === generation) loading.value = false;
  }
}
watch([() => props.accountId, () => props.recordingId], load, {
  flush: 'sync',
});
onMounted(load);
onBeforeUnmount(() => {
  generation += 1;
  source.value = null;
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-lg border border-n-violet-6 bg-n-solid-1 p-4 text-n-slate-12"
    data-recording-original-analysis
  >
    <p class="text-sm text-n-slate-11">{{ text('IMMUTABLE_ORIGINAL') }}</p>
    <p v-if="loading" role="status">{{ text('LOADING') }}</p>
    <div v-else-if="error" class="space-y-3">
      <p role="alert" class="break-words text-n-ruby-11">{{ text(error) }}</p>
      <button
        type="button"
        class="rounded-lg border border-n-violet-6 px-3 py-2 text-n-violet-11"
        data-recording-analysis-retry
        @click="load"
      >
        {{ text('RETRY') }}
      </button>
    </div>
    <template v-else-if="source">
      <dl class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <dt class="text-xs text-n-slate-11">{{ text('ORIGINAL_CLASS') }}</dt>
          <dd data-analysis-original-sentiment>
            {{ shown(original.sentimento_cliente) }}
          </dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ text('ORIGINAL_QUALITY') }}
          </dt>
          <dd data-analysis-original-score>{{ shown(original.nota_final) }}</dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">
            {{ text('SENTIMENT_CONFIDENCE') }}
          </dt>
          <dd>{{ shown(original.sentiment_confidence) }}</dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-11">{{ text('MODEL') }}</dt>
          <dd class="break-all">{{ shown(original.model) }}</dd>
        </div>
      </dl>
      <div>
        <h3 class="font-semibold text-n-violet-11">
          {{ text('ORIGINAL_SUMMARY') }}
        </h3>
        <p
          class="whitespace-pre-wrap break-words"
          data-analysis-original-summary
        >
          {{ shown(original.resumo_conversa) }}
        </p>
      </div>
      <div>
        <h3 class="font-semibold text-n-violet-11">
          {{ text('ORIGINAL_THEMES') }}
        </h3>
        <ul
          v-if="original.themes?.length"
          class="list-inside list-disc break-words"
        >
          <li v-for="(theme, index) in original.themes" :key="index">
            {{ theme }}
          </li>
        </ul>
        <p v-else class="text-n-slate-11">{{ text('UNKNOWN') }}</p>
      </div>
      <div>
        <h3 class="font-semibold text-n-violet-11">
          {{ text('RECOMMENDATIONS') }}
        </h3>
        <p class="text-xs text-n-slate-11">{{ text('SUGGESTIONS_ONLY') }}</p>
        <ul
          v-if="original.recommendations?.length"
          class="list-inside list-disc break-words"
        >
          <li v-for="row in original.recommendations" :key="row.id">
            {{ row.text }}
          </li>
        </ul>
        <p v-else class="text-n-slate-11">{{ text('NO_RECOMMENDATIONS') }}</p>
      </div>
      <div
        v-if="source.latest_review"
        class="space-y-2 rounded-lg border border-n-blue-6 p-3"
        data-analysis-latest-human
      >
        <h3 class="font-semibold text-n-blue-11">{{ text('HUMAN_ORIGIN') }}</h3>
        <p
          v-if="source.latest_review.source_sha256 !== source.source_sha256"
          class="text-xs text-n-amber-11"
          data-analysis-older-human-source
        >
          {{ text('OLDER_SOURCE_REVIEW') }}
        </p>
        <p class="break-words">
          {{ source.latest_review.values.adjusted_summary }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ text('REVISION') }} {{ source.latest_review.revision }}
        </p>
      </div>
    </template>
  </section>
</template>
