<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/serviceDeskCockpit';
import HistoryEventCard from './HistoryEventCard.vue';
import State from './ServiceDeskState.vue';
import NotificationControls from './NotificationControls.vue';
import ServiceDeskDialog from './ServiceDeskDialog.vue';
import LookupSelect from './LookupSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { useTicketTimeline } from '../composables/useTicketTimeline';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';
import { formatTimestamp } from '../helpers/presentation';
import { visibleTimelineItems } from '../helpers/detailExperience';
import { newRequestKey } from '../helpers/drafts';

const props = defineProps({
  ticket: { type: Object, required: true },
  revision: { type: Number, default: 0 },
  onlyFiles: Boolean,
  view: { type: String, default: 'all' },
});
const emit = defineEmits(['republish', 'updated']);
const { t, tm, locale } = useI18n();
const labels = computed(() => communicationLabels(t));
const values = computed(() => v2Labels(t));
const session = useServiceDesk();
const filters = reactive({
  event_type: '',
  author_id: '',
  date_from: '',
  date_to: '',
});
const appliedFilters = ref({});
const effectiveView = computed(() => (props.onlyFiles ? 'files' : props.view));
const { items, cursor, status, busy, load } = useTicketTimeline({
  get ticket() {
    return props.ticket;
  },
  get revision() {
    return props.revision;
  },
  get view() {
    return effectiveView.value;
  },
  get filters() {
    return appliedFilters.value;
  },
});
const feedback = ref(null);
const action = ref(null);
const actionBody = ref('');
const actionReason = ref('');
const actionBusy = ref(false);
const actionError = ref('');
let actionKey;
const preview = ref(null);
let alive = true;
let requestEpoch = 0;
let requestController = new AbortController();
const currentRequest = (context, ticket, turn) =>
  alive &&
  turn === requestEpoch &&
  context === session.state.context &&
  session.state.status === 'ready' &&
  ticket.account_id === props.ticket.account_id &&
  ticket.id === props.ticket.id;
const visibleItems = computed(() =>
  visibleTimelineItems(items.value, effectiveView.value)
);
const historyTypes = computed(() =>
  Object.entries(tm('JRC_SERVICE_DESK.OPS.EVENTS')).map(([value, label]) => ({
    value,
    label,
  }))
);
const applyFilters = () => {
  appliedFilters.value = Object.fromEntries(
    Object.entries(filters).filter(([, value]) => value)
  );
};
const openAction = (kind, row, file = null) => {
  action.value = { kind, row, file };
  actionBody.value = row.body || '';
  actionReason.value = '';
  actionError.value = '';
  actionKey = newRequestKey();
};
const actionTitle = computed(() => {
  const label =
    { edit: 'edit_note', file: 'delete_file' }[action.value?.kind] ||
    'delete_note';
  return t(`JRC_SERVICE_DESK.REDESIGN_DETAIL.${label}`);
});
const confirmAction = async () => {
  if (actionBusy.value || !action.value || actionReason.value.trim().length < 3)
    return;
  const context = session.state.context;
  const ticket = props.ticket;
  const current = action.value;
  const turn = requestEpoch;
  const body = actionBody.value;
  actionBusy.value = true;
  actionError.value = '';
  try {
    const reason = actionReason.value.trim();
    let ack;
    if (current.kind === 'edit') {
      ack = await API.updateNote(
        ticket.account_id,
        ticket.id,
        current.row.id,
        body,
        reason,
        actionKey,
        requestController.signal
      );
    } else if (current.kind === 'file') {
      ack = await API.deleteAttachment(
        ticket.account_id,
        ticket.id,
        current.row.id,
        current.file.id,
        reason,
        requestController.signal
      );
    } else {
      ack = await API.deleteNote(
        ticket.account_id,
        ticket.id,
        current.row.id,
        reason,
        requestController.signal
      );
    }
    if (!currentRequest(context, ticket, turn)) return;
    const operation = {
      edit: 'update_note',
      file: 'delete_attachment',
      delete: 'delete_note',
    }[current.kind];
    if (
      ack.applied !== true ||
      ack.operation !== operation ||
      String(ack.account_id) !== ticket.account_id ||
      String(ack.ticket_id) !== ticket.id
    )
      throw new Error('Invalid acknowledgement');
    const rows = await load();
    if (!currentRequest(context, ticket, turn)) return;
    if (!rows) throw new Error('Readback unavailable');
    if (
      current.kind === 'edit' &&
      !rows.some(
        row =>
          row.kind === 'note' &&
          row.id === String(ack.result_id) &&
          row.body === body
      )
    )
      throw new Error('Correction not confirmed');
    action.value = null;
    feedback.value = 'saved';
    emit('updated');
  } catch (error) {
    if (!currentRequest(context, ticket, turn)) return;
    const failure =
      { 409: 'conflict', 401: 'denied', 403: 'denied' }[
        error.response?.status
      ] || 'error';
    actionError.value = t(`JRC_SERVICE_DESK.COCKPIT.${failure}`);
  } finally {
    if (currentRequest(context, ticket, turn)) actionBusy.value = false;
  }
};
const closePreview = () => {
  if (preview.value) URL.revokeObjectURL(preview.value.url);
  preview.value = null;
};
const canPreview = attachment =>
  [
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/avif',
    'application/pdf',
  ].includes(attachment.content_type);
