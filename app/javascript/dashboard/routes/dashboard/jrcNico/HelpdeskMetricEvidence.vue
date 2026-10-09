<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { helpdeskMetricValue, helpdeskValue } from './helpdeskPresentation';
const props = defineProps({ metric: { type: Object, required: true } });
const { t } = useI18n();
const evidence = computed(() => props.metric.evidence || {});
const value = item => helpdeskValue(item, t('JRC_NICO_HELPDESK.NO_DATA'));
const coverageLabels = computed(() => ({
  observed: t('JRC_NICO_HELPDESK.COVERAGE.observed'),
  covered_human: t('JRC_NICO_HELPDESK.COVERAGE.covered_human'),
  human_approved_nico: t('JRC_NICO_HELPDESK.COVERAGE.human_approved_nico'),
  unknown: t('JRC_NICO_HELPDESK.COVERAGE.unknown'),
  autonomous_supported: t('JRC_NICO_HELPDESK.COVERAGE.autonomous_supported'),
  pending: t('JRC_NICO_HELPDESK.STATES.pending'),
  dispatching: t('JRC_NICO_HELPDESK.RECEIPT_STATES.dispatching'),
  sent: t('JRC_NICO_HELPDESK.RECEIPT_STATES.sent'),
  delivered: t('JRC_NICO_HELPDESK.RECEIPT_STATES.delivered'),
  failed: t('JRC_NICO_HELPDESK.STATES.failed'),
  blocked: t('JRC_NICO_HELPDESK.STATES.blocked'),
  missing_delivery: t('JRC_NICO_HELPDESK.COVERAGE.missing_delivery'),
}));
const observationLabels = computed(() => ({
  resolution_sla_overrun_72h: t(
    'JRC_NICO_HELPDESK.OBSERVATIONS.resolution_sla_overrun_72h'
  ),
  age_at_close_72h: t('JRC_NICO_HELPDESK.OBSERVATIONS.age_at_close_72h'),
}));
</script>

<template>
  <div class="mt-3 space-y-3 text-xs" data-testid="helpdesk-metric-evidence">
    <p
      v-if="evidence.source_conflict?.resolved === false"
      class="rounded bg-n-amber-2 p-2"
    >
      {{ evidence.source_conflict.code }}
      {{ t('JRC_NICO_HELPDESK.UNRESOLVED_SOURCE') }}
    </p>
    <dl v-if="evidence.coverage" class="grid gap-2 sm:grid-cols-2">
      <div v-for="(count, key) in evidence.coverage" :key="key">
        <dt class="text-n-slate-11">{{ coverageLabels[key] || key }}</dt>
        <dd>{{ value(count) }}</dd>
      </div>
    </dl>
    <article
      v-for="observation in evidence.observations || []"
      :key="observation.key"
      class="rounded border border-n-weak p-2"
      :data-observation="observation.key"
    >
      <h3 class="font-medium">
        {{ observationLabels[observation.key] || observation.key }}
      </h3>
      <p>
        {{ t('JRC_NICO_HELPDESK.TIME_BASIS') }} {{ value(observation.basis) }}
      </p>
      <p>
        {{ t('JRC_NICO_HELPDESK.NUMERATOR') }}
        {{ value(observation.numerator) }} /
        {{ t('JRC_NICO_HELPDESK.DENOMINATOR') }}
        {{ value(observation.denominator) }}
      </p>
      <p>
        {{ t('JRC_NICO_HELPDESK.RESULT') }}
        {{
          helpdeskMetricValue(
            {
              ...observation,
              state: observation.value == null ? 'sem_dados' : 'available',
              unit: 'percent',
            },
            t('JRC_NICO_HELPDESK.NO_DATA')
          )
        }}
      </p>
      <p>
        {{ t('JRC_NICO_HELPDESK.COVERAGE.unknown') }}
        {{ value(observation.unknown) }}
      </p>
    </article>
    <dl v-if="evidence.elapsed_seconds" class="grid gap-2 sm:grid-cols-2">
      <div>
        <dt>{{ t('JRC_NICO_HELPDESK.ELAPSED_SECONDS') }}</dt>
        <dd>
          {{
            evidence.elapsed_seconds.map(value).join(', ') ||
            t('JRC_NICO_HELPDESK.NO_DATA')
          }}
        </dd>
      </div>
      <div>
        <dt>{{ t('JRC_NICO_HELPDESK.ELAPSED_MINUTES') }}</dt>
        <dd>
          {{
            (evidence.elapsed_minutes || []).map(value).join(', ') ||
            t('JRC_NICO_HELPDESK.NO_DATA')
          }}
        </dd>
      </div>
      <div>
        <dt>{{ t('JRC_NICO_HELPDESK.MEDIAN_SECONDS') }}</dt>
        <dd>{{ value(evidence.median_seconds) }}</dd>
      </div>
      <div>
        <dt>{{ t('JRC_NICO_HELPDESK.P95_SECONDS') }}</dt>
        <dd>{{ value(evidence.p95_seconds) }}</dd>
      </div>
    </dl>
  </div>
</template>
