<script setup>
import {
  computed,
  defineAsyncComponent,
  nextTick,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CallRecordingPlayer from 'dashboard/components-next/Calls/CallRecordingPlayer.vue';
import RecordingAccessHistory from './RecordingAccessHistory.vue';
import QualityReviewDialog from './QualityReviewDialog.vue';
import RecordingTranscript from './RecordingTranscript.vue';
import RecordingCallContext from './RecordingCallContext.vue';
import RecordingTicketAction from './RecordingTicketAction.vue';
import RecordingLinkedTickets from './RecordingLinkedTickets.vue';
import QualityReviewHistory from './QualityReviewHistory.vue';
import RecordingEndingActions from './RecordingEndingActions.vue';
import RecordingAnalysis from './RecordingAnalysis.vue';
import RecordingManualTasks from './RecordingManualTasks.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  item: { type: Object, required: true },
  capabilities: { type: Object, required: true },
  url: { type: String, default: '' },
  authorizePlayback: { type: Function, required: true },
  formattedDuration: { type: String, default: '' },
  loading: { type: Boolean, default: false },
  error: { type: String, default: '' },
});

const emit = defineEmits(['close', 'playback', 'download', 'playback-error']);

const RecordingTaskCreate = defineAsyncComponent(
  () => import('./RecordingTaskCreate.vue')
);

