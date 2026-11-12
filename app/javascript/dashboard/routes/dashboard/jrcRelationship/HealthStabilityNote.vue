<script setup>
import { useI18n } from 'vue-i18n';
defineProps({ health: { type: Object, default: () => ({}) } });
const { t } = useI18n();
</script>

<template>
  <p
    v-if="health.hysteresis?.retained"
    class="text-xs text-n-slate-11"
    data-testid="health-stability-note"
  >
    {{
      t('RELATIONSHIP.HEALTH_STABILITY', {
        points: health.hysteresis.points,
        band: t(`RELATIONSHIP.BANDS.${health.raw_band}`),
      })
    }}
  </p>
</template>
