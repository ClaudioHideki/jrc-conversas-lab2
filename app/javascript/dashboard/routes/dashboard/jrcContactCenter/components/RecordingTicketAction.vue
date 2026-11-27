<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/jrcContactCenter';
import { decodeRecordingTicketSource } from '../../serviceDesk/helpers/recordingTicketSource';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  contactId: { type: [String, Number], default: null },
  enabled: { type: Boolean, default: false },
});
const { t } = useI18n();
const router = useRouter();
const actor = useMapGetter('getCurrentUserID');
const source = ref(null);
const loading = ref(false);
const opening = ref(false);
const failed = ref(false);
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([
    props.accountId,
    props.recordingId,
    props.callSessionId,
    props.callId,
    props.contactId,
    props.enabled,
    actor.value,
  ])
);
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  source.value = null;
  failed.value = false;
  loading.value = false;
  if (!props.enabled) return null;
  const original = identity.value;
  const request = new AbortController();
  controller = request;
  loading.value = true;
  try {
    const { data } = await API.recordingTicketIntake(
      props.accountId,
      props.recordingId,
      { signal: request.signal }
    );
    if (
      version !== generation ||
      request.signal.aborted ||
      original !== identity.value
    )
      return null;
    const value = decodeRecordingTicketSource(
      data,
      props.accountId,
      actor.value,
      props.recordingId
    );
    if (
      value.call_session_id !== String(props.callSessionId) ||
      value.call_id !== props.callId ||
      (props.contactId != null && value.contact_id !== String(props.contactId))
    )
      throw new TypeError('Native recording context changed');
    source.value = value;
    return value;
  } catch {
    if (version === generation && !request.signal.aborted) failed.value = true;
    return null;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const open = async () => {
  if (opening.value || loading.value || !source.value) return;
  opening.value = true;
  const original = identity.value;
  try {
    const value = await load();
    if (!value || original !== identity.value) return;
    await router.push({
      name: 'jrc_service_desk_new',
      params: { accountId: value.account_id },
      query: { recording_id: value.recording_id },
    });
  } catch {
    failed.value = true;
  } finally {
    opening.value = false;
  }
};
watch(identity, load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  source.value = null;
});
</script>

<template>
  <div class="min-w-0 space-y-2" data-recording-ticket-action>
    <template v-if="enabled">
      <p v-if="loading" role="status" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.RECORDING_TICKET.LOADING') }}
      </p>
      <button
        v-if="source"
        type="button"
        data-open-native-recording-ticket
        class="inline-flex max-w-full items-center gap-2 rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm font-semibold text-n-blue-12"
        :disabled="loading || opening"
        @click="open"
      >
        <span class="i-lucide-ticket-plus size-4 shrink-0" aria-hidden="true" />
        {{ t('JRC_CONTACT_CENTER.RECORDING_TICKET.OPEN') }}
      </button>
      <template v-if="failed">
        <p role="alert" class="break-words text-sm text-n-ruby-11">
          {{ t('JRC_CONTACT_CENTER.RECORDING_TICKET.UNAVAILABLE') }}
        </p>
        <button
          type="button"
          :disabled="loading || opening"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-blue-11"
          @click="load"
        >
          {{ t('JRC_CONTACT_CENTER.RECORDING_TICKET.RETRY') }}
        </button>
      </template>
    </template>
  </div>
</template>
