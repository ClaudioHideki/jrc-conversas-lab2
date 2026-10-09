<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
import TicketProtocol from './TicketProtocol.vue';

const props = defineProps({ ticket: { type: Object, required: true } });
const emit = defineEmits(['open', 'list', 'createAnother']);
const { t } = useI18n();
const fields = computed(() => [
  {
    label: t('JRC_SERVICE_DESK.FIELDS.status'),
    value: props.ticket.status?.name,
  },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.queue'),
    value: props.ticket.queue?.name,
  },
  { label: t('JRC_SERVICE_DESK.FIELDS.team'), value: props.ticket.team?.name },
  {
    label: t('JRC_SERVICE_DESK.FIELDS.assignee'),
    value:
      props.ticket.assignee?.name || t('JRC_SERVICE_DESK.CREATION.unassigned'),
  },
]);
</script>

<template>
  <Panel
    :title="t('JRC_SERVICE_DESK.CREATION.title')"
    data-testid="ticket-created-receipt"
  >
    <p role="status" class="text-sm text-n-teal-11">
      {{ t('JRC_SERVICE_DESK.CREATION.verified') }}
    </p>
    <TicketProtocol :ticket="ticket" />
    <h3 class="my-3 break-words text-lg font-semibold">{{ ticket.title }}</h3>
    <dl class="grid gap-3 sm:grid-cols-2">
      <div v-for="field in fields" :key="field.label">
        <dt class="text-xs text-n-slate-11">{{ field.label }}</dt>
        <dd class="m-0 break-words text-sm">
          {{ field.value || t('JRC_SERVICE_DESK.COMMON.no_value') }}
        </dd>
      </div>
    </dl>
    <p v-if="!ticket.assignee" class="mt-3 text-sm text-n-amber-11">
      {{ t('JRC_SERVICE_DESK.CREATION.assignment_pending') }}
    </p>
    <p class="mt-3 text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.CREATION.delivery_help') }}
    </p>
    <div class="mt-4 flex flex-wrap gap-3">
      <Button
        :label="t('JRC_SERVICE_DESK.CREATION.open')"
        data-testid="open-created-ticket"
        @click="emit('open', ticket.id)"
      />
      <Button
        :label="t('JRC_SERVICE_DESK.SCREENS.tickets')"
        variant="outline"
        @click="emit('list')"
      />
      <Button
        :label="t('JRC_SERVICE_DESK.CREATION.create_another')"
        variant="ghost"
        color="slate"
        @click="emit('createAnother')"
      />
    </div>
  </Panel>
</template>
