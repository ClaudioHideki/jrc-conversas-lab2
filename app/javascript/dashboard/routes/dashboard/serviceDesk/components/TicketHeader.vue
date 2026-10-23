<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTimestamp } from '../helpers/presentation';
import TicketProtocol from './TicketProtocol.vue';

const props = defineProps({ ticket: { type: Object, required: true } });
const { t, te, locale } = useI18n();
const source = computed(() => {
  const value = props.ticket.source;
  const key = `JRC_SERVICE_DESK.REDESIGN_LIST.sources.${value}`;
  return te(key) ? t(key) : value;
});
</script>

<template>
  <header
    class="sticky top-0 z-10 mb-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
  >
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-center gap-2">
          <TicketProtocol :ticket="ticket" compact />
          <h2 class="m-0 min-w-0 break-words text-lg font-semibold">
            {{ ticket.title }}
          </h2>
          <span
            v-if="ticket.status"
            class="rounded-full bg-n-blue-3 px-2 py-1 text-xs font-medium text-n-blue-11"
            >{{ ticket.status.name }}</span
          >
          <span
            v-if="ticket.priority"
            class="rounded-full bg-n-amber-3 px-2 py-1 text-xs font-medium text-n-amber-11"
            >{{ ticket.priority.name }}</span
          >
        </div>
        <p class="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs text-n-slate-11">
          <span
            >{{ t('JRC_SERVICE_DESK.FIELDS.opened_at') }}
            {{
              formatTimestamp(ticket.opened_at || ticket.created_at, locale)
            }}</span
          >
          <span v-if="source"
            >{{ t('JRC_SERVICE_DESK.FIELDS.source') }}: {{ source }}</span
          >
          <span
            >{{ t('JRC_SERVICE_DESK.FIELDS.assignee') }}:
            {{
              ticket.assignee?.name ||
              t('JRC_SERVICE_DESK.REDESIGN_DETAIL.unassigned')
            }}</span
          >
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <slot name="actions" />
      </div>
    </div>
  </header>
</template>
