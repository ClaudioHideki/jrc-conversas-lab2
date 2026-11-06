<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  health: { type: Object, default: () => ({}) },
  formatting: { type: Object, default: () => ({}) },
});
const { t, locale } = useI18n();
const percent = value => {
  if (!Number.isFinite(value) || value < 0 || value > 100)
    return t('RELATIONSHIP.UNAVAILABLE');
  return new Intl.NumberFormat(
    props.formatting.locale || locale?.value || 'pt-BR',
    {
      style: 'percent',
      maximumFractionDigits: 1,
    }
  ).format(value / 100);
};
const policy = computed(
  () =>
    ({
      renormalize: t('RELATIONSHIP.MISSING_POLICIES.renormalize'),
      neutral: t('RELATIONSHIP.MISSING_POLICIES.neutral'),
      block: t('RELATIONSHIP.MISSING_POLICIES.block'),
    })[props.health?.missing_factor_policy]
);
</script>

<template>
  <div
    class="my-2 min-w-0 space-y-1 break-words text-xs text-n-slate-11"
    data-testid="health-coverage-note"
  >
    <p>
      {{
        t('RELATIONSHIP.OBSERVED_HEALTH_COVERAGE.OBSERVED', {
          value: percent(health?.coverage_weight),
        })
      }}
    </p>
    <p>
      {{
        t('RELATIONSHIP.OBSERVED_HEALTH_COVERAGE.CALCULATION', {
          value: percent(health?.calculation_weight),
        })
      }}
    </p>
    <p v-if="policy">
      {{ t('RELATIONSHIP.OBSERVED_HEALTH_COVERAGE.POLICY', { policy }) }}
    </p>
    <p>{{ t('RELATIONSHIP.OBSERVED_HEALTH_COVERAGE.NOTICE') }}</p>
  </div>
</template>
