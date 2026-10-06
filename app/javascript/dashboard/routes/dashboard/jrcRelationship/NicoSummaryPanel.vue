<script setup>
import { useI18n } from 'vue-i18n';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';
import { buttonClass, date as formatDate } from './definitions';
const props = defineProps({
  metrics: { type: Object, default: () => ({}) },
  assignmentId: { type: [Number, String], default: null },
  enabled: Boolean,
  metadata: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['customer']);
const { t } = useI18n();
const { openWithPrompt } = useJrcCopilot();
const request = task => openWithPrompt(t(`RELATIONSHIP.NICO_PROMPTS.${task}`, { id: props.assignmentId }));
const date = value => formatDate(value, props.metadata?.formatting);
</script>

<template>
  <section class="mt-4 rounded-xl border border-n-weak p-4">
    <h3 class="font-semibold">{{ t('RELATIONSHIP.NICO_DAILY') }}</h3>
    <template v-if="!assignmentId">
      <p class="mt-2 text-sm">{{ t('RELATIONSHIP.NICO_PRIORITIES', { today: metrics.actions_today ?? '—', overdue: metrics.overdue_actions ?? '—', risk: metrics.at_risk ?? '—' }) }}</p>
      <ol class="mt-2 space-y-2">
        <li v-for="action in metrics.priority_actions || []" :key="`${action.assignment_id}:${action.reason}`">
          <button type="button" :class="buttonClass" @click="emit('customer', action.assignment_id)">{{ action.customer }} · {{ action.reason }} · {{ date(action.due_at) }}</button>
        </li>
      </ol>
      <button v-if="enabled" type="button" :class="buttonClass" class="mt-3" @click="request('daily')">{{ t('RELATIONSHIP.NICO_REVIEW_DAILY') }}</button>
    </template>
    <div v-else-if="enabled" class="mt-3 flex flex-wrap gap-2">
      <button v-for="task in ['summary', 'risk', 'qbr', 'next_action', 'draft']" :key="task" type="button" :class="buttonClass" @click="request(task)">{{ t(`RELATIONSHIP.NICO_TASKS.${task}`) }}</button>
    </div>
    <p v-if="enabled" class="mt-2 text-xs text-n-slate-11">{{ t('RELATIONSHIP.NICO_REVIEW_PROMPT') }}</p>
    <p v-else class="mt-2 text-xs text-n-slate-11">{{ t('RELATIONSHIP.NICO_DISABLED') }}</p>
  </section>
</template>
