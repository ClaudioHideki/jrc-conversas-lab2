<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useServiceDesk } from '../composables/useServiceDesk';
import { formatTimestamp } from '../helpers/presentation';
const props = defineProps({
  ticket: { type: Object, required: true },
  compact: Boolean,
});
const { t, te, locale } = useI18n();
const { state } = useServiceDesk();
const unit = computed(() =>
  state.context?.units.find(item => item.id === props.ticket.unit_id)
);
const allDetails = computed(() => ({
  unit: unit.value?.name,
  operator_company: unit.value?.operator_company?.name,
  requester: props.ticket.requester?.name,
  assignee: props.ticket.assignee?.name,
  team: props.ticket.team?.name,
  queue: props.ticket.queue?.name,
  status: props.ticket.status?.name,
  priority: props.ticket.priority?.name,
  category: props.ticket.category?.name,
  subcategory: props.ticket.subcategory?.name,
  ticket_type: props.ticket.ticket_type?.name,
  service: props.ticket.service?.name,
  source: te(`JRC_SERVICE_DESK.REDESIGN_LIST.sources.${props.ticket.source}`)
    ? t(`JRC_SERVICE_DESK.REDESIGN_LIST.sources.${props.ticket.source}`)
    : props.ticket.source,
  opened_at: formatTimestamp(props.ticket.opened_at, locale.value),
  created_at: formatTimestamp(props.ticket.created_at, locale.value),
  updated_at: formatTimestamp(props.ticket.updated_at, locale.value),
  first_response: formatTimestamp(
    props.ticket.sla?.first_response_due_at,
    locale.value
  ),
  resolution: formatTimestamp(
    props.ticket.sla?.resolution_due_at,
    locale.value
  ),
}));
const details = computed(() =>
  props.compact
    ? Object.fromEntries(
        [
          'requester',
          'unit',
          'queue',
          'team',
          'assignee',
          'status',
          'priority',
          'updated_at',
        ].map(key => [key, allDetails.value[key]])
      )
    : allDetails.value
);
</script>

<template>
  <dl class="sd-detail-list">
    <template v-for="(value, field) in details" :key="field">
      <dt>
        {{ t(`JRC_SERVICE_DESK.FIELDS.${field}`) }}
      </dt>
      <dd>
        {{ value || t('JRC_SERVICE_DESK.COMMON.no_value') }}
        <span
          v-if="field === 'requester' && ticket.requester?.phone_number"
          class="block text-xs text-n-slate-11"
        >
          {{ ticket.requester.phone_number }}
        </span>
      </dd>
    </template>
  </dl>
</template>
