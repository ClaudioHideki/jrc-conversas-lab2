<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { date } from './definitions';
const props = defineProps({
  signals: { type: Object, required: true },
  formatting: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const measurement = computed(
  () =>
    props.signals.satisfaction_evidence ||
    props.signals.health?.factors?.find(row => row.factor === 'satisfaction')
      ?.measurement
);
const trend = computed(() => props.signals.health_trend);
</script>

<template>
  <section
    v-if="measurement || trend"
    class="my-3 grid min-w-0 gap-3 sm:grid-cols-2"
  >
    <div
      v-if="measurement"
      class="rounded-xl border border-n-weak bg-n-alpha-2 p-3 text-sm"
    >
      <h3 class="font-semibold">
        {{ t('RELATIONSHIP.HEALTH_EVIDENCE.SATISFACTION') }}
      </h3>
      <p>{{ t(`RELATIONSHIP.HEALTH_EVIDENCE.STATES.${measurement.state}`) }}</p>
      <p
        v-if="measurement.recalculation_required"
        class="font-medium text-n-amber-11"
      >
        {{ t('RELATIONSHIP.HEALTH_EVIDENCE.REFRESH_REQUIRED') }}
      </p>
      <p>
        {{
          t('RELATIONSHIP.HEALTH_EVIDENCE.WINDOW', {
            days: measurement.window_days,
          })
        }}
      </p>
      <p v-if="measurement.observed_at">
        {{
          t('RELATIONSHIP.HEALTH_EVIDENCE.ANSWERED', {
            date: date(measurement.observed_at, formatting),
          })
        }}
      </p>
    </div>
    <div
      v-if="trend"
      class="rounded-xl border border-n-weak bg-n-alpha-2 p-3 text-sm"
    >
      <h3 class="font-semibold">
        {{ t('RELATIONSHIP.HEALTH_EVIDENCE.TREND') }}
      </h3>
      <p>{{ t(`RELATIONSHIP.HEALTH_EVIDENCE.STATES.${trend.state}`) }}</p>
      <p>
        {{
          t('RELATIONSHIP.HEALTH_EVIDENCE.WINDOW', { days: trend.window_days })
        }}
      </p>
      <p v-if="trend.delta !== undefined">
        {{ t('RELATIONSHIP.HEALTH_EVIDENCE.CHANGE', { delta: trend.delta }) }}
      </p>
      <p v-if="trend.baseline_at">
        {{
          t('RELATIONSHIP.HEALTH_EVIDENCE.BASELINE', {
            date: date(trend.baseline_at, formatting),
          })
        }}
      </p>
    </div>
  </section>
</template>
