<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CallRecordingPlayer from 'dashboard/components-next/Calls/CallRecordingPlayer.vue';
import RecordingAccessHistory from './RecordingAccessHistory.vue';
import QualityReviewDialog from './QualityReviewDialog.vue';

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
const { t } = useI18n();
const dialog = ref(null);
const showHistory = ref(false);
const showQuality = ref(false);
watch(
  () => props.capabilities.audit,
  allowed => {
    if (!allowed) showHistory.value = false;
  }
);
const labels = computed(() => ({
  AUDIT_HISTORY: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.TITLE'),
  QUALITY: t('JRC_CONTACT_CENTER.RECORDINGS.QUALITY'),
  DETAILS: t('JRC_CONTACT_CENTER.RECORDINGS.DETAILS'),
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
    @close="emit('close')"
  >
    <div
      class="min-w-0 space-y-4 text-sm text-n-slate-12"
      data-recording-selected
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
      <CallRecordingPlayer
        v-if="url && capabilities.recordings_listen"
        :key="url"
        :src="url"
        :fallback-duration="item.talk_duration_seconds || 0"
        :can-download="false"
        :before-playback="authorizePlayback"
        @error="emit('playback-error')"
      />
      <button
        v-if="capabilities.audit"
        type="button"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
        data-recording-audit-open
        :aria-expanded="showHistory"
        @click="showHistory = !showHistory"
      >
        {{ text('AUDIT_HISTORY') }}
      </button>
      <RecordingAccessHistory
        v-if="showHistory && capabilities.audit"
        :key="`${accountId}-${item.id}`"
        :account-id="accountId"
        :recording-id="item.id"
      />
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
  <QualityReviewDialog
    v-if="showQuality && capabilities.recordings_listen"
    :key="`${accountId}-${item.id}`"
    :account-id="accountId"
    :recording="item"
    :formatted-duration="formattedDuration"
    @close="showQuality = false"
  />
</template>
