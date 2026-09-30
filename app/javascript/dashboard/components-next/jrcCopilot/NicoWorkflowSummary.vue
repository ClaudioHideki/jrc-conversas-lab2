<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ workflow: { type: Object, default: null } });
const { t } = useI18n();
const tone = status => {
  if (status === 'succeeded') return 'bg-n-teal-3 text-n-teal-11';
  if (['failed', 'unknown'].includes(status))
    return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-amber-3 text-n-amber-11';
};
</script>

<template>
  <section
    v-if="workflow"
    class="mt-2 rounded-lg border border-n-weak p-2 text-xs text-n-slate-12"
    aria-live="polite"
    data-testid="nico-workflow-summary"
  >
    <p class="font-semibold">{{ t(`JRC_NICO.WORKFLOW.${workflow.state}`) }}</p>
    <p class="mt-1 text-n-slate-11">
      {{ t('JRC_NICO.WORKFLOW.COUNT', { count: workflow.completed_count }) }}
    </p>
    <details
      v-if="workflow.steps?.length"
      :open="['partial', 'failed'].includes(workflow.state)"
    >
      <summary
        class="mt-2 cursor-pointer rounded font-medium focus-visible:ring-2 focus-visible:ring-n-blue-7"
      >
        {{ t('JRC_NICO.WORKFLOW.TITLE') }}
      </summary>
      <ol class="mt-2 space-y-2">
        <li v-for="step in workflow.steps" :key="step.id" class="space-y-1">
          <span
            class="inline-block rounded px-2 py-0.5 font-medium"
            :class="tone(step.status)"
          >
            {{ t(`JRC_NICO.WORKFLOW.STATUS.${step.status}`) }}
          </span>
          <p class="whitespace-pre-wrap break-words">{{ step.reply }}</p>
        </li>
      </ol>
    </details>
  </section>
</template>
