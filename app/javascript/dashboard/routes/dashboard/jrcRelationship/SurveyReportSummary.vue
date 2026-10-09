<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
defineProps({ report: { type: Object, required: true } });
const { t } = useI18n();
const number = value =>
  value === null || value === undefined ? '—' : Math.round(value * 100) / 100;
const percent = value =>
  value === null || value === undefined ? '—' : `${number(value)}%`;
const labels = computed(() => ({
  response_count: t('RELATIONSHIP.SURVEY_METRICS.response_count'),
  nps: t('RELATIONSHIP.SURVEY_METRICS.nps'),
  csat: t('RELATIONSHIP.SURVEY_METRICS.csat'),
  ces: t('RELATIONSHIP.SURVEY_METRICS.ces'),
  eligible_count: t('RELATIONSHIP.SURVEY_METRICS.eligible_count'),
  sent_count: t('RELATIONSHIP.SURVEY_METRICS.sent_count'),
  delivered_count: t('RELATIONSHIP.SURVEY_METRICS.delivered_count'),
  eligible_answered_count: t(
    'RELATIONSHIP.SURVEY_METRICS.eligible_answered_count'
  ),
  available_link_count: t('RELATIONSHIP.SURVEY_METRICS.available_link_count'),
  queued_count: t('RELATIONSHIP.SURVEY_METRICS.queued_count'),
  legacy_count: t('RELATIONSHIP.SURVEY_METRICS.legacy_count'),
  untracked_count: t('RELATIONSHIP.SURVEY_METRICS.untracked_count'),
}));
const kinds = computed(() => ({
  nps: t('RELATIONSHIP.SURVEY_ADMIN.nps'),
  csat: t('RELATIONSHIP.SURVEY_ADMIN.csat'),
  ces: t('RELATIONSHIP.SURVEY_ADMIN.ces'),
  custom: t('RELATIONSHIP.SURVEY_ADMIN.custom'),
}));
</script>

<template>
  <section
    class="space-y-3 rounded-xl border border-n-weak p-4"
    data-testid="survey-report-summary"
  >
    <h3 class="font-semibold">
      {{ t('RELATIONSHIP.SURVEY_FILTERED_METRICS') }}
    </h3>
    <dl class="grid gap-3 sm:grid-cols-4">
      <div
        v-for="key in ['response_count', 'nps', 'csat', 'ces']"
        :key="key"
      >
        <dt class="text-xs text-n-slate-11">
          {{ labels[key] }}
        </dt>
        <dd class="text-xl font-semibold">{{ number(report[key]) }}</dd>
      </div>
    </dl>
    <div
      v-if="report.delivery"
      class="space-y-2 border-t border-n-weak pt-3"
    >
      <p
        v-if="!report.delivery.available"
        role="status"
        class="text-sm"
      >
        {{ t('RELATIONSHIP.SURVEY_COHORT_REQUIRED') }}
      </p>
      <template v-else>
        <p class="flex flex-wrap gap-2 text-xs text-n-slate-11">
          <span>{{ t('RELATIONSHIP.SURVEY_COHORT_PROVENANCE') }}</span>
          <span>{{
            t('RELATIONSHIP.SURVEY_COHORT_PERIOD', {
              from: report.delivery.period?.from || '—',
              to: report.delivery.period?.to || '—',
            })
          }}</span>
        </p>
        <dl class="grid gap-3 sm:grid-cols-4">
          <div
            v-for="key in [
              'eligible_count',
              'sent_count',
              'delivered_count',
              'eligible_answered_count',
              'available_link_count',
              'queued_count',
              'legacy_count',
              'untracked_count',
            ]"
            :key="key"
          >
            <dt class="text-xs text-n-slate-11">
              {{ labels[key] }}
            </dt>
            <dd>{{ number(report.delivery[key]) }}</dd>
          </div>
        </dl>
        <p class="flex flex-wrap gap-2 text-sm">
          <span>{{ t('RELATIONSHIP.SURVEY_METRICS.response_rate') }}</span>
          <span>{{
            t('RELATIONSHIP.SURVEY_COHORT_RATE', {
              rate: percent(report.delivery.response_rate),
              numerator: report.delivery.response_numerator,
              denominator: report.delivery.response_denominator,
            })
          }}</span>
        </p>
        <p class="flex flex-wrap gap-2 text-sm">
          <span>{{ t('RELATIONSHIP.SURVEY_METRICS.delivery_rate') }}</span>
          <span>{{
            t('RELATIONSHIP.SURVEY_COHORT_RATE', {
              rate: percent(report.delivery.delivery_rate),
              numerator: report.delivery.delivery_numerator,
              denominator: report.delivery.delivery_denominator,
            })
          }}</span>
        </p>
      </template>
    </div>
    <details v-if="report.trend?.length">
      <summary class="cursor-pointer text-sm">
        {{ t('RELATIONSHIP.SURVEY_TREND') }}
      </summary>
      <table class="mt-3 w-full text-sm">
        <thead>
          <tr>
            <th>{{ t('RELATIONSHIP.FIELDS.from') }}</th>
            <th>{{ t('RELATIONSHIP.FIELDS.kind') }}</th>
            <th>{{ t('RELATIONSHIP.SURVEY_METRICS.response_count') }}</th>
            <th>{{ t('RELATIONSHIP.SURVEY_METRICS.average_score') }}</th>
            <th>{{ t('RELATIONSHIP.SURVEY_ADMIN.nps') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="point in report.trend"
            :key="`${point.day}:${point.kind}`"
            class="border-t border-n-weak"
          >
            <td class="p-2">{{ point.day }}</td>
            <td class="p-2">
              {{ kinds[point.kind] || point.kind }}
            </td>
            <td class="p-2">{{ point.response_count }}</td>
            <td class="p-2">{{ number(point.average_score) }}</td>
            <td class="p-2">{{ number(point.nps) }}</td>
          </tr>
        </tbody>
      </table>
    </details>
  </section>
</template>