const download = async (row, attachment, display = false) => {
  const context = session.state.context;
  const ticket = props.ticket;
  const turn = requestEpoch;
  try {
    const blob = await API.timelineAttachment(
      context.account_id,
      ticket.id,
      row.kind,
      row.id,
      attachment.id,
      requestController.signal
    );
    if (!currentRequest(context, ticket, turn)) return;
    const url = URL.createObjectURL(blob);
    if (display && canPreview(attachment)) {
      closePreview();
      preview.value = {
        url,
        filename: attachment.filename,
        type: attachment.content_type,
      };
    } else {
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = attachment.filename;
      anchor.click();
      URL.revokeObjectURL(url);
    }
  } catch {
    if (currentRequest(context, ticket, turn)) feedback.value = 'unavailable';
  }
};
const fileSize = value =>
  value >= 1024 * 1024
    ? `${(value / (1024 * 1024)).toFixed(1)} MB`
    : `${Math.ceil((value || 0) / 1024)} KB`;
const messageState = row =>
  values.value.state[row.status] ||
  values.value.delivery[row.status] ||
  t(
    `JRC_SERVICE_DESK.REDESIGN_DETAIL.message_states.${row.status}`,
    t('JRC_SERVICE_DESK.COMMON.not_available')
  );
watch(
  [
    () => props.ticket.id,
    () => props.ticket.account_id,
    () => session.state.context,
    () => session.state.status,
    effectiveView,
  ],
  () => {
    requestEpoch += 1;
    requestController.abort();
    requestController = new AbortController();
    action.value = null;
    actionBusy.value = false;
    feedback.value = null;
    closePreview();
  }
);
onBeforeUnmount(() => {
  alive = false;
  requestEpoch += 1;
  requestController.abort();
  closePreview();
});
</script>

