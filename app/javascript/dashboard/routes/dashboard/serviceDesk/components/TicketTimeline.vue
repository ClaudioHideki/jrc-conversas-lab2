<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/serviceDeskCockpit';
import HistoryEventCard from './HistoryEventCard.vue';
import State from './ServiceDeskState.vue';
import NotificationControls from './NotificationControls.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { useTicketTimeline } from '../composables/useTicketTimeline';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';
import { formatTimestamp } from '../helpers/presentation';

const props = defineProps({
  ticket: { type: Object, required: true },
  revision: { type: Number, default: 0 },
  onlyFiles: Boolean,
});
const emit = defineEmits(['republish', 'updated']);
const { t, locale } = useI18n();
const labels = computed(() => communicationLabels(t));
const values = computed(() => v2Labels(t));
const session = useServiceDesk();
const { items, cursor, status, busy, load } = useTicketTimeline({
  get ticket() {
    return props.ticket;
  },
  get revision() {
    return props.revision;
  },
});
const feedback = ref(null);
const visibleItems = computed(() =>
  props.onlyFiles
    ? items.value.filter(
        row => row.attachments?.length || row.recordings?.length
      )
    : items.value
);
const download = async (row, attachment) => {
  const context = session.state.context;
  try {
    const blob = await API.timelineAttachment(
      context.account_id,
      props.ticket.id,
      row.kind,
      row.id,
      attachment.id
    );
    if (context !== session.state.context || session.state.status !== 'ready')
      return;
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = attachment.filename;
    anchor.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    feedback.value = 'unavailable';
  }
};
</script>

<template>
  <section class="grid gap-3">
    <h3 class="font-semibold">{{ labels.timeline }}</h3>
    <State
      v-if="!['ready', 'empty'].includes(status)"
      :status="status"
      retry
      @retry="load()"
    />
    <p v-if="status === 'empty'" class="text-sm">{{ labels.empty }}</p>
    <p
      v-if="onlyFiles && status === 'ready' && !visibleItems.length"
      class="text-sm"
    >
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.no_files_in_page') }}
    </p>
    <article
      v-for="row in visibleItems"
      :key="row.key"
      class="grid gap-2 rounded-lg border border-n-weak p-3"
    >
      <p class="text-xs text-n-slate-11">
        {{ labels.kinds[row.kind] }} {{ row.author?.name }}
        {{ formatTimestamp(row.created_at, locale) }}
      </p>
      <p v-if="row.visibility" class="text-xs font-semibold">
        {{ values.visibility[row.visibility] }}
      </p>
      <p v-if="row.title" class="font-medium text-sm">{{ row.title }}</p>
      <p v-if="row.body" class="whitespace-pre-wrap break-words text-sm">
        {{ row.body }}
      </p>
      <p v-if="row.comment" class="whitespace-pre-wrap text-sm">
        {{ row.comment }}
      </p>
      <HistoryEventCard
        v-if="row.kind === 'event' && row.event_type"
        :event="row"
        :ticket="ticket"
      />
      <p v-else-if="row.event_type" class="text-sm">
        {{ values.event[row.event_type] || labels.kinds.event }}
      </p>
      <p v-if="row.status" class="text-xs">
        {{
          values.state[row.status] || values.delivery[row.status] || row.status
        }}
      </p>
      <template v-if="row.kind === 'delivery'">
        <p class="text-sm">
          {{ values.channel[row.channel] }} {{ values.delivery[row.state] }}
          {{ row.recipient }}
        </p>
        <p v-if="row.reason" class="text-xs">
          {{ labels.reasons[row.reason] || labels.unavailable }}
        </p>
        <p class="text-xs">
          {{ labels.attempt }} {{ row.attempt_number }}
          {{ labels.policy_version }} {{ row.policy_version }}
        </p>
        <p class="text-xs">
          {{ labels.provider }} {{ row.provider }} {{ labels.executor }}
          {{ row.author?.name }}
        </p>
        <p class="text-xs">
          {{ labels.receipt }} {{ row.provider_id }}
          {{
            formatTimestamp(
              row.read_at || row.delivered_at || row.sent_at,
              locale
            )
          }}
        </p>
        <p class="whitespace-pre-wrap text-sm">{{ row.content }}</p>
        <NotificationControls
          :row="row"
          :ticket="ticket"
          @updated="
            load();
            emit('updated');
          "
        />
      </template>
      <div
        v-for="attachment in [
          ...(row.attachments || []),
          ...(row.recordings || []),
        ]"
        :key="attachment.id"
        class="flex items-center gap-2"
      >
        <Button
          size="xs"
          variant="outline"
          :label="attachment.filename"
          :disabled="attachment.scan_state !== 'clean'"
          @click="download(row, attachment)"
        />
        <p v-if="attachment.scan_state !== 'clean'" class="text-xs">
          {{ t('JRC_SERVICE_DESK.COCKPIT.scan_unavailable') }}
        </p>
      </div>
      <Button
        v-if="row.kind === 'note' && ticket.permissions.add_note"
        size="xs"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.COCKPIT.republish')"
        @click="emit('republish', row)"
      />
    </article>
    <Button
      v-if="cursor"
      variant="outline"
      :disabled="busy"
      :label="labels.more"
      @click="load(true)"
    />
    <p v-if="feedback" role="status" class="text-sm">{{ labels[feedback] }}</p>
  </section>
</template>
