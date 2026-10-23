<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCallsStore } from 'dashboard/stores/calls';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
import { useSipWebphone } from '../webphone/useSipWebphone';
import { normalizeSipDialNumber } from '../webphone/phoneNumber';
import { useEmbeddedSoftphone } from '../webphone/useEmbeddedSoftphone';
import { callStateLabels } from './inboxPresentation';

const props = defineProps({
  accountId: { type: Number, required: true },
  allowed: { type: Boolean, default: false },
  capabilities: { type: Object, default: () => ({}) },
  qualificationPending: { type: Boolean, default: false },
  nativeCallId: { type: Number, default: null },
  callRecord: { type: Object, default: null },
  customer: { type: Object, default: null },
  ambiguous: { type: Boolean, default: false },
  sessionView: { type: Boolean, default: false },
  elapsed: { type: String, default: '' },
});
const emit = defineEmits(['open', 'ended', 'updated']);
const { t, locale } = useI18n();
const sip = useSipWebphone();
const calls = useCallsStore();
const { isInitiating } = useWhatsappCallSession();
const input = ref(null);
const keypadOpen = ref(false);
const transferOpen = ref(false);
const transferMode = ref('immediate');
const transferDestination = ref('');
const transferSent = ref(false);
const pending = ref(false);
const actionError = ref(false);
const note = ref('');
const noteBaseline = ref('');
const noteVersion = ref(null);
const noteSaving = ref(false);
const noteError = ref('');
const noteSaved = ref(false);
const lastRemote = ref('');
const lastDuration = ref('');
const sameAccount = computed(
  () => Number(sip.accountId.value) === props.accountId
);
const independentSession = computed(
  () => !props.nativeCallId && !props.callRecord
);
const available = computed(
  () =>
    props.allowed &&
    sameAccount.value &&
    (independentSession.value ||
      ['available', 'pending_contract'].includes(props.capabilities.sip_webrtc))
);
// A selected server record may only control its exact native SIP session.
const matches = computed(
  () =>
    available.value &&
    ((independentSession.value && props.sessionView) ||
      (!independentSession.value &&
        props.capabilities.sip_webrtc === 'available' &&
        Boolean(props.callRecord?.external_session_id) &&
        props.callRecord.external_session_id === sip.callId.value))
);
const otherBusy = computed(
  () => calls.hasActiveCall || calls.hasIncomingCall || isInitiating.value
);
const canEnd = computed(
  () => matches.value && sip.hasCall.value && !pending.value
);
const canAnswer = computed(
  () =>
    canEnd.value &&
    sip.incoming.value &&
    !otherBusy.value &&
    !props.qualificationPending
);
const canControl = computed(
  () =>
    matches.value && sip.established.value && !pending.value && !otherBusy.value
);
const canDial = computed(
  () =>
    available.value &&
    independentSession.value &&
    props.sessionView &&
    !sip.hasCall.value &&
    !otherBusy.value &&
    !props.qualificationPending &&
    sip.registered.value &&
    !pending.value &&
    Boolean(normalizeSipDialNumber(sip.destination.value))
);
const hasInteraction = computed(() =>
  Boolean(
    props.nativeCallId ||
      (props.sessionView && (sip.hasCall.value || lastRemote.value))
  )
);
const dialDestination = computed({
  get: () => (available.value ? sip.destination.value : ''),
  set: value => {
    if (
      available.value &&
      !sip.hasCall.value &&
      !otherBusy.value &&
      !props.qualificationPending
    )
      sip.destination.value = value;
  },
});
const number = computed(() => {
  if (props.callRecord)
    return props.callRecord.direction === 'outbound'
      ? props.callRecord.dnis
      : props.callRecord.ani;
  return matches.value ? lastRemote.value : '';
});
const customerName = computed(() =>
  props.ambiguous
    ? t('JRC_CONTACT_CENTER.CALL.AMBIGUOUS')
    : props.customer?.name || t('SOFTPHONE.CENTRAL.UNKNOWN_CUSTOMER')
);
const initials = computed(() =>
  props.ambiguous || !props.customer?.name
    ? '?'
    : props.customer.name
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map(word => word[0])
        .join('')
        .toUpperCase()
);
const state = computed(() => {
  if (matches.value) {
    if (sip.incoming.value) return 'incoming';
    if (sip.held.value) return 'held';
    if (sip.established.value) return 'connected';
    if (sip.hasCall.value) return 'calling';
    if (sip.sessionState.value === 'Terminated' && hasInteraction.value)
      return 'ended';
  }
  return props.callRecord?.status || '';
});
const stateLabel = computed(() =>
  ['incoming', 'calling', 'connected', 'held', 'ended'].includes(state.value)
    ? t(`SOFTPHONE.CENTRAL.STATES.${state.value}`)
    : callStateLabels(t)[state.value] || t('SOFTPHONE.CENTRAL.NO_CALL')
);
const duration = computed(() => {
  if (matches.value) {
    if (sip.established.value) return sip.duration.value;
    if (sip.sessionState.value === 'Terminated' && !props.callRecord?.ended_at)
      return lastDuration.value;
  }
  return props.elapsed || (matches.value ? lastDuration.value : '');
});
const supportsTransfer = mode =>
  independentSession.value ||
  props.capabilities[
    mode === 'immediate' ? 'transfer_blind' : 'transfer_attended'
  ] === 'available';
