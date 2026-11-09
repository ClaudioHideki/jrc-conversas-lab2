<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useQuickActionContext } from './useQuickActionAccess';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
import { useSipWebphone } from 'dashboard/routes/dashboard/webphone/useSipWebphone';
import InboxVoicePanel from 'dashboard/routes/dashboard/inbox/InboxVoicePanel.vue';
import { clearVoiceNoteDrafts } from 'dashboard/routes/dashboard/inbox/voiceNoteDrafts';
import { useActiveVoiceContext } from 'dashboard/routes/dashboard/inbox/useActiveVoiceContext';
import { useEmbeddedSoftphone } from 'dashboard/routes/dashboard/webphone/useEmbeddedSoftphone';
import {
  writeVoiceNoteDraft,
  readVoiceNoteDraft,
} from 'dashboard/routes/dashboard/inbox/voiceNoteDrafts';
import {
  clearOutboundVoiceDrafts,
  getOutboundVoiceDraft,
  setOutboundVoiceDraft,
} from 'dashboard/routes/dashboard/inbox/outboundVoiceDrafts';
import OutboundVoiceDialog from './OutboundVoiceDialog.vue';
import { voiceShellState } from 'dashboard/routes/dashboard/webphone/voiceShell';

defineOptions({ inheritAttrs: false });
const { t } = useI18n();
const router = useRouter();
const { accountId, userId, routeAllowed, policy } = useQuickActionContext();
const sip = useSipWebphone();
const context = ref(null);
const outboundOpen = ref(false);
const initialPhone = ref('');
const allowed = computed(() => routeAllowed('ramal_index'));
const sameAccount = computed(
  () => Number(sip.accountId.value) === Number(accountId.value)
);
const active = computed(
  () => allowed.value && sameAccount.value && sip.hasCall.value
);
const lookupEnabled = computed(
  () => allowed.value && context.value?.capabilities?.operate === true
);
const identity = computed(() =>
  allowed.value &&
  sameAccount.value &&
  sip.callId.value &&
  context.value?.provider?.key
    ? {
        accountId: Number(accountId.value),
        provider: context.value.provider.key,
        sessionId: sip.callId.value,
      }
    : null
);
const attendance = useActiveVoiceContext(identity, lookupEnabled);
const statusKey = computed(() => {
  if (!active.value) return 'NO_ACTIVE_CALL';
  if (sip.incoming.value) return 'INCOMING';
  if (sip.held.value) return 'ON_HOLD';
  return sip.established.value ? 'CONNECTED' : 'DIALING';
});
let generation = 0;
let stateTimer;
watch(
  [accountId, userId, allowed],
  async () => {
    generation += 1;
    const version = generation;
    context.value = null;
    voiceShellState.value = null;
    clearTimeout(stateTimer);
    outboundOpen.value = false;
    clearVoiceNoteDrafts();
    clearOutboundVoiceDrafts();
    if (
      !allowed.value ||
      !policy.isFeatureFlagEnabled(FEATURE_FLAGS.JRC_CONTACT_CENTER)
    )
      return;
    try {
      const [result, state] = await Promise.allSettled([
        ContactCenterAPI.context(accountId.value),
        ContactCenterAPI.agentState(accountId.value),
      ]);
      if (version !== generation) return;
      if (
        result.status === 'fulfilled' &&
        Number(result.value.data.account_id) === Number(accountId.value)
      )
        context.value = result.value.data;
      const agent =
        state.status === 'fulfilled' &&
        Number(state.value.data.account_id) === Number(accountId.value)
          ? state.value.data.item
          : null;
      voiceShellState.value = {
        accountId: Number(accountId.value),
        userId: Number(userId.value),
        context: context.value,
        agent,
      };
      const refreshState = async () => {
        try {
          const response = (await ContactCenterAPI.agentState(accountId.value))
            .data;
          if (
            version === generation &&
            Number(response.account_id) === Number(accountId.value)
          )
            voiceShellState.value = {
              ...voiceShellState.value,
              agent: response.item,
            };
        } catch {
          /* Do not invent a new presence state after a failed read. */
        }
        if (version === generation)
          stateTimer = setTimeout(refreshState, 15000);
      };
      if (context.value?.capabilities?.operate)
        stateTimer = setTimeout(refreshState, 15000);
    } catch {
      /* SIP remains usable; customer and persistence context stay unavailable. */
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  clearTimeout(stateTimer);
  voiceShellState.value = null;
  clearVoiceNoteDrafts();
  clearOutboundVoiceDrafts();
});
const qualificationPending = computed(
  () =>
    voiceShellState.value?.agent?.state === 'acw' ||
    Boolean(voiceShellState.value?.agent?.pending_qualifications?.length)
);
const openOutbound = number => {
  if (
    !allowed.value ||
    !sameAccount.value ||
    sip.hasCall.value ||
    qualificationPending.value
  )
    return;
  initialPhone.value = typeof number === 'string' ? number : '';
  outboundOpen.value = true;
};
useEmbeddedSoftphone(accountId, allowed, openOutbound);
watch(attendance, value => {
  if (value?.status !== 'linked' || value.accountId !== Number(accountId.value))
    return;
  const draft = getOutboundVoiceDraft({ ...value, userId: userId.value });
  const pendingNote = readVoiceNoteDraft(
    value.accountId,
    userId.value,
    `sip:${value.sessionId}`
  );
  if (
    (!draft && !pendingNote?.text) ||
    readVoiceNoteDraft(value.accountId, userId.value, value.record.id)
  )
    return;
  const baseline = value.record.metadata?.attendance_observations?.text || '';
  const text = [
    baseline,
    draft ? `${t('VOICE_V4.REASON')}: ${draft.reason}` : '',
    draft?.notes,
    pendingNote?.text,
  ]
    .filter(Boolean)
    .join('\n');
  writeVoiceNoteDraft(value.accountId, userId.value, value.record.id, {
    text,
    baseline,
    version: value.record.lock_version,
  });
});
const openAttendance = () => {
  if (attendance.value?.status !== 'linked' || !active.value) return;
  router.push({
    name: 'inbox_view_conversation',
    params: {
      accountId: accountId.value,
      type: 'call',
      id: attendance.value.record.id,
    },
  });
};
</script>

<template>
  <section
    v-if="allowed"
    data-global-voice-bar
    :aria-label="t('VOICE_V4.BAR_LABEL')"
    class="shrink-0 border-b border-n-strong px-3 py-2 sm:px-5"
    :class="active ? 'bg-n-teal-3' : 'bg-n-solid-1'"
  >
    <div class="flex flex-wrap items-center gap-3">
      <span
        class="i-lucide-phone size-5 shrink-0 text-n-teal-10"
        aria-hidden="true"
      />
      <div class="min-w-40 flex-1 text-sm">
        <div
          class="flex flex-wrap items-center gap-2 font-semibold"
          role="status"
        >
          <span>{{ t(`VOICE_V4.${statusKey}`) }}</span>
          <span v-if="active && sip.established.value" class="tabular-nums">{{
            sip.duration.value
          }}</span>
        </div>
        <div
          v-if="active"
          class="flex flex-wrap gap-x-3 text-xs text-n-slate-11"
        >
          <span>{{
            sip.remoteNumber.value || t('SOFTPHONE.CENTRAL.UNKNOWN_CUSTOMER')
          }}</span>
          <span v-if="attendance?.record?.queue?.name">{{
            attendance.record.queue.name
          }}</span>
          <span v-if="attendance?.record?.protocol">{{
            attendance.record.protocol
          }}</span>
          <button
            v-if="attendance?.status === 'linked'"
            type="button"
            class="underline focus-visible:outline focus-visible:outline-2"
            @click="openAttendance"
          >
            {{ t('VOICE_V4.OPEN_ATTENDANCE') }}
          </button>
        </div>
        <span
          v-if="active && lookupEnabled && attendance?.status !== 'linked'"
          class="text-xs text-n-slate-11"
          >{{ t('VOICE_V4.ATTENDANCE_PENDING') }}</span
        >
      </div>
      <button
        v-if="!active"
        type="button"
        class="min-h-10 rounded-lg border border-n-strong px-4 text-xs font-semibold text-n-brand focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-40"
        :disabled="
          !sameAccount || !sip.registered.value || qualificationPending
        "
        @click="openOutbound()"
      >
        {{ t('VOICE_V4.NEW_CALL') }}
      </button>
      <InboxVoicePanel
        v-if="active"
        :account-id="Number(accountId)"
        :allowed="allowed"
        :qualification-pending="qualificationPending"
        session-view
        controls-only
        class="basis-full xl:basis-auto xl:flex-1"
      />
    </div>
    <OutboundVoiceDialog
      v-if="outboundOpen"
      :account-id="Number(accountId)"
      :user-id="Number(userId)"
      :allowed="allowed"
      :initial-phone="initialPhone"
      :can-lookup="lookupEnabled"
      :qualification-pending="qualificationPending"
      @started="setOutboundVoiceDraft"
      @close="outboundOpen = false"
    />
  </section>
</template>
