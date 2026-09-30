<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WhatsappCallsAPI from 'dashboard/api/channel/whatsapp/whatsappCallsAPI';
import WhatsappCallingConfigurationAPI from 'dashboard/api/whatsappCallingConfiguration';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import { useCallActions } from 'dashboard/composables/useCallSession';
import { useCallsStore } from 'dashboard/stores/calls';
import {
  getVoiceCallProvider,
  VOICE_CALL_PROVIDERS,
} from 'dashboard/helper/inbox';
import {
  VOICE_CALL_DIRECTION,
  VOICE_CALL_OUTBOUND_INIT_STATUS,
} from 'dashboard/components-next/message/constants';

const props = defineProps({
  contact: {
    type: Object,
    default: () => ({}),
  },
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');
const callsStore = useCallsStore();
const whatsappCallSession = useWhatsappCallSession();
const callActions = useCallActions();

const KEYPAD_KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

const showKeypad = ref(false);
const manualNumber = ref('');
const suggestedNumber = ref('');
const hasManualOverride = ref(false);
const selectedInboxId = ref(null);
const configuration = ref({
  enabled: false,
  status: 'not_configured',
  active: false,
});
const permission = ref({
  status: 'idle',
  can_start_call: false,
  can_request_permission: false,
  target_key: null,
});
const permissionLoading = ref(false);
const callState = ref('idle');
const isEndingCall = ref(false);
const appliedConversationId = ref(null);
let hadWhatsappCall = false;

const contactPhone = computed(
  () => props.contact?.phone_number || props.contact?.phoneNumber || ''
);

const destination = computed({
  get: () =>
    hasManualOverride.value ? manualNumber.value : suggestedNumber.value,
  set: value => {
    manualNumber.value = String(value || '');
    hasManualOverride.value = true;
  },
});

const normalizeE164 = value => {
  const digits = String(value || '').replace(/\D/g, '');
  return digits ? `+${digits}` : '';
};

const normalizedDestination = computed(() => normalizeE164(destination.value));
const strippedDestination = computed(() =>
  String(destination.value || '')
    .trim()
    .replace(/[\s().-]/g, '')
);
const normalizedContactPhone = computed(() => normalizeE164(contactPhone.value));
const hasValidDestination = computed(() =>
  /^\+?[1-9]\d{7,14}$/.test(strippedDestination.value)
);

const whatsappVoiceInboxes = computed(() =>
  (inboxes.value || []).filter(
    inbox => getVoiceCallProvider(inbox) === VOICE_CALL_PROVIDERS.WHATSAPP
  )
);
const hasWhatsappInbox = computed(() => whatsappVoiceInboxes.value.length > 0);

const permissionTargetKey = computed(
  () => `${selectedInboxId.value || ''}:${normalizedDestination.value}`
);

const activeWhatsappCall = computed(() => {
  const activeCall = callsStore.activeCall;
  return activeCall?.provider === VOICE_CALL_PROVIDERS.WHATSAPP
    ? activeCall
    : null;
});

const incomingWhatsappCall = computed(
  () =>
    callsStore.incomingCalls.find(
      call =>
        call.provider === VOICE_CALL_PROVIDERS.WHATSAPP &&
        call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND
    ) || null
);

const currentWhatsappCall = computed(
  () =>
    activeWhatsappCall.value ||
    callsStore.incomingCalls.find(
      call => call.provider === VOICE_CALL_PROVIDERS.WHATSAPP
    ) ||
    null
);

const isBusy = computed(
  () =>
    callsStore.hasActiveCall ||
    callsStore.hasIncomingCall ||
    whatsappCallSession.isInitiating.value
);

const permissionMatchesDestination = computed(
  () => permission.value.target_key === permissionTargetKey.value
);

const canCall = computed(
  () =>
    configuration.value.active &&
    hasWhatsappInbox.value &&
    hasValidDestination.value &&
    selectedInboxId.value &&
    permissionMatchesDestination.value &&
    permission.value.status === 'approved' &&
    permission.value.can_start_call &&
    !isBusy.value
);

const canCheckPermission = computed(
  () =>
    configuration.value.active &&
    hasWhatsappInbox.value &&
    hasValidDestination.value &&
    selectedInboxId.value &&
    !permissionLoading.value &&
    !isBusy.value
);

const canRequestPermission = computed(
  () =>
    canCheckPermission.value &&
    permissionMatchesDestination.value &&
    permission.value.can_request_permission
);

const canAnswerCall = computed(
  () =>
    !!incomingWhatsappCall.value &&
    !callsStore.hasActiveCall &&
    !isEndingCall.value &&
    !callActions.isJoining.value
);

const canEndCall = computed(
  () => !!currentWhatsappCall.value && !isEndingCall.value
);

const formattedCallDuration = callActions.formattedCallDuration;

const statusLabel = computed(() => {
  if (activeWhatsappCall.value)
    return t('WHATSAPP_CALLING.CALL_STATE.IN_PROGRESS');
  if (incomingWhatsappCall.value)
    return t('WHATSAPP_CALLING.CALL_STATE.INCOMING');
  if (callState.value === 'calling' || whatsappCallSession.isInitiating.value)
    return t('WHATSAPP_CALLING.CALL_STATE.CALLING');
  if (!configuration.value.active || !hasWhatsappInbox.value)
    return t('WHATSAPP_CALLING.INACTIVE');
  return t('WHATSAPP_CALLING.SIDEBAR.AVAILABLE');
});

const helperMessage = computed(() => {
  if (!configuration.value.active)
    return t('WHATSAPP_CALLING.SIDEBAR.NOT_CONFIGURED');
  if (!hasWhatsappInbox.value) return t('WHATSAPP_CALLING.HELP.NO_INBOX');
  if (!destination.value) return t('WHATSAPP_CALLING.SIDEBAR.ENTER_NUMBER');
  if (!hasValidDestination.value)
    return t('WHATSAPP_CALLING.HELP.INVALID_NUMBER');
  if (permissionLoading.value)
    return t('WHATSAPP_CALLING.SIDEBAR.CHECKING_PERMISSION');

  const messages = {
    idle: t('WHATSAPP_CALLING.PERMISSION.CHECK_REQUIRED'),
    approved: t('WHATSAPP_CALLING.PERMISSION.APPROVED'),
    permission_required: t('WHATSAPP_CALLING.PERMISSION.REQUIRED'),
    permission_requested: t('WHATSAPP_CALLING.PERMISSION.REQUESTED'),
    permission_pending: t('WHATSAPP_CALLING.PERMISSION.PENDING'),
    permission_denied: t('WHATSAPP_CALLING.PERMISSION.DENIED'),
    permission_expired: t('WHATSAPP_CALLING.PERMISSION.EXPIRED'),
    permission_unavailable: t('WHATSAPP_CALLING.PERMISSION.UNAVAILABLE'),
    credential_invalid: t('WHATSAPP_CALLING.PERMISSION.CREDENTIAL_INVALID'),
  };
  return messages[permission.value.status] || t('WHATSAPP_CALLING.HELP.READY');
});

const callTarget = computed(() => {
  const usesCurrentContact =
    props.contact?.id &&
    normalizedContactPhone.value &&
    normalizedContactPhone.value === normalizedDestination.value;

  if (usesCurrentContact) {
    return {
      contactId: props.contact.id,
      inboxId: selectedInboxId.value,
    };
  }

  return {
    phoneNumber: normalizedDestination.value,
    inboxId: selectedInboxId.value,
  };
});

const resetPermission = () => {
  permission.value = {
    status: 'idle',
    can_start_call: false,
    can_request_permission: false,
    target_key: null,
  };
};

const applyPermission = response => {
  permission.value = {
    status: response?.status || 'permission_unavailable',
    can_start_call: Boolean(response?.can_start_call),
    can_request_permission: Boolean(response?.can_request_permission),
    target_key: permissionTargetKey.value,
  };
};

const functionalResponse = error => error?.response?.data;

const checkPermission = async ({ silent = false } = {}) => {
  if (!canCheckPermission.value) return;
  permissionLoading.value = true;
  try {
    applyPermission(await WhatsappCallsAPI.permission(callTarget.value));
  } catch (error) {
    const response = functionalResponse(error);
    applyPermission(response);
    if (!silent) {
      useAlert(
        response?.error || t('WHATSAPP_CALLING.PERMISSION.UNAVAILABLE')
      );
    }
  } finally {
    permissionLoading.value = false;
  }
};

const autoCheckSuggestedContact = () => {
  if (
    hasManualOverride.value ||
    !props.contact?.id ||
    !hasValidDestination.value ||
    !configuration.value.active ||
    !selectedInboxId.value ||
    permissionLoading.value ||
    isBusy.value
  ) {
    return;
  }
  checkPermission({ silent: true });
};

const requestPermission = async () => {
  if (!canRequestPermission.value) return;
  permissionLoading.value = true;
  try {
    const response = await WhatsappCallsAPI.requestPermission(callTarget.value);
    applyPermission(response);
    useAlert(t('WHATSAPP_CALLING.ALERT.PERMISSION_REQUESTED'));
  } catch (error) {
    const response = functionalResponse(error);
    applyPermission(response);
    useAlert(
      response?.error || t('WHATSAPP_CALLING.ALERT.PERMISSION_REQUEST_FAILED')
    );
  } finally {
    permissionLoading.value = false;
  }
};

const startCall = async () => {
  if (!canCall.value) return;
  callState.value = 'calling';

  try {
    const response = await whatsappCallSession.initiateOutboundCall(
      callTarget.value
    );
    if (response?.status === VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED) {
      callState.value = 'idle';
      return;
    }
    if (!response?.id) {
      callState.value = 'idle';
      applyPermission(response);
      useAlert(helperMessage.value);
      return;
    }

    callsStore.addCall({
      callSid: response.call_id,
      callId: response.id,
      conversationId: response.conversation_id,
      inboxId: selectedInboxId.value,
      callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
      provider: VOICE_CALL_PROVIDERS.WHATSAPP,
    });
  } catch (error) {
    callState.value = 'failed';
    useAlert(
      functionalResponse(error)?.error ||
        t('WHATSAPP_CALLING.ALERT.CALL_FAILED')
    );
  }
};

const answerIncomingCall = async () => {
  const call = incomingWhatsappCall.value;
  if (!call || !canAnswerCall.value) return;

  const response = await callActions.joinCall({
    conversationId: call.conversationId,
    inboxId: call.inboxId,
    callSid: call.callSid,
  });
  if (response) callState.value = 'active';
};

const endCall = async () => {
  const call = currentWhatsappCall.value;
  if (!call || isEndingCall.value) return;
  isEndingCall.value = true;

  try {
    const isRingingInbound =
      !call.isActive && call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND;
    if (isRingingInbound) {
      await whatsappCallSession.rejectIncomingCall(call.callId);
    } else {
      await whatsappCallSession.endActiveCall(call.callId);
    }
    callsStore.dismissCall(call.callSid);
    callState.value = 'ended';
  } catch (error) {
    useAlert(
      functionalResponse(error)?.error || t('WHATSAPP_CALLING.ALERT.END_FAILED')
    );
  } finally {
    isEndingCall.value = false;
  }
};

const pressKey = key => {
  if (isBusy.value) return;
  destination.value = `${destination.value}${key}`;
};

const addPlus = () => {
  if (isBusy.value) return;
  const current = String(destination.value || '');
  destination.value = current.startsWith('+') ? current : `+${current}`;
};

const eraseLastDigit = () => {
  if (isBusy.value) return;
  destination.value = String(destination.value || '').slice(0, -1);
};

const clearNumber = () => {
  if (isBusy.value) return;
  destination.value = '';
};

const syncConversationContext = () => {
  if (isBusy.value) return;
  manualNumber.value = '';
  suggestedNumber.value = contactPhone.value || '';
  hasManualOverride.value = false;
  appliedConversationId.value = String(props.conversationId || '');
  resetPermission();
  autoCheckSuggestedContact();
};

const loadConfiguration = async () => {
  try {
    configuration.value = await WhatsappCallingConfigurationAPI.get();
  } catch {
    configuration.value = {
      enabled: false,
      status: 'error',
      active: false,
    };
  }
};

watch(
  whatsappVoiceInboxes,
  list => {
    if (!list.some(inbox => Number(inbox.id) === Number(selectedInboxId.value))) {
      selectedInboxId.value = list[0]?.id || null;
    }
  },
  { immediate: true }
);

watch(
  () => props.conversationId,
  () => syncConversationContext(),
  { immediate: true }
);

watch(
  () => props.contact?.id,
  () => {
    if (!isBusy.value) syncConversationContext();
  }
);

watch(contactPhone, phone => {
  if (!hasManualOverride.value && !isBusy.value) {
    suggestedNumber.value = phone || '';
    resetPermission();
    autoCheckSuggestedContact();
  }
});

watch([normalizedDestination, selectedInboxId], () => {
  resetPermission();
  if (!hasManualOverride.value) autoCheckSuggestedContact();
});

watch(
  () => configuration.value.active,
  active => {
    if (active) autoCheckSuggestedContact();
  }
);

watch(isBusy, busy => {
  if (
    !busy &&
    appliedConversationId.value !== String(props.conversationId || '')
  ) {
    syncConversationContext();
  }
});

watch(
  () =>
    callsStore.calls
      .filter(call => call.provider === VOICE_CALL_PROVIDERS.WHATSAPP)
      .map(call => `${call.callSid}:${call.isActive}`),
  calls => {
    const hasCall = calls.length > 0;
    if (hasCall) hadWhatsappCall = true;
    if (!hasCall && hadWhatsappCall) {
      callState.value = 'ended';
      hadWhatsappCall = false;
    }
  }
);

onMounted(async () => {
  await loadConfiguration();
  autoCheckSuggestedContact();
});
</script>

<template>
  <section class="mx-3 mb-3 overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-sm">
    <div class="flex items-center justify-between bg-emerald-500 px-4 py-2.5 text-white">
      <div class="flex items-center gap-2 text-sm font-semibold">
        <span class="i-ri-whatsapp-fill size-5" />
        <span>{{ $t('WHATSAPP_CALLING.SIDEBAR.TITLE') }}</span>
      </div>
      <span class="rounded-full bg-emerald-700/40 px-2.5 py-1 text-[11px] font-medium">
        {{ statusLabel }}
      </span>
    </div>

    <div class="p-3">
      <div class="mb-2 flex items-center justify-between gap-3">
        <div class="min-w-0">
          <p class="truncate text-xs font-medium text-n-slate-12">
            {{ contact?.name || $t('WHATSAPP_CALLING.SIDEBAR.GENERAL_DIALER') }}
          </p>
          <p class="mt-0.5 text-[11px] text-n-slate-9">
            {{ $t('WHATSAPP_CALLING.SIDEBAR.NUMBER_HELP') }}
          </p>
        </div>
        <strong v-if="activeWhatsappCall" class="shrink-0 text-sm text-n-slate-12">
          {{ formattedCallDuration }}
        </strong>
      </div>

      <div class="grid gap-2" :class="whatsappVoiceInboxes.length > 1 ? 'grid-cols-[1fr_112px]' : 'grid-cols-1'">
        <input
          v-model="destination"
          type="tel"
          inputmode="tel"
          autocomplete="tel"
          :disabled="isBusy"
          :placeholder="$t('WHATSAPP_CALLING.PHONE_PLACEHOLDER')"
          class="h-9 min-w-0 rounded-lg border border-n-weak bg-n-background px-3 text-sm font-medium text-n-slate-12 outline-none focus:border-emerald-500 disabled:cursor-not-allowed disabled:opacity-60"
        />
        <select
          v-if="whatsappVoiceInboxes.length > 1"
          v-model="selectedInboxId"
          :disabled="isBusy"
          :aria-label="$t('WHATSAPP_CALLING.INBOX_LABEL')"
          class="h-9 min-w-0 rounded-lg border border-n-weak bg-n-background px-2 text-[11px] text-n-slate-11 outline-none focus:border-emerald-500 disabled:opacity-60"
        >
          <option
            v-for="inbox in whatsappVoiceInboxes"
            :key="inbox.id"
            :value="inbox.id"
          >
            {{ inbox.name }}
          </option>
        </select>
      </div>

      <div class="mt-3 grid grid-cols-2 gap-2">
        <button
          v-if="!incomingWhatsappCall && !activeWhatsappCall"
          type="button"
          class="flex min-h-[50px] w-full items-center justify-center gap-2 rounded-xl border border-n-teal-10 bg-n-teal-9 px-3 py-3 text-sm font-bold text-white shadow-sm hover:enabled:bg-n-teal-10 disabled:cursor-not-allowed disabled:opacity-45"
          :disabled="!canCall"
          @click="startCall"
        >
          <span class="i-lucide-phone-outgoing size-4" />
          <span>{{ $t('WHATSAPP_CALLING.CONTROLS.CALL') }}</span>
        </button>
        <button
          v-else-if="incomingWhatsappCall && !activeWhatsappCall"
          type="button"
          class="flex min-h-[50px] w-full items-center justify-center gap-2 rounded-xl bg-n-brand px-3 py-3 text-sm font-bold text-white shadow-sm hover:enabled:brightness-110 disabled:cursor-not-allowed disabled:opacity-45"
          :disabled="!canAnswerCall"
          @click="answerIncomingCall"
        >
          <span class="i-lucide-phone-call size-4" />
          <span>{{ $t('WHATSAPP_CALLING.SIDEBAR.ANSWER') }}</span>
        </button>
        <button
          type="button"
          class="flex min-h-[50px] w-full items-center justify-center gap-2 rounded-xl border border-n-amber-10 bg-n-amber-9 px-3 py-3 text-sm font-bold text-n-on-amber shadow-sm hover:enabled:bg-n-amber-10 disabled:cursor-not-allowed disabled:opacity-100"
          :disabled="isBusy && !showKeypad"
          @click="showKeypad = !showKeypad"
        >
          <span class="i-lucide-grid-3x3 size-4" />
          <span>
            {{
              showKeypad
                ? $t('WHATSAPP_CALLING.SIDEBAR.HIDE_KEYPAD')
                : $t('WHATSAPP_CALLING.SIDEBAR.KEYPAD')
            }}
          </span>
        </button>
      </div>

      <div
        class="mt-2 rounded-lg px-3 py-2 text-[11px]"
        :class="canCall ? 'bg-emerald-500/10 text-emerald-700' : 'bg-n-alpha-2 text-n-slate-10'"
      >
        {{ helperMessage }}
      </div>

      <div
        v-if="showKeypad"
        class="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3"
      >
        <div class="grid grid-cols-3 gap-2">
          <button
            v-for="key in KEYPAD_KEYS"
            :key="key"
            type="button"
            class="rounded-lg border border-amber-100 bg-white py-2 text-sm font-bold text-n-slate-12 shadow-sm hover:bg-amber-100 disabled:opacity-40"
            :disabled="isBusy"
            @click="pressKey(key)"
          >
            {{ key }}
          </button>
        </div>
        <div class="mt-2 grid grid-cols-3 gap-2">
          <button
            type="button"
            class="rounded-lg border border-amber-200 bg-white py-2 text-sm font-bold text-n-slate-12 hover:bg-amber-100 disabled:opacity-40"
            :disabled="isBusy"
            @click="addPlus"
          >
            +
          </button>
          <button
            type="button"
            class="rounded-lg border border-amber-200 bg-white py-2 text-n-slate-12 hover:bg-amber-100 disabled:opacity-40"
            :disabled="isBusy || !destination"
            :title="$t('WHATSAPP_CALLING.SIDEBAR.BACKSPACE')"
            @click="eraseLastDigit"
          >
            <span class="i-lucide-delete mx-auto block size-4" />
          </button>
          <button
            type="button"
            class="rounded-lg border border-amber-200 bg-white py-2 text-[11px] font-semibold text-n-slate-11 hover:bg-amber-100 disabled:opacity-40"
            :disabled="isBusy || !destination"
            @click="clearNumber"
          >
            {{ $t('WHATSAPP_CALLING.SIDEBAR.CLEAR') }}
          </button>
        </div>
      </div>

      <div
        v-if="hasValidDestination && configuration.active && hasWhatsappInbox"
        class="mt-2 flex flex-wrap items-center gap-2"
      >
        <button
          v-if="permission.status !== 'approved'"
          type="button"
          class="rounded-lg border border-n-weak bg-n-background px-3 py-1.5 text-[11px] font-semibold text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-40"
          :disabled="!canCheckPermission"
          @click="checkPermission()"
        >
          {{ $t('WHATSAPP_CALLING.PERMISSION.CHECK_ACTION') }}
        </button>
        <button
          v-if="canRequestPermission"
          type="button"
          class="rounded-lg bg-emerald-500 px-3 py-1.5 text-[11px] font-semibold text-white hover:bg-emerald-600 disabled:opacity-40"
          :disabled="permissionLoading"
          @click="requestPermission"
        >
          {{ $t('WHATSAPP_CALLING.PERMISSION.REQUEST_ACTION') }}
        </button>
      </div>

      <button
        v-if="currentWhatsappCall"
        type="button"
        class="mt-3 w-full rounded-xl bg-n-ruby-9 px-4 py-3 text-xs font-bold text-white shadow-sm hover:enabled:bg-n-ruby-10 disabled:cursor-not-allowed disabled:opacity-45"
        :disabled="!canEndCall"
        @click="endCall"
      >
        <span class="i-lucide-phone-off me-1 inline-block size-4 align-text-bottom" />
        {{ $t('WHATSAPP_CALLING.CONTROLS.END') }}
      </button>
    </div>
  </section>
</template>