const tones = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
const info = computed(() => [
  [
    'START',
    props.callRecord?.started_at
      ? new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
          dateStyle: 'short',
          timeStyle: 'short',
        }).format(new Date(props.callRecord.started_at))
      : null,
  ],
  ['DURATION', duration.value],
  ['ORIGIN', props.callRecord?.ani],
  ['DESTINATION', props.callRecord?.dnis],
  ['QUEUE', props.callRecord?.queue?.name],
  ['AGENT', props.callRecord?.attendant?.name],
  ['STATUS', stateLabel.value],
]);
const selectionKey = computed(
  () => `${props.accountId}:${props.nativeCallId || 'session'}`
);
watch(selectionKey, () => {
  note.value = '';
  noteBaseline.value = '';
  noteVersion.value = null;
  noteSaving.value = false;
  noteError.value = '';
  noteSaved.value = false;
  lastRemote.value = '';
  lastDuration.value = '';
  keypadOpen.value = false;
  transferOpen.value = false;
});
watch(
  () => props.callRecord,
  record => {
    if (!record || record.id !== props.nativeCallId) return;
    // Refreshes must not silently overwrite the operator's unsaved edit/version.
    if (note.value === noteBaseline.value) {
      note.value = record.metadata?.attendance_observations?.text || '';
      noteBaseline.value = note.value;
      noteVersion.value = record.lock_version;
    }
  },
  { immediate: true }
);
watch(
  [() => sip.remoteNumber.value, matches],
  ([remote, matching]) => {
    if (matching && remote && remote !== '—') lastRemote.value = remote;
  },
  { immediate: true }
);
watch(
  [() => sip.duration.value, matches, () => sip.established.value],
  ([value, matching]) => {
    if (matching && sip.established.value) lastDuration.value = value;
  },
  { immediate: true }
);
const run = async (allowed, action) => {
  if (!allowed || pending.value) return;
  const account = props.accountId;
  pending.value = true;
  actionError.value = false;
  try {
    await action();
  } catch {
    if (account === props.accountId) actionError.value = true;
  } finally {
    pending.value = false;
  }
};
const endCall = () =>
  run(canEnd.value, async () => {
    await sip.hangup();
    emit('ended');
  });
const startCall = () =>
  run(canDial.value, () => {
    sip.destination.value = normalizeSipDialNumber(sip.destination.value);
    return sip.call();
  });
const key = tone => {
  if (!available.value || pending.value || otherBusy.value) return;
  if (sip.hasCall.value) {
    if (canControl.value) sip.pressKey(tone);
  } else if (props.sessionView && !props.qualificationPending)
    sip.destination.value += tone;
};
const transfer = () =>
  run(
    canControl.value &&
      supportsTransfer(transferMode.value) &&
      !sip.holdPending.value &&
      !sip.transferring.value &&
      /^\d+$/.test(transferDestination.value),
    async () => {
      transferSent.value = await sip.transferCall(
        transferMode.value,
        transferDestination.value
      );
      if (transferSent.value) transferOpen.value = false;
    }
  );
