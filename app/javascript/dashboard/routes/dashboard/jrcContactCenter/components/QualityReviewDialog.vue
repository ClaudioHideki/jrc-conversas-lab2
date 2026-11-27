<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recording: { type: Object, required: true },
  formattedDuration: { type: String, default: '' },
});
const emit = defineEmits(['close', 'saved']);
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.TITLE'),
  NUMBER: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.NUMBER'),
  EXTENSION: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.EXTENSION'),
  STARTED: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.STARTED'),
  DURATION: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.DURATION'),
  INTRO: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.INTRO'),
  LOADING: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.LOADING'),
  UNKNOWN: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.UNKNOWN'),
  CALL: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.CALL'),
  REVISION: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.REVISION'),
  HUMAN_ORIGIN: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.HUMAN_ORIGIN'),
  LATEST_HUMAN_REVIEW: t(
    'JRC_CONTACT_CENTER.QUALITY_REVIEW.LATEST_HUMAN_REVIEW'
  ),
  OLDER_SOURCE_REVIEW: t(
    'JRC_CONTACT_CENTER.QUALITY_REVIEW.OLDER_SOURCE_REVIEW'
  ),
  SENTIMENT: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SENTIMENT'),
  ORIGINAL_CLASS: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_CLASS'),
  ORIGINAL_QUALITY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_QUALITY'),
  SCORE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SCORE'),
  SENTIMENT_CONFIDENCE: t(
    'JRC_CONTACT_CENTER.QUALITY_REVIEW.SENTIMENT_CONFIDENCE'
  ),
  ASR_CONFIDENCE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ASR_CONFIDENCE'),
  MODEL: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.MODEL'),
  NEW_CLASS: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.NEW_CLASS'),
  POSITIVE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.POSITIVE'),
  NEUTRAL: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.NEUTRAL'),
  NEGATIVE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.NEGATIVE'),
  ORIGINAL_SUMMARY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_SUMMARY'),
  ADJUSTED_SUMMARY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ADJUSTED_SUMMARY'),
  ORIGINAL_THEMES: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ORIGINAL_THEMES'),
  ADJUSTED_THEMES: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ADJUSTED_THEMES'),
  ONE_THEME_PER_LINE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ONE_THEME_PER_LINE'),
  RECOMMENDATIONS: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.RECOMMENDATIONS'),
  SUGGESTIONS_ONLY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SUGGESTIONS_ONLY'),
  NO_RECOMMENDATIONS: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.NO_RECOMMENDATIONS'),
  JUSTIFICATION: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.JUSTIFICATION'),
  IMMUTABLE_ORIGINAL: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.IMMUTABLE_ORIGINAL'),
  REVIEW_REQUIRED: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.REVIEW_REQUIRED'),
  SUGGESTIONS_CHANGED: t(
    'JRC_CONTACT_CENTER.QUALITY_REVIEW.SUGGESTIONS_CHANGED'
  ),
  REMOVE_UNAVAILABLE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.REMOVE_UNAVAILABLE'),
  REFRESH_REVIEW: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.REFRESH_REVIEW'),
  ACCEPT_REVIEW: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ACCEPT_REVIEW'),
  DISCARD_QUESTION: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.DISCARD_QUESTION'),
  KEEP_EDITING: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.KEEP_EDITING'),
  DISCARD: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.DISCARD'),
  RETRY: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.RETRY'),
  CANCEL: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.CANCEL'),
  SAVING: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SAVING'),
  SAVE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SAVE'),
  DENIED: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.DENIED'),
  CONFLICT: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.CONFLICT'),
  SOURCE_UNAVAILABLE: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SOURCE_UNAVAILABLE'),
  PERSISTENCE_ERROR: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.PERSISTENCE_ERROR'),
  REASON_REQUIRED: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.REASON_REQUIRED'),
  CLASS_REQUIRED: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.CLASS_REQUIRED'),
  ERROR: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.ERROR'),
  SEPARATOR: t('JRC_CONTACT_CENTER.QUALITY_REVIEW.SEPARATOR'),
}));
const text = key => labels.value[key];
const dialog = ref(null);
const source = ref(null);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const stale = ref(false);
const reviewedSource = ref(false);
const confirmDiscard = ref(false);
const draft = reactive({
  classification: '',
  adjusted_summary: '',
  themes: '',
  recommendation_ids: [],
  justification: '',
});
const initialDraft = ref(JSON.stringify(draft));
let generation = 0;
let submitted = null;
const original = computed(() => source.value?.original || {});
const startedAt = computed(() => {
  const value = Date.parse(props.recording.started_at);
  if (!Number.isFinite(value) || !source.value?.timezone)
    return text('UNKNOWN');
  try {
    return new Intl.DateTimeFormat('pt-BR', {
      timeZone: source.value.timezone,
      dateStyle: 'short',
      timeStyle: 'short',
    }).format(new Date(value));
  } catch {
    return text('UNKNOWN');
  }
});
const canReview = computed(() => source.value?.can_review === true);
const recommendations = computed(() => original.value.recommendations || []);
const unavailableSelections = computed(() =>
  draft.recommendation_ids.filter(
    id => !recommendations.value.some(row => row.id === id)
  )
);
const classifications = ['positive', 'neutral', 'negative'];
const sentimentStyles = {
  positive: { icon: 'i-lucide-smile', color: 'border-n-teal-6 text-n-teal-11' },
  neutral: { icon: 'i-lucide-meh', color: 'border-n-amber-6 text-n-amber-11' },
  negative: { icon: 'i-lucide-frown', color: 'border-n-ruby-6 text-n-ruby-11' },
};
const dirty = computed(() => JSON.stringify(draft) !== initialDraft.value);
const requiredMessage = computed(() => {
  if (!classifications.includes(draft.classification)) return 'CLASS_REQUIRED';
  return draft.justification.trim() ? '' : 'REASON_REQUIRED';
});
const valid = computed(
  () =>
    canReview.value &&
    classifications.includes(draft.classification) &&
    draft.justification.trim() &&
    !stale.value &&
    unavailableSelections.value.length === 0
);
const sameOrigin = data =>
  String(data.account_id) === String(props.accountId) &&
  String(data.recording_id) === String(props.recording.id);