<template>
  <section class="grid gap-3">
    <form
      v-if="effectiveView === 'history'"
      class="grid gap-3 rounded-lg border border-n-weak bg-n-solid-2 p-3 sm:grid-cols-2"
      @submit.prevent="applyFilters"
    >
      <label class="grid gap-1 text-xs"
        >{{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.event_type')
        }}<select
          v-model="filters.event_type"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ t('JRC_SERVICE_DESK.COMMON.all') }}</option>
          <option
            v-for="item in historyTypes"
            :key="item.value"
            :value="item.value"
          >
            {{ item.label }}
          </option>
        </select></label
      >
      <LookupSelect
        v-model="filters.author_id"
        resource="assignees"
        :unit-id="ticket.unit_id"
        :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.author')"
      />
      <label class="grid gap-1 text-xs"
        >{{ t('JRC_SERVICE_DESK.COMMON.date_from')
        }}<input
          v-model="filters.date_from"
          type="date"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <label class="grid gap-1 text-xs"
        >{{ t('JRC_SERVICE_DESK.COMMON.date_to')
        }}<input
          v-model="filters.date_to"
          type="date"
          :min="filters.date_from"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <div class="col-span-full flex gap-2">
        <Button
          type="submit"
          size="xs"
          :disabled="
            busy ||
            (!!filters.date_from &&
              !!filters.date_to &&
              filters.date_from > filters.date_to)
          "
          :label="t('JRC_SERVICE_DESK.COMMON.apply')"
        /><Button
          type="button"
          size="xs"
          color="slate"
          variant="ghost"
          :disabled="busy"
          :label="t('JRC_SERVICE_DESK.COMMON.clear')"
          @click="
            Object.keys(filters).forEach(key => (filters[key] = ''));
            applyFilters();
          "
        />
      </div>
    </form>
    <State
      v-if="!['ready', 'empty'].includes(status)"
      :status="status"
      retry
      @retry="load()"
    />
    <p
      v-if="['ready', 'empty'].includes(status) && !visibleItems.length"
      class="py-6 text-center text-sm text-n-slate-11"
    >
      {{ labels.empty }}
    </p>
    <article
      v-for="row in visibleItems"
      :key="row.key"
      class="grid gap-2 rounded-xl border border-n-weak p-4"
      :class="
        effectiveView === 'notes'
          ? 'bg-n-amber-2'
          : row.message_type === 'outgoing'
            ? 'bg-n-blue-2'
            : 'bg-n-solid-1'
      "
    >
      <div
        v-if="row.kind !== 'event'"
        class="flex flex-wrap items-start justify-between gap-2 text-xs text-n-slate-11"
      >
        <p>
          <span class="font-semibold text-n-slate-12">{{
            row.author?.name || t('JRC_SERVICE_DESK.COMMON.not_informed')
          }}</span>
          · {{ labels.kinds[row.kind] }}
          <span v-if="row.channel">· {{ values.channel[row.channel] }}</span>
        </p>
        <time :datetime="row.created_at">{{
          formatTimestamp(row.created_at, locale)
        }}</time>
      </div>
      <p v-if="row.visibility" class="text-xs font-medium text-n-slate-11">
        {{ values.visibility[row.visibility] }}
      </p>
      <p v-if="row.title" class="font-medium text-sm">{{ row.title }}</p>
      <p
        v-if="row.body && !onlyFiles"
        class="whitespace-pre-wrap break-words text-sm"
      >
        {{ row.body }}
      </p>
      <p v-if="row.comment && !onlyFiles" class="whitespace-pre-wrap text-sm">
        {{ row.comment }}
      </p>
      <HistoryEventCard
        v-if="row.kind === 'event' && row.event_type"
        :event="row"
        :ticket="ticket"
      />
      <p v-if="row.status && !onlyFiles" class="text-xs text-n-slate-11">
        {{ messageState(row) }}
      </p>
      <template v-if="row.kind === 'delivery'">
        <p class="text-sm">
          {{ values.channel[row.channel] }} · {{ values.delivery[row.state] }} ·
          {{ row.recipient }}
        </p>
        <p v-if="row.reason" class="text-xs text-n-amber-11">
          {{ labels.reasons[row.reason] || labels.unavailable }}
        </p>
        <p class="whitespace-pre-wrap break-words text-sm">{{ row.content }}</p>
        <details class="text-xs text-n-slate-11">
          <summary class="cursor-pointer">
            {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delivery_details') }}
          </summary>
          <p>
            {{ labels.attempt }} {{ row.attempt_number }} ·
            {{ labels.policy_version }} {{ row.policy_version }}
          </p>
          <p>
            {{ labels.provider }} {{ row.provider }} · {{ labels.receipt }}
            {{ row.provider_id }}
          </p>
          <p>
            {{
              formatTimestamp(
                row.read_at || row.delivered_at || row.sent_at,
                locale
              )
            }}
          </p>
        </details>
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
        class="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-n-solid-2 p-3"
      >
        <div class="min-w-0 flex-1">
          <p class="break-all text-sm font-medium">{{ attachment.filename }}</p>
          <p v-if="attachment.byte_size" class="text-xs text-n-slate-11">
            {{ fileSize(attachment.byte_size) }} · {{ attachment.content_type }}
          </p>
        </div>
        <div class="flex flex-wrap gap-1">
          <Button
            v-if="canPreview(attachment)"
            size="xs"
            color="slate"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.COMMON.preview')"
            :disabled="attachment.scan_state !== 'clean'"
            @click="download(row, attachment, true)"
          />
          <Button
            size="xs"
            color="slate"
            variant="outline"
            icon="i-lucide-download"
            :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.download')"
            :disabled="attachment.scan_state !== 'clean'"
            @click="download(row, attachment)"
          />
          <Button
            v-if="row.kind === 'note' && attachment.permissions?.destroy"
            size="xs"
            color="ruby"
            variant="ghost"
            icon="i-lucide-trash-2"
            :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delete')"
            @click="openAction('file', row, attachment)"
          />
        </div>
        <p
          v-if="attachment.scan_state !== 'clean'"
          class="w-full text-xs text-n-slate-11"
        >
          {{ t('JRC_SERVICE_DESK.COCKPIT.scan_unavailable') }}
        </p>
      </div>
      <div
        v-if="row.kind === 'note' && !onlyFiles"
        class="flex flex-wrap gap-2"
      >
        <Button
          v-if="
            row.permissions?.update &&
            ['internal', 'technical_team'].includes(row.visibility)
          "
          size="xs"
          color="slate"
          variant="ghost"
          icon="i-lucide-pencil"
          :label="t('JRC_SERVICE_DESK.COMMON.edit')"
          @click="openAction('edit', row)"
        />
        <Button
          v-if="row.permissions?.destroy"
          size="xs"
          color="ruby"
          variant="ghost"
          icon="i-lucide-trash-2"
          :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delete')"
          @click="openAction('delete', row)"
        />
        <Button
          v-if="
            effectiveView !== 'notes' &&
            ticket.permissions.add_note &&
            ['customer', 'public_without_notification'].includes(row.visibility)
          "
          size="xs"
          color="slate"
          variant="ghost"
          :label="t('JRC_SERVICE_DESK.COCKPIT.republish')"
          @click="emit('republish', row)"
        />
      </div>
    </article>
    <Button
      v-if="cursor"
      variant="outline"
      :disabled="busy"
      :label="labels.more"
      @click="load(true)"
    />
    <p v-if="feedback" role="status" class="text-sm">{{ labels[feedback] }}</p>
    <ServiceDeskDialog
      :open="!!action"
      :title="actionTitle"
      :busy="actionBusy"
      @close="action = null"
    >
      <form class="grid gap-4" @submit.prevent="confirmAction">
        <p class="text-sm">
          {{
            t(
              action?.kind === 'edit'
                ? 'JRC_SERVICE_DESK.REDESIGN_DETAIL.note_edit_help'
                : 'JRC_SERVICE_DESK.REDESIGN_DETAIL.withdraw_help'
            )
          }}
        </p>
        <textarea
          v-if="action?.kind === 'edit'"
          v-model="actionBody"
          required
          maxlength="50000"
          rows="6"
          :aria-label="t('JRC_SERVICE_DESK.FIELDS.note')"
          :disabled="actionBusy"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
        />
        <label class="grid gap-2 text-sm"
          >{{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.reason')
          }}<textarea
            v-model="actionReason"
            required
            minlength="3"
            maxlength="1000"
            rows="3"
            :disabled="actionBusy"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          />
        </label>
        <p v-if="actionError" role="alert" class="text-sm text-n-ruby-11">
          {{ actionError }}
        </p>
        <Button
          type="submit"
          :color="action?.kind === 'edit' ? 'blue' : 'ruby'"
          :disabled="
            actionBusy ||
            actionReason.trim().length < 3 ||
            (action?.kind === 'edit' && !actionBody.trim())
          "
          :label="
            t(
              action?.kind === 'edit'
                ? 'JRC_SERVICE_DESK.COMMON.save'
                : 'JRC_SERVICE_DESK.REDESIGN_DETAIL.confirm_delete'
            )
          "
        />
      </form>
    </ServiceDeskDialog>
    <ServiceDeskDialog
      :open="!!preview"
      :title="preview?.filename || t('JRC_SERVICE_DESK.COMMON.preview')"
      @close="closePreview"
    >
      <iframe
        v-if="preview?.type === 'application/pdf'"
        :src="preview.url"
        :title="preview.filename"
        sandbox
        class="h-[65vh] w-full rounded-lg border border-n-weak"
      />
      <img
        v-else-if="preview"
        :src="preview.url"
        :alt="preview.filename"
        class="mx-auto max-h-[65vh] max-w-full object-contain"
      />
    </ServiceDeskDialog>
  </section>
</template>