const controls = computed(() => [
  {
    key: 'MUTE',
    label: matches.value && sip.muted.value ? 'UNMUTE' : 'MUTE',
    icon:
      matches.value && sip.muted.value ? 'i-lucide-mic' : 'i-lucide-mic-off',
    enabled: canControl.value,
    action: () => sip.setMuted(!sip.muted.value),
  },
  {
    key: 'KEYPAD',
    label: 'KEYPAD',
    icon: 'i-lucide-grip',
    enabled: canControl.value,
    action: () => {
      keypadOpen.value = !keypadOpen.value;
    },
  },
  {
    key: 'HOLD',
    label: matches.value && sip.held.value ? 'RESUME' : 'HOLD',
    icon: matches.value && sip.held.value ? 'i-lucide-play' : 'i-lucide-pause',
    enabled:
      canControl.value &&
      (independentSession.value || props.capabilities.hold === 'available') &&
      !sip.holdPending.value,
    action: () => sip.setHold(!sip.held.value),
  },
  {
    key: 'TRANSFER',
    label: 'TRANSFER',
    icon: 'i-lucide-arrow-right',
    enabled:
      canControl.value &&
      (supportsTransfer('immediate') || supportsTransfer('supervised')),
    action: () => {
      transferMode.value = supportsTransfer('immediate')
        ? 'immediate'
        : 'supervised';
      transferOpen.value = !transferOpen.value;
    },
  },
]);
const saveNote = async () => {
  if (
    !props.allowed ||
    !props.nativeCallId ||
    noteSaving.value ||
    note.value.length > 1000 ||
    noteVersion.value === null
  )
    return;
  const keyAtStart = selectionKey.value;
  const text = note.value;
  noteSaving.value = true;
  noteError.value = '';
  noteSaved.value = false;
  try {
    const response = await ContactCenterAPI.saveCallObservations(
      props.accountId,
      props.nativeCallId,
      { text, lock_version: noteVersion.value }
    );
    if (keyAtStart !== selectionKey.value) return;
    noteBaseline.value = text;
    noteVersion.value = response.data.item.lock_version;
    noteSaved.value = true;
    emit('updated', response.data.item);
  } catch (error) {
    if (keyAtStart === selectionKey.value)
      noteError.value =
        error.response?.status === 409 ? 'NOTE_CONFLICT' : 'NOTE_ERROR';
  } finally {
    if (keyAtStart === selectionKey.value) noteSaving.value = false;
  }
};
const reloadNote = async () => {
  const keyAtStart = selectionKey.value;
  try {
    const response = await ContactCenterAPI.call(
      props.accountId,
      props.nativeCallId
    );
    if (keyAtStart !== selectionKey.value) return;
    note.value =
      response.data.item.metadata?.attendance_observations?.text || '';
    noteBaseline.value = note.value;
    noteVersion.value = response.data.item.lock_version;
    noteError.value = '';
    emit('updated', response.data.item);
  } catch {
    if (keyAtStart === selectionKey.value) noteError.value = 'NOTE_ERROR';
  }
};
const open = async numberToDial => {
  emit('open');
  await nextTick();
  if (available.value && !sip.hasCall.value) {
    lastRemote.value = '';
    lastDuration.value = '';
  }
  if (
    available.value &&
    !sip.hasCall.value &&
    !otherBusy.value &&
    !props.qualificationPending &&
    numberToDial
  )
    sip.destination.value = normalizeSipDialNumber(numberToDial);
  input.value?.focus({ preventScroll: true });
};
useEmbeddedSoftphone(
  computed(() => props.accountId),
  available,
  open
);
watch(
  [() => sip.incoming.value, available],
  ([incoming, allowed]) => {
    if (incoming && allowed) emit('open');
  },
  { immediate: true }
);
defineExpose({ endCall, canEnd, duration });
</script>