const { t } = useI18n();
const dialog = ref(null);
const activeTab = ref('recording');
const showHistory = ref(false);
const showQuality = ref(false);
const showQualityHistory = ref(false);
const showActions = ref(false);
const showTaskCreate = ref(false);
const manualTasksRevision = ref(0);
const qualityReadRevision = ref(0);
const closeDetails = () => {
  if (!showTaskCreate.value) emit('close');
};
const createManualTask = () => {
  if (!props.capabilities.recordings_listen) return;
  // Native HTML dialog top-layer must be suspended before the existing
  // Projects modal opens. Keep the selected recording and history mounted.
  showTaskCreate.value = true;
  dialog.value.close();
};
const closeTaskCreate = async () => {
  if (!showTaskCreate.value) return;
  showTaskCreate.value = false;
  manualTasksRevision.value += 1;
  await nextTick();
  if (props.capabilities.recordings_listen) dialog.value?.open();
};
watch(
  () => props.capabilities.audit,
  allowed => {
    if (!allowed) {
      showHistory.value = false;
      if (
        !props.capabilities.recordings_listen &&
        activeTab.value === 'actions'
      )
        activeTab.value = 'recording';
    }
  }
);
watch(
  [
    () => props.accountId,
    () => props.item.id,
    () => props.capabilities.recordings_listen,
  ],
  () => {
    activeTab.value = 'recording';
    showQuality.value = false;
    showQualityHistory.value = false;
    showActions.value = false;
    showTaskCreate.value = false;
  },
  { flush: 'sync' }
);
const labels = computed(() => ({
  AUDIT_HISTORY: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.TITLE'),
  QUALITY: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY'),
  TRANSCRIPT: t('JRC_CONTACT_CENTER.RECORDINGS.TABS.TRANSCRIPT'),
  VOLUME: t('JRC_CONTACT_CENTER.RECORDINGS.TRANSCRIPT.VOLUME'),
  CONTEXT: t('JRC_CONTACT_CENTER.RECORDINGS.TABS.CONTEXT'),
  QUALITY_HISTORY: t('JRC_CONTACT_CENTER.QUALITY_HISTORY.TITLE'),
  ACTIONS: t('JRC_CONTACT_CENTER.RECORDINGS.ACTIONS.TITLE'),
  DETAILS: t('JRC_CONTACT_CENTER.RECORDINGS.DETAILS'),
  ANALYSIS_TAB: t('JRC_CONTACT_CENTER.RECORDINGS.TABS.ANALYSIS'),
  RECORDING_TAB: t('JRC_CONTACT_CENTER.RECORDINGS.TABS.RECORDING'),
  ACTIONS_TAB: t('JRC_CONTACT_CENTER.RECORDINGS.TABS.ACTIONS'),
  CALL: t('JRC_CONTACT_CENTER.RECORDINGS.CALL'),
  CALL_ID: t('JRC_CONTACT_CENTER.RECORDINGS.CALL_ID'),
  RECORDING_ID: t('JRC_CONTACT_CENTER.RECORDINGS.RECORDING_ID'),
  NUMBER: t('JRC_CONTACT_CENTER.RECORDINGS.NUMBER'),
  EXTENSION: t('JRC_CONTACT_CENTER.RECORDINGS.EXTENSION'),
  UNIT: t('JRC_CONTACT_CENTER.RECORDINGS.UNIT'),
  QUEUE: t('JRC_CONTACT_CENTER.RECORDINGS.QUEUE'),
  STARTED: t('JRC_CONTACT_CENTER.RECORDINGS.STARTED'),
  DURATION: t('JRC_CONTACT_CENTER.RECORDINGS.DURATION'),
  NO_MEASUREMENT: t('JRC_CONTACT_CENTER.RECORDINGS.NO_MEASUREMENT'),
  STORAGE_NOT_CONFIRMED: t(
    'JRC_CONTACT_CENTER.RECORDINGS.STORAGE_NOT_CONFIRMED'
  ),
  AVAILABLE: t('JRC_CONTACT_CENTER.RECORDINGS.AVAILABLE'),
  PENDING: t('JRC_CONTACT_CENTER.RECORDINGS.PENDING'),
  LISTEN: t('JRC_CONTACT_CENTER.RECORDINGS.LISTEN'),
  DOWNLOAD: t('JRC_CONTACT_CENTER.RECORDINGS.DOWNLOAD'),
  CLOSE: t('JRC_CONTACT_CENTER.RECORDINGS.CLOSE'),
  MEDIA_ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.MEDIA_ERROR'),
  MEDIA_AUDIT_ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.MEDIA_AUDIT_ERROR'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDINGS.DENIED'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.ERROR'),
}));
const text = key => labels.value[key];
const available = computed(() => props.item.recording_state === 'requestable');
const tabs = computed(() => [
  ...(props.capabilities.recordings_listen
    ? [
        {
          key: 'analysis',
          label: 'ANALYSIS_TAB',
          color: 'border-n-violet-6 text-n-violet-11',
        },
        {
          key: 'transcript',
          label: 'TRANSCRIPT',
          color: 'border-n-cyan-6 text-n-cyan-11',
        },
      ]
    : []),
  {
    key: 'recording',
    label: 'RECORDING_TAB',
    color: 'border-n-blue-6 text-n-blue-11',
  },
  ...(props.capabilities.recordings_listen
    ? [
        {
          key: 'context',
          label: 'CONTEXT',
          color: 'border-n-teal-6 text-n-teal-11',
        },
      ]
    : []),
  ...(props.capabilities.recordings_listen || props.capabilities.audit
    ? [
        {
          key: 'actions',
          label: 'ACTIONS_TAB',
          color: 'border-n-amber-6 text-n-amber-12 dark:text-n-amber-11',
        },
      ]
    : []),
]);
const identity = (kind, key) =>
  `recording-${props.accountId}-${props.item.id}-${kind}-${key}`;
function selectTab(key) {
  activeTab.value = key;
  if (key === 'actions') {
    showQualityHistory.value = props.capabilities.recordings_listen === true;
    showHistory.value = props.capabilities.audit === true;
    showActions.value =
      props.capabilities.recordings_listen &&
      (props.capabilities.operate || props.capabilities.audit);
  }
}
function navigateTabs(event) {
  const keys = tabs.value.map(tab => tab.key);
  const position = keys.indexOf(activeTab.value);
  let next;
  if (event.key === 'ArrowRight') next = (position + 1) % keys.length;
  else if (event.key === 'ArrowLeft')
    next = (position + keys.length - 1) % keys.length;
  else if (event.key === 'Home') next = 0;
  else if (event.key === 'End') next = keys.length - 1;
  else return;
  event.preventDefault();
  selectTab(keys[next]);
  event.currentTarget.querySelectorAll('[role="tab"]')[next]?.focus();
}

