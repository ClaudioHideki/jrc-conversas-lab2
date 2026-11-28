<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  summary: { type: Object, required: true },
  sentiment: { type: String, default: '' },
  observedAt: { type: String, required: true },
});
const emit = defineEmits(['filter']);
const { t } = useI18n();
const text = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.DISTRIBUTION_TITLE'),
  ALL: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.ALL'),
  POSITIVE: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.POSITIVE'),
  NEUTRAL: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.NEUTRAL'),
  NEGATIVE: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.NEGATIVE'),
  UNCLASSIFIED: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.UNCLASSIFIED'),
  WITHOUT_ANALYSIS: t(
    'JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.WITHOUT_ANALYSIS'
  ),
  NO_PERCENT: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.NO_PERCENT'),
  NO_SCORE: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.NO_SCORE'),
  SOURCE_LIMITS: t(
    'JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.SOURCE_LIMITS'
  ),
}));
const distribution = computed(() => {
  const total = props.summary.analyzed;
  if (!total) return 'conic-gradient(#94a3b8 0% 100%)';
  const positive = (100 * props.summary.counts.positivo) / total;
  const neutral = positive + (100 * props.summary.counts.neutro) / total;
  const negative = neutral + (100 * props.summary.counts.negativo) / total;
  return `conic-gradient(#22c55e 0% ${positive}%, #94a3b8 ${positive}% ${neutral}%, #f43f5e ${neutral}% ${negative}%, #f59e0b ${negative}% 100%)`;
});
const cards = computed(() => [
  {
    key: '',
    count: props.summary.universe,
    label: 'ALL',
    style: 'border-n-blue-6 bg-n-blue-2 text-n-blue-12',
  },
  ...[
    ['positivo', 'POSITIVE', 'border-n-teal-6 bg-n-teal-2 text-n-teal-12'],
    ['neutro', 'NEUTRAL', 'border-n-slate-6 bg-n-slate-2 text-n-slate-12'],
    ['negativo', 'NEGATIVE', 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-12'],
  ].map(([key, label, style]) => ({
    key,
    label,
    style,
    count: props.summary.counts[key],
    percent: props.summary.percentages[key],
  })),
  {
    key: 'unclassified',
    label: 'UNCLASSIFIED',
    count: props.summary.unclassified,
    style: 'border-n-amber-6 bg-n-amber-2 text-n-amber-12',
  },
  {
    key: 'without_analysis',
    label: 'WITHOUT_ANALYSIS',
    count: props.summary.without_analysis,
    style: 'border-n-slate-6 bg-n-slate-2 text-n-slate-12',
  },
]);
</script>

<template>
  <section class="min-w-0 space-y-3" data-recording-quality-summary>
    <h2 class="text-lg font-semibold">{{ text.TITLE }}</h2>
    <p class="break-words text-sm text-n-slate-11" data-quality-denominator>
      {{
        t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.DENOMINATOR', {
          analyzed: summary.analyzed,
          universe: summary.universe,
          observed: observedAt,
        })
      }}
    </p>
    <div
      class="grid min-w-0 gap-3 xl:grid-cols-[minmax(0,3fr)_minmax(12rem,1fr)]"
    >
      <div class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <button
          v-for="card in cards"
          :key="card.key"
          type="button"
          class="min-w-0 rounded-xl border p-4 text-left focus-visible:outline focus-visible:outline-2"
          :class="[
            card.style,
            sentiment === card.key ? 'ring-2 ring-n-blue-9' : '',
          ]"
          :aria-pressed="sentiment === card.key"
          :data-quality-filter="card.key || 'all'"
          @click="emit('filter', card.key)"
        >
          <span class="block text-sm">{{ text[card.label] }}</span>
          <span class="mt-1 block text-2xl font-semibold">{{
            card.count
          }}</span>
          <span v-if="card.percent !== undefined" class="text-sm">
            {{ card.percent === null ? text.NO_PERCENT : `${card.percent}%` }}
          </span>
        </button>
      </div>
      <div
        class="flex min-w-0 items-center justify-center rounded-xl border border-n-weak bg-n-solid-1 p-4"
      >
        <div
          role="img"
          class="flex size-40 shrink-0 items-center justify-center rounded-full"
          :style="{ background: distribution }"
          :aria-label="
            t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.DISTRIBUTION', {
              positive: summary.counts.positivo,
              neutral: summary.counts.neutro,
              negative: summary.counts.negativo,
              unknown: summary.unclassified,
            })
          "
          data-quality-distribution
        >
          <div
            aria-hidden="true"
            class="flex size-28 flex-col items-center justify-center rounded-full bg-n-solid-1 text-n-slate-12"
          >
            <strong class="text-2xl">{{ summary.analyzed }}</strong>
            <span class="text-sm">{{
              t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.ANALYZED')
            }}</span>
          </div>
        </div>
      </div>
    </div>
    <p
      class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
      data-quality-score
    >
      {{
        t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY_REPORT.SCORE', {
          average:
            summary.quality_average === null
              ? text.NO_SCORE
              : summary.quality_average,
          count: summary.quality_measured,
        })
      }}
    </p>
    <p class="text-sm text-n-slate-11">{{ text.SOURCE_LIMITS }}</p>
  </section>
</template>
