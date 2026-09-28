<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useServiceDesk } from '../composables/useServiceDesk';
import { formatTimestamp } from '../helpers/presentation';
const props = defineProps({ ticket: { type: Object, required: true } });
const { t, locale } = useI18n();
const { state } = useServiceDesk();
const unit = computed(() => state.context?.units.find(item => item.id === props.ticket.unit_id));
const details = computed(() => ({
  unit: unit.value?.name, operator_company: unit.value?.operator_company?.name,
  requester: props.ticket.requester?.name, assignee: props.ticket.assignee?.name,
  team: props.ticket.team?.name, queue: props.ticket.queue?.name,
  status: props.ticket.status?.name, priority: props.ticket.priority?.name,
  category: props.ticket.category?.name, source: props.ticket.source,
  created_at: formatTimestamp(props.ticket.created_at, locale.value),
  updated_at: formatTimestamp(props.ticket.updated_at, locale.value),
}));
</script>
<template>
  <dl class="sd-detail-list">
    <template v-for="(value, field) in details" :key="field">
      <dt>
        {{ t(`JRC_SERVICE_DESK.FIELDS.${field}`) }}
      </dt>
      <dd>
        {{ value || t('JRC_SERVICE_DESK.COMMON.no_value') }}
      </dd>
    </template>
  </dl>
</template>
