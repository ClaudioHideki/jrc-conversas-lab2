<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { money as formatMoney } from './definitions';
const props = defineProps({
  metadata: { type: Object, default: () => ({}) },
  metrics: { type: Object, default: () => ({}) },
  mode: { type: String, default: 'all' },
  inspect: Boolean,
});
const emit = defineEmits(['filter', 'inspect']);
const { t } = useI18n();
const keys = [
  'customers',
  'active',
  'mrr_cents',
  'arr_cents',
  'health_average',
  'at_risk',
  'mrr_at_risk_cents',
  'churned',
  'retained',
  'retention_rate',
  'nps',
  'csat',
  'ces',
  'without_contact',
  'overdue_activities',
  'actions_today',
  'overdue_actions',
  'waiting_customer_actions',
  'waiting_finance_actions',
  'expansion_potential_cents',
  'expansion_won_cents',
  'nrr',
  'gross_retention',
  'revenue_churn',
  'renewal_rate',
  'renewed_mrr_cents',
  'qbr_completed',
  'qbr_scheduled',
  'nps_promoters',
  'nps_detractors',
  'first_action_minutes',
  'open_retention_cases',
];
const money = value => formatMoney(value, props.metadata?.formatting);
const observedMoney = value =>
  value == null ? t('RELATIONSHIP.UNAVAILABLE') : money(value);
const revenueReasonKeys = {
  financial_access_unavailable: 'RELATIONSHIP.MRR_EVOLUTION_FINANCIAL_ACCESS',
  observation_limit: 'RELATIONSHIP.MRR_EVOLUTION_LIMIT',
  no_observations: 'RELATIONSHIP.MRR_EVOLUTION_EMPTY',
  conflicting_customer_observations: 'RELATIONSHIP.MRR_EVIDENCE_CONFLICT',
  amount_unavailable: 'RELATIONSHIP.MRR_EVIDENCE_UNKNOWN',
  amount_source_unavailable: 'RELATIONSHIP.MRR_EVIDENCE_SOURCE_UNAVAILABLE',
  customer_source_changed: 'RELATIONSHIP.MRR_EVIDENCE_CUSTOMER_CHANGED',
  overlapping_customer_sources: 'RELATIONSHIP.MRR_EVIDENCE_OVERLAP',
};
const revenueReason = reason =>
  t(revenueReasonKeys[reason] || 'RELATIONSHIP.UNAVAILABLE');
const display = key => {
  const value = props.metrics[key];
  if (value === null || value === undefined)
    return t('RELATIONSHIP.UNAVAILABLE');
  if (key.endsWith('_cents')) return money(value);
  if (typeof value === 'number') return Number(value.toFixed(1));
  return value;
};
const portfolioKeys = [
  'customers',
  'mrr_cents',
  'health_average',
  'at_risk',
  'nps',
  'csat',
  'without_contact',
  'expansion_potential_cents',
];
const modeKeys = {
  portfolio: portfolioKeys,
  expansion: ['expansion_potential_cents', 'expansion_won_cents'],
  actions: [
    'actions_today',
    'overdue_actions',
    'at_risk',
    'nps_detractors',
    'expansion_potential_cents',
    'waiting_customer_actions',
    'waiting_finance_actions',
  ],
  surveys: ['nps', 'csat', 'ces', 'nps_promoters', 'nps_detractors'],
};
const cards = computed(() =>
  (modeKeys[props.mode] || keys).map(key => ({
    key,
    value: display(key),
  }))
);
const windows = computed(() => {
  if (['surveys', 'expansion'].includes(props.mode)) return [];
  return ['portfolio', 'actions'].includes(props.mode)
    ? [30, 60, 90]
    : [15, 30, 60, 90, 120];
});
const drilldown = [
  'at_risk',
  'mrr_at_risk_cents',
  'active',
  'churned',
  'without_contact',
  'overdue_actions',
  'actions_today',
  'waiting_customer_actions',
  'waiting_finance_actions',
];
</script>

