<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { capturedPriorityBand } from './priorityBands';
const props = defineProps({ record: { type: Object, required: true } });
const { t } = useI18n();
const band = computed(() => capturedPriorityBand(props.record));
const colors = {
  P0: 'border-rose-300 bg-rose-50 text-rose-900 dark:border-rose-800 dark:bg-rose-950 dark:text-rose-200',
  P1: 'border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-200',
  P2: 'border-blue-300 bg-blue-50 text-blue-900 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-200',
  P3: 'border-slate-300 bg-slate-50 text-slate-900 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-200',
};
</script>

<template>
  <span
    v-if="band"
    data-testid="priority-band"
    class="inline-flex rounded-lg border px-2 py-1 text-xs font-semibold"
    :class="colors[band]"
    :title="t('RELATIONSHIP.PRIORITY_BANDS.CAPTURED')"
  >
    {{ band }} · {{ t(`RELATIONSHIP.PRIORITY_BANDS.${band}`) }}
  </span>
</template>
