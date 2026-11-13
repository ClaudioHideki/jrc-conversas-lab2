<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({ state: { type: String, required: true } });
const { t, te } = useI18n();
const color = computed(
  () =>
    ({
      pending:
        'border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-200',
      approved:
        'border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-200',
      rejected:
        'border-rose-200 bg-rose-50 text-rose-800 dark:border-rose-800 dark:bg-rose-950/40 dark:text-rose-200',
      returned:
        'border-orange-200 bg-orange-50 text-orange-800 dark:border-orange-800 dark:bg-orange-950/40 dark:text-orange-200',
    })[props.state] || 'border-n-weak bg-n-alpha-2 text-n-slate-12'
);
const label = computed(() => {
  const key = `JRC_APPROVALS.workspace.states.${props.state}`;
  return te(key) ? t(key) : props.state;
});
</script>

<template>
  <span
    class="inline-flex shrink-0 items-center rounded-lg border px-2.5 py-1 text-xs font-semibold"
    :class="color"
    >{{ label }}</span
  >
</template>