// Only the existing authorized public DTO is presented. No storage URL,
// provider reference, inferred legal retention, or invented integrity status.
const metadata = computed(() => [
  ['CALL', props.item.unique_id],
  ['CALL_ID', props.item.call_session_id],
  ['RECORDING_ID', props.item.id],
  ['NUMBER', props.item.external_number],
  ['EXTENSION', props.item.extension],
  ['UNIT', props.item.unit_name],
  ['QUEUE', props.item.queue_name],
  ['STARTED', props.item.started_at],
  ['DURATION', props.formattedDuration],
]);
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="text('DETAILS')"
    width="xl"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :close-on-click-outside="false"
    contained
    @close="closeDetails"
  >
    <div
      class="min-w-0 space-y-4 text-sm text-n-slate-12"
      data-recording-selected
    >
      <nav
        class="flex flex-wrap gap-2"
        role="tablist"
        :aria-label="text('DETAILS')"
        data-recording-tabs
        @keydown="navigateTabs"
      >
        <button
          v-for="tab in tabs"
          :id="identity('tab', tab.key)"
          :key="tab.key"
          type="button"
          role="tab"
          :aria-controls="identity('panel', tab.key)"
          :aria-selected="activeTab === tab.key"
          :tabindex="activeTab === tab.key ? 0 : -1"
          :class="[
            tab.color,
            activeTab === tab.key
              ? 'bg-n-alpha-2 ring-1 ring-current'
              : 'bg-n-solid-1',
          ]"
          class="min-w-0 rounded-lg border px-3 py-2 text-left text-sm font-medium"
          :data-recording-analysis-open="tab.key === 'analysis' ? '' : null"
          :data-recording-audio-open="tab.key === 'recording' ? '' : null"
          :data-recording-transcript-open="tab.key === 'transcript' ? '' : null"
          :data-recording-context-open="tab.key === 'context' ? '' : null"
          :data-recording-quality-history-open="
            tab.key === 'actions' && capabilities.recordings_listen ? '' : null
          "
          :data-recording-actions-open="
            tab.key === 'actions' &&
            capabilities.recordings_listen &&
            (capabilities.operate || capabilities.audit)
              ? ''
              : null
          "
          :data-recording-audit-open="
            tab.key === 'actions' && capabilities.audit ? '' : null
          "
          @click="selectTab(tab.key)"
        >
          {{ text(tab.label) }}
        </button>
      </nav>
      <RecordingAnalysis
        v-if="activeTab === 'analysis' && capabilities.recordings_listen"
        :id="identity('panel', 'analysis')"
        :key="`${accountId}-${item.id}-${qualityReadRevision}`"
        role="tabpanel"
        :aria-labelledby="identity('tab', 'analysis')"
        :account-id="accountId"
        :recording-id="item.id"
      />
      <div
        v-if="activeTab === 'recording'"
        :id="identity('panel', 'recording')"
        role="tabpanel"
        :aria-labelledby="identity('tab', 'recording')"
        class="space-y-4"
      >
        <dl class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2">
          <div v-for="[key, value] in metadata" :key="key" class="min-w-0">
            <dt class="text-xs text-n-slate-11">{{ text(key) }}</dt>
            <dd class="break-all">{{ value || text('NO_MEASUREMENT') }}</dd>
          </div>
        </dl>
        <p class="text-n-slate-11">
          {{ text(available ? 'AVAILABLE' : 'PENDING') }}
        </p>
        <p class="rounded-lg border border-n-weak p-3 text-n-slate-11">
          {{ text('STORAGE_NOT_CONFIRMED') }}
        </p>
      </div>
      <p v-if="error" role="alert" class="break-words text-n-ruby-11">
        {{ text(error) }}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="capabilities.recordings_listen"
          type="button"
          :disabled="loading || !available"
          class="rounded-lg border border-n-violet-6 px-3 py-2 text-n-violet-11"
          data-recording-listen
          @click="emit('playback')"
        >
          {{ text('LISTEN') }}
        </button>
        <button
          v-if="capabilities.recordings_download"
          type="button"
          :disabled="loading || !available"
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
          data-recording-download
          @click="emit('download')"
        >
          {{ text('DOWNLOAD') }}
        </button>
      </div>
      <button
        v-if="capabilities.recordings_listen"
        type="button"
        class="rounded-lg border border-n-violet-6 px-3 py-2 text-n-violet-11"
        data-recording-quality-open
        @click="showQuality = true"
      >
        {{ text('QUALITY') }}
      </button>
      <RecordingTranscript
        v-if="activeTab === 'transcript' && capabilities.recordings_listen"
        :id="identity('panel', 'transcript')"
        :key="`${accountId}-${item.id}`"
        role="tabpanel"
        :aria-labelledby="identity('tab', 'transcript')"
        :account-id="accountId"
        :recording-id="item.id"
        :call-id="item.unique_id"
      />
      <CallRecordingPlayer
        v-if="url && capabilities.recordings_listen"
        :key="url"
        :src="url"
        :fallback-duration="item.talk_duration_seconds || 0"
        :can-download="false"
        :volume-label="text('VOLUME')"
        :before-playback="authorizePlayback"
        @error="emit('playback-error')"
      />
      <RecordingCallContext
        v-if="activeTab === 'context' && capabilities.recordings_listen"
        :id="identity('panel', 'context')"
        :key="`${accountId}-${item.id}`"
        role="tabpanel"
        :aria-labelledby="identity('tab', 'context')"
        :account-id="accountId"
        :recording-id="item.id"
        :call-session-id="item.call_session_id"
        :call-id="item.unique_id"
        :operational-context-allowed="capabilities.operate === true"
      />
      <section
        v-if="activeTab === 'actions'"
        :id="identity('panel', 'actions')"
        role="tabpanel"
        :aria-labelledby="identity('tab', 'actions')"
        class="space-y-4"
      >
        <RecordingTicketAction
          v-if="capabilities.recordings_listen && capabilities.operate"
          :key="`ticket-${accountId}-${item.id}`"
          :account-id="accountId"
          :recording-id="item.id"
          :call-session-id="item.call_session_id"
          :call-id="item.unique_id"
          enabled
        />
        <RecordingLinkedTickets
          v-if="capabilities.recordings_listen"
          :key="`linked-tickets-${accountId}-${item.id}`"
          :account-id="accountId"
          :recording-id="item.id"
          :call-session-id="item.call_session_id"
          :call-id="item.unique_id"
          :authority-key="JSON.stringify([accountId, item.id, capabilities])"
        />
        <RecordingManualTasks
          v-if="capabilities.recordings_listen"
          :key="`${accountId}-${item.id}`"
          :account-id="accountId"
          :recording-id="item.id"
          :call-session-id="item.call_session_id"
          :call-id="item.unique_id"
          :authority-key="JSON.stringify([accountId, item.id, capabilities])"
          :revision="manualTasksRevision"
          @create="createManualTask"
        />
        <QualityReviewHistory
          v-if="showQualityHistory && capabilities.recordings_listen"
          :key="`${accountId}-${item.id}-${qualityReadRevision}`"
          :account-id="accountId"
          :recording-id="item.id"
        />
        <RecordingEndingActions
          v-if="
            showActions &&
            capabilities.recordings_listen &&
            (capabilities.operate || capabilities.audit)
          "
          :key="`${accountId}-${item.id}`"
          :account-id="accountId"
          :recording-id="item.id"
          :call-session-id="item.call_session_id"
          :call-id="item.unique_id"
          :authority-key="JSON.stringify([accountId, item.id, capabilities])"
        />
        <RecordingAccessHistory
          v-if="showHistory && capabilities.audit"
          :key="`${accountId}-${item.id}`"
          :account-id="accountId"
          :recording-id="item.id"
        />
      </section>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2 text-n-slate-12"
        data-recording-close
        @click="dialog.close()"
      >
        {{ text('CLOSE') }}
      </button>
    </div>
  </Dialog>
  <RecordingTaskCreate
    v-if="showTaskCreate && capabilities.recordings_listen"
    :key="`${accountId}-${item.id}`"
    :account-id="accountId"
    :recording-id="item.id"
    :authority-key="JSON.stringify([accountId, item.id, capabilities])"
    @close="closeTaskCreate"
  />
  <QualityReviewDialog
    v-if="showQuality && capabilities.recordings_listen"
    :key="`${accountId}-${item.id}`"
    :account-id="accountId"
    :recording="item"
    :formatted-duration="formattedDuration"
    @close="showQuality = false"
    @saved="qualityReadRevision += 1"
  />
</template>