const display = value =>
  value === null || value === undefined || value === ''
    ? text('UNKNOWN')
    : value;

function errorKey(failure) {
  const status = failure.response?.status;
  if ([401, 403, 404].includes(status)) return 'DENIED';
  if (status === 409) return 'CONFLICT';
  const code = failure.response?.data?.error;
  if (code === 'quality_review_persistence_failed') return 'PERSISTENCE_ERROR';
  if (status === 503) return 'SOURCE_UNAVAILABLE';
  if (code === 'quality_analysis_source_unavailable')
    return 'SOURCE_UNAVAILABLE';
  if (code === 'quality_review_justification_required')
    return 'REASON_REQUIRED';
  if (code === 'quality_review_classification_required')
    return 'CLASS_REQUIRED';
  return 'ERROR';
}

async function load(preserveDraft = false) {
  generation += 1;
  const own = generation;
  loading.value = true;
  error.value = '';
  reviewedSource.value = false;
  if (!preserveDraft) source.value = null;
  try {
    const { data } = await ContactCenterAPI.qualityReview(
      props.accountId,
      props.recording.id
    );
    if (own !== generation) return;
    if (!sameOrigin(data)) throw new Error('quality_source_identity_mismatch');
    source.value = data;
    if (preserveDraft) {
      reviewedSource.value = true;
    } else {
      const latest =
        data.latest_review?.source_sha256 === data.source_sha256
          ? data.latest_review.values
          : null;
      Object.assign(draft, {
        classification: latest?.classification || '',
        adjusted_summary:
          latest?.adjusted_summary ?? data.original.resumo_conversa ?? '',
        themes: (latest?.adjusted_themes || data.original.themes || []).join(
          '\n'
        ),
        recommendation_ids: [
          ...(latest?.recommendation_ids ||
            data.original.recommendations.map(row => row.id)),
        ],
        justification: '',
      });
      initialDraft.value = JSON.stringify(draft);
      stale.value = false;
      submitted = null;
    }
  } catch (failure) {
    if (own !== generation) return;
    error.value = errorKey(failure);
    if (error.value === 'DENIED') source.value = null;
  } finally {
    if (own === generation) loading.value = false;
  }
}

function acceptReview() {
  if (!reviewedSource.value) return;
  stale.value = false;
  reviewedSource.value = false;
  submitted = null;
  error.value = '';
}