<template>
  <p
    v-if="!['surveys', 'expansion'].includes(mode) && metrics.health_coverage"
    class="mb-3 text-xs text-n-slate-11"
  >
    {{ t('RELATIONSHIP.HEALTH_COVERAGE', metrics.health_coverage) }}
  </p>
  <section class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-6">
    <button
      v-for="card in cards"
      :key="card.key"
      type="button"
      :disabled="
        props.inspect
          ? metrics[card.key] === null || metrics[card.key] === undefined
          : !drilldown.includes(card.key)
      "
      class="rounded-xl border border-n-weak bg-n-solid-2 p-4"
      @click="
        props.inspect ? emit('inspect', card.key) : emit('filter', card.key)
      "
    >
      <p class="text-xs text-n-slate-11">
        {{ t(`RELATIONSHIP.METRICS.${card.key}`) }}
      </p>
      <strong class="mt-2 block text-lg">{{ card.value }}</strong>
    </button>
    <button
      v-for="days in windows"
      :key="days"
      class="rounded-xl border border-n-weak bg-n-solid-2 p-4"
      @click="emit('filter', { renewal_days: days })"
    >
      <p class="text-xs text-n-slate-11">
        {{ t('RELATIONSHIP.RENEWAL_WINDOW', { days }) }}
      </p>
      <strong class="mt-2 block text-lg">{{
        metrics.renewals?.[days] ?? '—'
      }}</strong>
    </button>
  </section>
  <section
    v-if="!['surveys', 'expansion'].includes(mode) && metrics.bands"
    class="mt-4 flex flex-wrap gap-3"
    :aria-label="t('RELATIONSHIP.DISTRIBUTION')"
  >
    <button
      v-for="(count, band) in metrics.bands"
      :key="band"
      type="button"
      class="rounded-xl border border-n-weak p-3 text-sm"
      @click="emit('filter', { band })"
    >
      {{ t(`RELATIONSHIP.BANDS.${band}`) }}: {{ count }}
    </button>
  </section>
  <details
    v-if="
      !['surveys', 'expansion', 'actions'].includes(mode) &&
      metrics.mrr_evolution
    "
    class="mt-4 rounded-xl border border-n-weak p-3"
    data-testid="relationship-mrr-evolution"
  >
    <summary>{{ t('RELATIONSHIP.MRR_EVOLUTION') }}</summary>
    <p class="mt-2 text-xs text-n-slate-11">
      {{ t('RELATIONSHIP.MRR_EVOLUTION_BASIS') }}
    </p>
    <p class="mt-2 text-xs">
      {{ metrics.mrr_evolution.period?.from }} —
      {{ metrics.mrr_evolution.period?.to }} ·
      {{ metrics.mrr_evolution.timezone }}
    </p>
    <p
      v-if="metrics.mrr_evolution.reason"
      class="mt-2 text-xs"
    >
      {{ revenueReason(metrics.mrr_evolution.reason) }}
    </p>
    <div class="mt-3 overflow-x-auto">
      <table
        v-if="metrics.mrr_evolution.points?.length"
        class="w-full text-sm"
      >
        <thead>
          <tr>
            <th class="text-left">{{ t('RELATIONSHIP.MRR_EVOLUTION_DAY') }}</th>
            <th class="text-left">
              {{ t('RELATIONSHIP.MRR_EVOLUTION_OBSERVED') }}
            </th>
            <th class="text-left">
              {{ t('RELATIONSHIP.MRR_EVOLUTION_COMPLETE') }}
            </th>
            <th class="text-left">
              {{ t('RELATIONSHIP.MRR_EVOLUTION_COVERAGE') }}
            </th>
            <th class="text-left">
              {{ t('RELATIONSHIP.MRR_EVOLUTION_EVIDENCE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="point in metrics.mrr_evolution.points"
            :key="point.day"
            data-testid="relationship-mrr-observation"
            class="border-t border-n-weak"
          >
            <td class="p-2">{{ point.day }}</td>
            <td class="p-2">{{ observedMoney(point.observed_mrr_cents) }}</td>
            <td class="p-2">{{ observedMoney(point.mrr_cents) }}</td>
            <td class="p-2">
              {{ t('RELATIONSHIP.MRR_EVOLUTION_COUNTS', point.coverage) }}
            </td>
            <td class="p-2">
              <details>
                <summary>
                  {{ t('RELATIONSHIP.MRR_EVOLUTION_EVIDENCE') }}
                </summary>
                <dl
                  v-for="row in point.evidence"
                  :key="row.customer_key"
                  class="mt-2 text-xs"
                >
                  <dt>
                    {{ row.customer_key }} · {{ observedMoney(row.mrr_cents) }}
                  </dt>
                  <dd>{{ row.observed_at }}</dd>
                  <dd>
                    {{ t('RELATIONSHIP.MRR_EVIDENCE_SNAPSHOTS') }}:
                    {{ row.snapshot_ids.join(', ') }}
                  </dd>
                  <dd>
                    {{ t('RELATIONSHIP.MRR_EVIDENCE_ASSIGNMENTS') }}:
                    {{ row.assignment_ids.join(', ') }}
                  </dd>
                  <dd>
                    {{ t('RELATIONSHIP.MRR_EVIDENCE_CONTRACTS') }}:
                    {{ row.contract_ids.join(', ') }}
                  </dd>
                  <dd v-if="row.reason">{{ revenueReason(row.reason) }}</dd>
                </dl>
              </details>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </details>
  <details
    v-if="
      !['surveys', 'expansion'].includes(mode) && metrics.health_trend?.length
    "
    class="mt-4 rounded-xl border border-n-weak p-3"
  >
    <summary>{{ t('RELATIONSHIP.HEALTH_TREND') }}</summary>
    <table class="mt-3 w-full text-sm">
      <tbody>
        <tr
          v-for="point in metrics.health_trend"
          :key="point.day"
        >
          <td>
            <button
              :disabled="!inspect || point.score == null"
              class="text-n-brand"
              @click="
                emit('inspect', { metric: 'health_average', day: point.day })
              "
            >
              {{ point.day }}
            </button>
          </td>
          <td>
            <meter
              min="0"
              max="100"
              :value="point.score || 0"
              :aria-label="point.day"
              class="w-40"
            />
          </td>
          <td>{{ point.score?.toFixed(1) ?? '—' }}</td>
        </tr>
      </tbody>
    </table>
  </details>
  <details
    v-if="
      !['surveys', 'expansion'].includes(mode) &&
      metrics.negative_factors?.length
    "
    class="mt-4 rounded-xl border border-n-weak p-3"
  >
    <summary>{{ t('RELATIONSHIP.NEGATIVE_FACTORS') }}</summary>
    <button
      v-for="row in metrics.negative_factors"
      :key="row.factor"
      class="mt-2 block text-sm text-n-brand"
      @click="emit('filter', { factor: row.factor, direction: 'negative' })"
    >
      {{ t(`RELATIONSHIP.FACTORS.${row.factor}`) }}: {{ row.average }} ·
      {{ row.customers }}
    </button>
  </details>
  <details
    v-if="mode !== 'expansion' && metrics.nps_evolution?.length"
    class="mt-4 rounded-xl border border-n-weak p-3"
  >
    <summary>{{ t('RELATIONSHIP.NPS_EVOLUTION') }}</summary>
    <button
      v-for="row in metrics.nps_evolution"
      :key="row.day"
      :disabled="!inspect"
      class="mt-2 block text-sm text-n-brand"
      @click="emit('inspect', { metric: 'nps', day: row.day })"
    >
      {{ row.day }}: {{ row.score?.toFixed(1) }}
    </button>
  </details>
  <details
    v-if="mode !== 'expansion' && metrics.csat_evolution?.length"
    class="mt-4 rounded-xl border border-n-weak p-3"
  >
    <summary>{{ t('RELATIONSHIP.CSAT_EVOLUTION') }}</summary>
    <button
      v-for="row in metrics.csat_evolution"
      :key="row.day"
      :disabled="!inspect"
      class="mt-2 block text-sm text-n-brand"
      @click="emit('inspect', { metric: 'csat', day: row.day })"
    >
      {{ row.day }}: {{ row.score?.toFixed(1) }}
    </button>
  </details>
</template>
