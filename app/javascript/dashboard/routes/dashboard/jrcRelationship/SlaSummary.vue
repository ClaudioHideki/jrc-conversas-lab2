<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { date as formatDate } from './definitions';
const props = defineProps({ metadata: { type: Object, default: () => ({}) }, sla: { type: Object, default: null } });
const { t } = useI18n();
const state = computed(() =>
  props.sla?.paused_at ? 'paused' : props.sla?.state || 'within'
);
const configured = computed(
  () => props.sla?.first_action_due_at || props.sla?.total_due_at
);
const date = value => formatDate(value, props.metadata?.formatting);
</script>
<template>
  <div
    v-if="sla"
    class="mt-2 text-xs"
    data-testid="sla-summary"
  >
    <template v-if="configured">
      <p :class="state === 'overdue' ? 'text-n-ruby-11' : 'text-n-slate-11'">
        {{ t('RELATIONSHIP.SLA') }} ·
        {{ t(`RELATIONSHIP.SLA_STATES.${state}`) }}
        <span v-if="sla.percent_elapsed !== null">
          ·
          {{
            t('RELATIONSHIP.SLA_ELAPSED', { percent: sla.percent_elapsed })
          }}</span
        >
      </p>
      <p>
        {{ t('RELATIONSHIP.FIRST_ACTION') }}:
        {{ date(sla.first_action_at || sla.first_action_due_at) }}
      </p>
      <p>{{ t('RELATIONSHIP.RESOLUTION') }}: {{ date(sla.total_due_at) }}</p>
      <p v-if="sla.paused_at">
        {{ t('RELATIONSHIP.SLA_PAUSED_SINCE', { date: date(sla.paused_at) }) }}
      </p>
    </template>
    <p v-else>{{ t('RELATIONSHIP.SLA_NOT_CONFIGURED') }}</p>
  </div>
</template>