async function save() {
  if (!valid.value || loading.value || saving.value) return;
  const own = generation;
  const values = {
    classification: draft.classification,
    adjusted_summary: draft.adjusted_summary,
    adjusted_themes: draft.themes
      .split('\n')
      .map(value => value.trim())
      .filter(Boolean),
    recommendation_ids: [...draft.recommendation_ids],
    justification: draft.justification,
    expected_revision: source.value.revision,
    expected_source_sha256: source.value.source_sha256,
  };
  const signature = JSON.stringify(values);
  if (submitted?.signature !== signature)
    submitted = { signature, request_id: crypto.randomUUID() };
  saving.value = true;
  error.value = '';
  try {
    const { data } = await ContactCenterAPI.saveQualityReview(
      props.accountId,
      props.recording.id,
      { ...values, request_id: submitted.request_id }
    );
    if (own !== generation) return;
    if (!sameOrigin(data)) throw new Error('quality_saved_identity_mismatch');
    emit('saved', data.item);
    dialog.value.close();
  } catch (failure) {
    if (own !== generation) return;
    error.value = errorKey(failure);
    stale.value = failure.response?.status === 409;
    if (error.value === 'DENIED') source.value = null;
  } finally {
    if (own === generation) saving.value = false;
  }
}

function cancel() {
  if (saving.value) return;
  if (dirty.value && !confirmDiscard.value) confirmDiscard.value = true;
  else dialog.value.close();
}
watch(
  () => [props.accountId, props.recording.id],
  () => {
    generation += 1;
    saving.value = false;
    submitted = null;
    confirmDiscard.value = false;
    Object.assign(draft, {
      classification: '',
      adjusted_summary: '',
      themes: '',
      recommendation_ids: [],
      justification: '',
    });
    load();
  }
);
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(() => {
  generation += 1;
  source.value = null;
  submitted = null;
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="text('TITLE')"
    :description="text('INTRO')"
    width="5xl"
    contained
    :dismissible="false"
    :use-form="false"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :close-on-click-outside="false"
    @close="emit('close')"
  >
    <div
      class="min-h-0 min-w-0 space-y-4 overflow-y-auto text-sm text-n-slate-12"
      data-quality-review
    >
      <p v-if="loading" role="status">{{ text('LOADING') }}</p>
      <p
        v-if="error"
        role="alert"
        class="rounded-lg border border-n-ruby-6 p-3 text-n-ruby-11"
      >
        {{ text(error) }}
      </p>
      <div v-if="source" class="min-w-0 space-y-4">
        <div
          class="flex flex-wrap justify-between gap-3 rounded-xl border border-n-violet-6 bg-n-violet-3 p-3"
        >
          <span class="min-w-0 break-all">
            {{ text('CALL') }} {{ recording.unique_id }}
          </span>
          <span class="min-w-0 break-words">
            {{ recording.unit_name }} {{ text('SEPARATOR') }}
            {{ recording.queue_name }}
          </span>
          <span>{{ text('REVISION') }} {{ source.revision }}</span>
        </div>
        <dl
          class="grid min-w-0 grid-cols-2 gap-3 rounded-xl border border-n-violet-6 p-3 lg:grid-cols-4"
        >
          <div class="min-w-0">
            <dt>{{ text('NUMBER') }}</dt>
            <dd class="break-words">
              {{ display(recording.external_number) }}
            </dd>
          </div>
          <div class="min-w-0">
            <dt>{{ text('EXTENSION') }}</dt>
            <dd class="break-words">{{ display(recording.extension) }}</dd>
          </div>
          <div class="min-w-0">
            <dt>{{ text('STARTED') }}</dt>
            <dd>{{ startedAt }}</dd>
          </div>
          <div class="min-w-0">
            <dt>{{ text('DURATION') }}</dt>
            <dd>{{ formattedDuration || text('UNKNOWN') }}</dd>
          </div>
        </dl>
        <p
          v-if="source.latest_review"
          class="rounded-lg border border-n-blue-6 p-3"
          data-quality-human-origin
        >
          {{ text('HUMAN_ORIGIN') }} {{ source.latest_review.revision }}
          {{ text('SEPARATOR') }} {{ source.latest_review.actor_id }}
          {{ text('SEPARATOR') }} {{ source.latest_review.created_at }}
        </p>
        <section
          v-if="source.latest_review"
          class="space-y-2 rounded-xl border border-n-blue-6 p-4"
          data-quality-current-human-review
        >
          <h4 class="font-semibold text-n-blue-11">
            {{ text('LATEST_HUMAN_REVIEW') }}
          </h4>
          <p>
            {{ text(source.latest_review.values.classification.toUpperCase()) }}
          </p>
          <p class="whitespace-pre-wrap break-words">
            {{ source.latest_review.values.adjusted_summary }}
          </p>
          <p class="break-words">
            {{ source.latest_review.values.adjusted_themes.join(', ') }}
          </p>
          <p class="whitespace-pre-wrap break-words">
            {{ source.latest_review.values.justification }}
          </p>
          <p
            v-if="source.latest_review.source_sha256 !== source.source_sha256"
            class="text-n-amber-11"
          >
            {{ text('OLDER_SOURCE_REVIEW') }}
          </p>
        </section>
        <div class="grid min-w-0 grid-cols-1 gap-4 lg:grid-cols-3">
          <div class="min-w-0 space-y-4 lg:col-span-2">
            <section class="space-y-3 rounded-xl border border-n-violet-6 p-4">
              <h4 class="font-semibold text-n-violet-11">
                {{ text('SENTIMENT') }}
              </h4>
              <dl class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <div>
                  <dt>{{ text('ORIGINAL_CLASS') }}</dt>
                  <dd data-quality-original-sentiment>
                    {{ display(original.sentimento_cliente) }}
                  </dd>
                </div>
                <div>
                  <dt>{{ text('ORIGINAL_QUALITY') }}</dt>
                  <dd>{{ display(original.classificacao_ligacao) }}</dd>
                </div>
                <div>
                  <dt>{{ text('SCORE') }}</dt>
                  <dd data-quality-original-score>
                    {{ display(original.nota_final) }}
                  </dd>
                </div>
                <div>
                  <dt>{{ text('SENTIMENT_CONFIDENCE') }}</dt>
                  <dd data-quality-sentiment-confidence>
                    {{ display(original.sentiment_confidence) }}
                  </dd>
                </div>
                <div>
                  <dt>{{ text('ASR_CONFIDENCE') }}</dt>
                  <dd>{{ display(original.confianca_transcricao) }}</dd>
                </div>
                <div>
                  <dt>{{ text('MODEL') }}</dt>
                  <dd data-quality-original-model>
                    {{ display(original.model) }}
                  </dd>
                </div>
              </dl>
              <fieldset
                v-if="canReview"
                :disabled="saving || loading"
                class="flex flex-wrap gap-3"
                data-quality-classification
              >
                <legend class="mb-2 font-medium">
                  {{ text('NEW_CLASS') }}
                </legend>
                <label
                  v-for="value in classifications"
                  :key="value"
                  class="flex items-center gap-2 rounded-lg border p-3"
                  :class="sentimentStyles[value].color"
                >
                  <input
                    v-model="draft.classification"
                    type="radio"
                    name="quality-classification"
                    :value="value"
                  /><Icon
                    :icon="sentimentStyles[value].icon"
                    class="size-5"
                    aria-hidden="true"
                  />{{ text(value.toUpperCase()) }}
                </label>
              </fieldset>
            </section>
            <section
              class="grid min-w-0 grid-cols-1 gap-3 rounded-xl border border-n-violet-6 p-4 sm:grid-cols-2"
            >
              <div class="min-w-0">
                <h4 class="mb-2 font-semibold">
                  {{ text('ORIGINAL_SUMMARY') }}
                </h4>
                <p
                  class="whitespace-pre-wrap break-words"
                  data-quality-original-summary
                >
                  {{ display(original.resumo_conversa) }}
                </p>
              </div>
              <label v-if="canReview" class="flex min-w-0 flex-col gap-2">
                {{ text('ADJUSTED_SUMMARY') }}
                <textarea
                  v-model="draft.adjusted_summary"
                  :disabled="saving || loading"
                  rows="6"
                  class="w-full min-w-0 rounded-lg border border-n-violet-6 bg-n-alpha-2 p-3"
                  data-quality-summary
                />
              </label>
            </section>
            <section
              class="grid min-w-0 grid-cols-1 gap-3 rounded-xl border border-n-violet-6 p-4 sm:grid-cols-2"
            >
              <div class="min-w-0">
                <h4 class="mb-2 font-semibold">
                  {{ text('ORIGINAL_THEMES') }}
                </h4>
                <p class="break-words">
                  {{ (original.themes || []).join(', ') || text('UNKNOWN') }}
                </p>
              </div>
              <label v-if="canReview" class="flex min-w-0 flex-col gap-2">
                {{ text('ADJUSTED_THEMES') }}
                <textarea
                  v-model="draft.themes"
                  :disabled="saving || loading"
                  rows="3"
                  class="w-full min-w-0 rounded-lg border border-n-violet-6 bg-n-alpha-2 p-3"
                  data-quality-themes
                />
                <span class="text-xs text-n-slate-11">{{
                  text('ONE_THEME_PER_LINE')
                }}</span>
              </label>
            </section>
          </div>
          <div class="min-w-0 space-y-4">
            <fieldset
              :disabled="!canReview || saving || loading"
              class="min-w-0 space-y-3 rounded-xl border border-n-violet-6 p-4"
            >
              <legend class="font-semibold text-n-violet-11">
                {{ text('RECOMMENDATIONS') }}
              </legend>
              <p class="text-xs text-n-slate-11">
                {{ text('SUGGESTIONS_ONLY') }}
              </p>
              <label
                v-for="row in recommendations"
                :key="row.id"
                class="flex items-start gap-2 break-words"
              >
                <input
                  v-model="draft.recommendation_ids"
                  type="checkbox"
                  :value="row.id"
                /><span class="min-w-0 break-words">{{ row.text }}</span>
              </label>
              <p v-if="!recommendations.length">
                {{ text('NO_RECOMMENDATIONS') }}
              </p>
            </fieldset>
            <label
              v-if="canReview"
              class="flex min-w-0 flex-col gap-2 rounded-xl border border-n-violet-6 p-4"
              >{{ text('JUSTIFICATION') }}
              <textarea
                v-model="draft.justification"
                :disabled="saving || loading"
                rows="5"
                required
                class="w-full min-w-0 rounded-lg border border-n-violet-6 bg-n-alpha-2 p-3"
                data-quality-justification
              />
            </label>
          </div>
          <p
            v-if="canReview && requiredMessage"
            class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-n-amber-11"
            role="status"
            data-quality-required
          >
            {{ text(requiredMessage) }}
          </p>
        </div>
        <p
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 p-3 text-n-blue-11"
        >
          {{ text('IMMUTABLE_ORIGINAL') }}
        </p>
      </div>
      <div
        v-if="source && unavailableSelections.length"
        class="space-y-2 rounded-lg border border-n-amber-6 p-3"
        data-quality-unavailable-suggestions
      >
        <p>{{ text('SUGGESTIONS_CHANGED') }}</p>
        <button
          type="button"
          :disabled="saving || loading"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="
            draft.recommendation_ids = draft.recommendation_ids.filter(
              id => !unavailableSelections.includes(id)
            )
          "
        >
          {{ text('REMOVE_UNAVAILABLE') }}
        </button>
      </div>
      <div
        v-if="stale"
        class="space-y-2 rounded-lg border border-n-amber-6 p-3"
        data-quality-conflict-review
      >
        <p>{{ text('REVIEW_REQUIRED') }}</p>
        <button
          type="button"
          :disabled="loading"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="load(true)"
        >
          {{ text('REFRESH_REVIEW') }}
        </button>
        <button
          v-if="reviewedSource"
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="acceptReview"
        >
          {{ text('ACCEPT_REVIEW') }}
        </button>
      </div>
      <div
        v-if="confirmDiscard"
        class="space-y-2 rounded-lg border border-n-amber-6 p-3"
        data-quality-discard
      >
        <p>{{ text('DISCARD_QUESTION') }}</p>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="confirmDiscard = false"
        >
          {{ text('KEEP_EDITING') }}
        </button>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="dialog.close()"
        >
          {{ text('DISCARD') }}
        </button>
      </div>
      <div class="flex flex-wrap justify-end gap-3">
        <button
          v-if="!source && !loading"
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="load()"
        >
          {{ text('RETRY') }}
        </button>
        <button
          type="button"
          :disabled="saving"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="cancel"
        >
          {{ text('CANCEL') }}
        </button>
        <button
          v-if="canReview"
          type="button"
          :disabled="!valid || loading || saving"
          class="rounded-lg border border-n-violet-6 bg-n-violet-3 px-4 py-2 text-n-violet-11 disabled:opacity-50"
          data-quality-save
          @click="save"
        >
          {{ text(saving ? 'SAVING' : 'SAVE') }}
        </button>
      </div>
    </div>
  </Dialog>
</template>