<template>
  <section data-inbox-softphone class="min-w-0 space-y-5 p-4 sm:p-5">
    <div
      class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-10"
    >
      <span class="flex items-center gap-2"
        ><span
          class="size-2 rounded-full"
          :class="
            available && sip.registered.value ? 'bg-n-teal-9' : 'bg-n-slate-8'
          "
        />{{ t('SOFTPHONE.CENTRAL.EXTENSION') }}
        {{ available ? sip.credential.value?.extension || '—' : '—' }} ·
        {{
          available
            ? t(
                sip.registered.value
                  ? 'SOFTPHONE.INBOX.REGISTERED'
                  : 'SOFTPHONE.INBOX.UNREGISTERED'
              )
            : t('SOFTPHONE.INBOX.UNAVAILABLE')
        }}</span
      >
      <button
        v-if="available && sip.configured.value && !sip.hasCall.value"
        type="button"
        class="rounded-md border border-n-weak px-3 py-2 text-n-brand disabled:opacity-40"
        :disabled="pending || sip.connecting.value"
        @click="
          run(available && !sip.hasCall.value, () =>
            sip.extensionEnabled.value
              ? sip.turnOffExtension()
              : sip.turnOnExtension()
          )
        "
      >
        {{
          t(
            sip.extensionEnabled.value
              ? 'SOFTPHONE.CENTRAL.EXTENSION_OFF'
              : 'SOFTPHONE.CENTRAL.EXTENSION_ON'
          )
        }}
      </button>
    </div>
    <p
      v-if="qualificationPending"
      role="status"
      class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11"
    >
      {{ t('SOFTPHONE.INBOX.QUALIFICATION_PENDING') }}
    </p>
    <p
      v-if="actionError || (matches && sip.errorMessage.value)"
      role="alert"
      class="rounded-lg bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
    >
      {{
        (matches && sip.errorMessage.value) ||
        t('JRC_CONTACT_CENTER.COMMON.ERROR')
      }}
    </p>
    <template v-if="hasInteraction">
      <div class="flex flex-wrap items-center gap-4" data-voice-identity>
        <span
          class="grid size-16 shrink-0 place-items-center rounded-full bg-n-blue-3 text-xl font-semibold text-n-blue-11"
          >{{ initials }}</span
        >
        <div class="min-w-0 flex-1">
          <h3
            class="m-0 whitespace-normal break-words text-lg font-semibold text-n-slate-12"
          >
            {{ customerName }}
          </h3>
          <p class="my-1 text-sm text-n-slate-10">
            {{ number || t('SOFTPHONE.CENTRAL.UNAVAILABLE') }}
          </p>
          <span
            class="rounded-md bg-n-teal-3 px-2 py-1 text-xs text-n-teal-11"
            >{{ stateLabel }}</span
          >
        </div>
        <dl
          class="m-0 grid w-full grid-cols-2 gap-4 border-t border-n-weak pt-3 text-xs sm:w-auto sm:grid-cols-3 sm:border-l sm:border-t-0 sm:pl-4 sm:pt-0"
        >
          <div>
            <dt class="text-n-slate-10">{{ t('SOFTPHONE.CENTRAL.TYPE') }}</dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{
                callRecord?.provider === 'jrc_pabx'
                  ? t('SOFTPHONE.CENTRAL.PABX')
                  : t('SOFTPHONE.CENTRAL.PHONE')
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-10">{{ t('SOFTPHONE.CENTRAL.QUEUE') }}</dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{
                callRecord?.queue?.name || t('SOFTPHONE.CENTRAL.UNAVAILABLE')
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-10">{{ t('SOFTPHONE.CENTRAL.AGENT') }}</dt>
            <dd class="m-0 mt-1 text-n-slate-12">
              {{
                callRecord?.attendant?.name ||
                t('SOFTPHONE.CENTRAL.UNAVAILABLE')
              }}
            </dd>
          </div>
        </dl>
      </div>
      <div
        role="status"
        class="flex items-center gap-3 rounded-lg bg-n-blue-2 px-4 py-3 font-medium text-n-blue-11"
        data-voice-status
      >
        <span class="i-lucide-audio-lines size-6 text-n-teal-9" />{{
          stateLabel
        }}
        <span v-if="duration" class="tabular-nums">· {{ duration }}</span>
      </div>
      <div
        v-if="matches && sip.incoming.value"
        class="flex flex-wrap justify-center gap-3"
      >
        <button
          type="button"
          :disabled="!canAnswer"
          :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.ANSWER')"
          class="flex min-h-11 items-center gap-2 rounded-lg bg-n-teal-9 px-6 font-semibold text-white disabled:opacity-40"
          @click="run(canAnswer, () => sip.answer())"
        >
          <span class="i-lucide-phone size-5" />{{
            t('SOFTPHONE.CENTRAL.ANSWER')
          }}
        </button>
        <button
          type="button"
          :disabled="!canEnd"
          class="flex min-h-11 items-center gap-2 rounded-lg bg-n-ruby-9 px-6 font-semibold text-white disabled:opacity-40"
          @click="run(canEnd, () => sip.reject())"
        >
          <span class="i-lucide-phone-off size-5" />{{
            t('SOFTPHONE.CENTRAL.REJECT')
          }}
        </button>
      </div>
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-4" data-voice-controls>
        <button
          v-for="control in controls"
          :key="control.key"
          type="button"
          :data-voice-action="control.key"
          :aria-label="t(`SOFTPHONE.CENTRAL.${control.label}`)"
          :disabled="!control.enabled"
          class="flex min-h-24 flex-col items-center gap-2 rounded-lg p-2 text-xs text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-40"
          @click="run(control.enabled, control.action)"
        >
          <span
            class="grid size-14 place-items-center rounded-full bg-n-alpha-2"
            ><span class="size-6" :class="control.icon" /></span
          >{{ t(`SOFTPHONE.CENTRAL.${control.label}`) }}
        </button>
      </div>
      <form
        v-if="transferOpen && canControl"
        class="flex flex-wrap gap-3 rounded-lg border border-n-weak p-4"
        @submit.prevent="transfer"
      >
        <select
          v-model="transferMode"
          :aria-label="t('SOFTPHONE.CENTRAL.TRANSFER_MODE')"
          class="min-w-0 rounded-md border border-n-weak bg-n-solid-1 text-sm"
        >
          <option v-if="supportsTransfer('immediate')" value="immediate">
            {{ t('SOFTPHONE.CENTRAL.IMMEDIATE') }}
          </option>
          <option v-if="supportsTransfer('supervised')" value="supervised">
            {{ t('SOFTPHONE.CENTRAL.SUPERVISED') }}
          </option>
        </select>
        <input
          v-model="transferDestination"
          inputmode="numeric"
          :aria-label="t('SOFTPHONE.CENTRAL.HUMAN_EXTENSION')"
          :placeholder="t('SOFTPHONE.CENTRAL.HUMAN_EXTENSION')"
          class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-solid-1 text-sm"
        />
        <button
          type="submit"
          :disabled="
            pending ||
            !/^\d+$/.test(transferDestination) ||
            !supportsTransfer(transferMode)
          "
          class="rounded-md bg-n-brand px-4 py-2 text-sm text-white disabled:opacity-40"
        >
          {{ t('SOFTPHONE.CENTRAL.TRANSFER') }}
        </button>
      </form>
      <p v-if="transferSent" role="status" class="text-xs text-n-blue-11">
        {{ t('SOFTPHONE.INBOX.TRANSFER_SENT') }}
      </p>
    </template>
    <form
      v-if="sessionView && !sip.hasCall.value"
      class="mx-auto max-w-md space-y-4 rounded-xl border border-n-weak p-5"
      data-central-dialer
      @submit.prevent="startCall"
    >
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ t('SOFTPHONE.CENTRAL.NEW_CALL') }}
      </h3>
      <label class="block text-sm text-n-slate-11"
        >{{ t('SOFTPHONE.CENTRAL.DESTINATION')
        }}<input
          ref="input"
          v-model="dialDestination"
          type="tel"
          autocomplete="off"
          :disabled="!available || otherBusy || qualificationPending"
          class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-4 py-3 text-xl disabled:opacity-40"
      /></label>
      <div class="grid grid-cols-3 gap-2">
        <button
          v-for="tone in tones"
          :key="tone"
          type="button"
          :disabled="!available || otherBusy || qualificationPending"
          class="min-h-12 rounded-lg bg-n-alpha-2 text-lg text-n-slate-12 hover:bg-n-blue-3 disabled:opacity-40"
          @click="key(tone)"
        >
          {{ tone }}
        </button>
      </div>
      <button
        type="submit"
        :disabled="!canDial"
        class="flex min-h-12 w-full items-center justify-center gap-2 rounded-lg bg-n-teal-9 font-semibold text-white disabled:opacity-40"
      >
        <span class="i-lucide-phone size-5" />{{ t('SOFTPHONE.CENTRAL.CALL') }}
      </button>
    </form>
    <div
      v-if="keypadOpen && canControl"
      class="mx-auto grid max-w-xs grid-cols-3 gap-2"
      data-call-keypad
    >
      <button
        v-for="tone in tones"
        :key="tone"
        type="button"
        class="min-h-11 rounded-lg bg-n-alpha-2 text-lg text-n-slate-12"
        @click="key(tone)"
      >
        {{ tone }}
      </button>
    </div>
    <template v-if="hasInteraction">
      <form
        class="space-y-3 rounded-lg border border-n-weak p-4"
        data-call-observations
        @submit.prevent="saveNote"
      >
        <label
          for="call-observations"
          class="block text-sm font-semibold text-n-slate-12"
          >{{ t('SOFTPHONE.CENTRAL.NOTES') }}</label
        >
        <textarea
          id="call-observations"
          v-model="note"
          rows="3"
          maxlength="1000"
          :disabled="!allowed || !nativeCallId || noteVersion === null"
          :placeholder="t('SOFTPHONE.CENTRAL.NOTES_HINT')"
          class="w-full resize-y rounded-md border border-n-weak bg-n-solid-1 p-3 text-sm disabled:opacity-50"
        />
        <div
          class="flex flex-wrap items-center justify-between gap-2 text-xs text-n-slate-10"
        >
          <span>{{
            t('SOFTPHONE.CENTRAL.COUNT', { count: note.length, limit: 1000 })
          }}</span
          ><button
            type="submit"
            :disabled="
              !allowed ||
              !nativeCallId ||
              noteSaving ||
              noteVersion === null ||
              note === noteBaseline
            "
            class="rounded-md bg-n-brand px-3 py-2 font-semibold text-white disabled:opacity-40"
          >
            {{ t('SOFTPHONE.CENTRAL.SAVE_NOTES') }}
          </button>
        </div>
        <p v-if="!nativeCallId" class="m-0 text-xs text-n-amber-11">
          {{ t('SOFTPHONE.CENTRAL.NOTES_PENDING') }}
        </p>
        <p v-if="noteError" role="alert" class="m-0 text-xs text-n-ruby-11">
          {{ t(`SOFTPHONE.CENTRAL.${noteError}`) }}
          <button
            v-if="noteError === 'NOTE_CONFLICT'"
            type="button"
            class="underline"
            @click="reloadNote"
          >
            {{ t('SOFTPHONE.CENTRAL.RELOAD_NOTES') }}
          </button>
        </p>
        <p v-if="noteSaved" role="status" class="m-0 text-xs text-n-teal-11">
          {{ t('SOFTPHONE.CENTRAL.NOTES_SAVED') }}
        </p>
      </form>
      <section class="overflow-hidden rounded-lg border border-n-weak">
        <h3
          class="m-0 flex items-center gap-3 bg-n-blue-2 px-4 py-3 text-sm font-semibold text-n-slate-12"
        >
          <span class="i-lucide-phone size-5 text-n-brand" />{{
            t('SOFTPHONE.CENTRAL.INFORMATION')
          }}
        </h3>
        <dl class="m-0 grid grid-cols-2 gap-4 p-4 text-xs sm:grid-cols-4">
          <div v-for="[label, value] in info" :key="label">
            <dt class="text-n-slate-10">
              {{ t(`SOFTPHONE.CENTRAL.${label}`) }}
            </dt>
            <dd class="m-0 mt-1 break-words text-n-slate-12">
              {{ value || t('SOFTPHONE.CENTRAL.UNAVAILABLE') }}
            </dd>
          </div>
        </dl>
      </section>
    </template>
  </section>
</template>
