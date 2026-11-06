<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  summary: { type: Object, required: true },
  formatting: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const percent = computed(() => {
  const value = props.summary.human_confirmation_percent;
  if (!Number.isFinite(value) || !(props.summary.reviewed > 0)) return null;
  return new Intl.NumberFormat(props.formatting.locale || 'pt-BR', {
    style: 'percent',
    maximumFractionDigits: 1,
  }).format(value / 100);
});
</script>

<template>
  <div
    class="space-y-1 text-sm"
    data-testid="human-assessment-rate"
  >
    <p v-if="percent">
      {{
        t('RELATIONSHIP.ALERT_REVIEW.HUMAN_RATIO', {
          percent,
          confirmed: summary.confirmed,
          reviewed: summary.reviewed,
        })
      }}
    </p>
    <p v-else>
      {{ t('RELATIONSHIP.ALERT_REVIEW.HUMAN_RATIO_UNAVAILABLE') }}
    </p>
    <p class="text-xs text-n-slate-11">
      {{ t('RELATIONSHIP.ALERT_REVIEW.HUMAN_RATIO_NOTICE') }}
    </p>
  </div>
</template>
