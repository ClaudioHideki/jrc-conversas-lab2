<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from './ServiceDeskPanel.vue';
import TicketSummary from './TicketSummary.vue';
import TicketTimeline from './TicketTimeline.vue';

defineProps({
  ticket: { type: Object, required: true },
  activeTab: { type: String, required: true },
});
defineEmits(['edit', 'assign', 'tab']);
const { t } = useI18n();
</script>

<template>
  <aside
    class="grid min-w-0 content-start gap-4"
    data-testid="ticket-information"
  >
    <Panel :title="t('JRC_SERVICE_DESK.DETAIL_REVIEW.information')">
      <div class="mb-4 flex flex-wrap justify-end gap-2">
        <Button
          v-if="ticket.permissions.update"
          size="xs"
          color="slate"
          variant="ghost"
          icon="i-lucide-pencil"
          :label="t('JRC_SERVICE_DESK.COMMON.edit')"
          @click="$emit('edit')"
        />
        <Button
          v-if="!ticket.assignee && ticket.permissions.assign"
          size="xs"
          variant="outline"
          icon="i-lucide-user-round-plus"
          :label="t('JRC_SERVICE_DESK.DETAIL_REVIEW.assign')"
          @click="$emit('assign')"
        />
      </div>
      <TicketSummary
        :ticket="ticket"
        compact
      />
    </Panel>
    <Panel
      v-if="ticket.permissions.view_notes"
      :title="t('JRC_SERVICE_DESK.TICKET.tabs.files')"
    >
      <p class="mb-3 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.DETAIL_REVIEW.files_help') }}
      </p>
      <TicketTimeline
        v-if="activeTab !== 'files'"
        :key="`${ticket.id}:${ticket.lock_version}:files`"
        :ticket="ticket"
        view="files"
        only-files
        compact
      />
      <Button
        v-else
        size="xs"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.DETAIL_REVIEW.files_open')"
        @click="$emit('tab', 'files')"
      />
    </Panel>
    <Panel
      v-if="ticket.permissions.view_history && activeTab !== 'history'"
      :title="t('JRC_SERVICE_DESK.DETAIL_REVIEW.status_history')"
    >
      <TicketTimeline
        :key="`${ticket.id}:${ticket.lock_version}:status`"
        :ticket="ticket"
        view="history"
        status-only
        compact
      />
      <Button
        class="mt-3"
        size="xs"
        color="slate"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.DETAIL_REVIEW.full_history')"
        @click="$emit('tab', 'history')"
      />
    </Panel>
  </aside>
</template>
