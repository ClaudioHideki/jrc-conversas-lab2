<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTimestamp } from '../helpers/presentation';

const props = defineProps({ ticket: { type: Object, required: true } });
const { t, locale } = useI18n();
const fields = computed(() => [
  {
    label: t('JRC_SERVICE_DESK.FIELDS.status'),
    value: props.ticket.status?.name,
  },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.priority'),
    value: props.ticket.priority?.name,
  },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.queue'),
    value: props.ticket.queue?.name,
  },
  { label: t('JRC_SERVICE_DESK.FIELDS.team'), value: props.ticket.team?.name },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.assignee'),
    value: props.ticket.assignee?.name,
  },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.first_response'),
    value: formatTimestamp(
      props.ticket.sla?.first_response_due_at,
      locale.value
    ),
  },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.resolution'),
    value: formatTimestamp(props.ticket.sla?.resolution_due_at, locale.value),
  },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.attendance'),
    value: formatTimestamp(props.ticket.sla?.attendance_due_at, locale.value),
  },
]);
const slaStates = computed(() => ({
  unavailable: t('JRC_SERVICE_DESK.OPS.SLA.unavailable'),
  pending: t('JRC_SERVICE_DESK.OPS.SLA.pending'),
  calculated: t('JRC_SERVICE_DESK.OPS.SLA.calculated'),
  paused: t('JRC_SERVICE_DESK.V2.availability.paused'),
}));
</script>

<template>
  <header
    class="sticky top-0 z-10 grid gap-2 rounded-lg border border-n-weak bg-n-solid-1 p-4 mb-4"
  >
    <h2 class="text-lg font-semibold">
      {{ ticket.number || ticket.id }} {{ ticket.title }}
    </h2>
    <dl class="flex flex-wrap gap-x-6 gap-y-2 text-sm">
      <div v-for="field in fields" :key="field.label" class="grid gap-1">
        <dt class="text-xs text-n-slate-11">{{ field.label }}</dt>
        <dd>{{ field.value || t('JRC_SERVICE_DESK.COMMON.no_value') }}</dd>
      </div>
    </dl>
    <p v-if="ticket.sla" class="text-xs">
      {{ t('JRC_SERVICE_DESK.R2.sla') }} {{ slaStates[ticket.sla.state] }}
    </p>
    <div v-if="ticket.sla?.clocks?.length" class="grid gap-2 sm:grid-cols-3">
      <div
        v-for="clock in ticket.sla.clocks"
        :key="clock.id"
        class="rounded-lg border border-n-weak p-2 text-xs"
        :class="
          clock.breached
            ? 'bg-n-ruby-3 text-n-ruby-11'
            : 'bg-n-solid-2 text-n-slate-12'
        "
      >
        <strong>{{
          t(`JRC_SERVICE_DESK.LIFECYCLE.clocks.${clock.kind}`)
        }}</strong>
        <p>
          {{
            t('JRC_SERVICE_DESK.R3.consumed', {
              value: Math.round(clock.consumed_percent),
            })
          }}
        </p>
        <p>
          {{
            t('JRC_SERVICE_DESK.R3.remaining', {
              value: Math.round(clock.remaining_seconds / 60),
            })
          }}
        </p>
        <p>{{ t(`JRC_SERVICE_DESK.LIFECYCLE.states.${clock.state}`) }}</p>
      </div>
    </div>
  </header>
</template>
