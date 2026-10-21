<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  inbox360Labels,
  callStateLabels,
  conversationStateLabels,
} from './inboxPresentation';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  getInboxChannelKey,
  INBOX_CHANNEL_PRESENTATION,
} from 'dashboard/helper/inbox';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
import { useSipWebphone } from 'dashboard/routes/dashboard/webphone/useSipWebphone';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MoreActions from 'dashboard/components/widgets/conversation/MoreActions.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import CallWorkspace from 'dashboard/routes/dashboard/jrcContactCenter/views/CallWorkspace.vue';
import AgentStatePanel from 'dashboard/routes/dashboard/jrcContactCenter/views/AgentStatePanel.vue';
import InboxChannelGroups from './InboxChannelGroups.vue';
import InboxCustomerPanel from './InboxCustomerPanel.vue';
import InboxContextContent from './InboxContextContent.vue';
import InboxQuickActions from './InboxQuickActions.vue';
import {
  agentStateLabels,
  pauseReasonLabels,
} from 'dashboard/routes/dashboard/jrcContactCenter/agentStateLabels';
import { useInboxCustomer360 } from './useInboxCustomer360';
import { useAttendanceClosing } from './useAttendanceClosing';
import QualificationHistory from './QualificationHistory.vue';

const props = defineProps({
  accountId: { type: Number, required: true },
  calls: { type: Array, default: () => [] },
  conversations: { type: Array, default: () => [] },
  channels: { type: Array, default: () => [] },
  assignees: { type: Array, default: () => [] },
  assigneeFilter: { type: String, default: 'me' },
  channelFilter: { type: String, default: 'all' },
  currentCallId: { type: Number, default: null },
  currentConversationId: { type: Number, default: null },
  inboxFor: { type: Function, required: true },
  context: { type: Object, default: null },
  loading: { type: Boolean, default: false },
  voiceError: { type: Boolean, default: false },
  canLoadMore: { type: Boolean, default: false },
  ready: { type: Boolean, default: true },
});
const emit = defineEmits([
  'selectCall',
  'selectConversation',
  'channelChange',
  'assigneeChange',
  'loadMore',
  'refresh',
]);
const { t } = useI18n();
const store = useStore();
const labels = computed(() => inbox360Labels(t));
const agentLabels = computed(() => agentStateLabels(t));
const pauseLabels = computed(() => pauseReasonLabels(t));
const selectedChat = useMapGetter('getSelectedChat');
const featureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
const sip = useSipWebphone();
const tab = ref('CONVERSATION');
const voiceSection = ref('journey');
const listOpen = ref(false);
const callDetails = ref(null);
const agent = ref(null);
const actionError = ref(false);
const qualification = ref('');
const scriptReply = ref('');
const pauseDialog = ref(null);
const customerDialog = ref(null);
const detailsDialog = ref(null);
const quickActions = ref(null);
const callWorkspace = ref(null);
const now = ref(Date.now());
const clock = setInterval(() => {
  now.value = Date.now();
}, 1000);
let agentGeneration = 0;
let actionGeneration = 0;
const canOperate = computed(
  () => props.context?.capabilities?.operate === true
);
const isVoice = computed(() => Boolean(props.currentCallId));
const hasSelection = computed(() =>
  Boolean(props.currentCallId || props.currentConversationId)
);
const conversation = computed(
  () =>
    props.conversations.find(item => item.id === props.currentConversationId) ||
    (selectedChat.value?.id === props.currentConversationId
      ? selectedChat.value
      : null)
);
const nativeConversationReady = computed(() =>
  Boolean(
    props.currentConversationId &&
      selectedChat.value?.id === props.currentConversationId
  )
);
const call = computed(() => callDetails.value?.call);
const identity = computed(() => ({
  accountId: props.accountId,
  callId: props.currentCallId,
  conversationId: props.currentConversationId,
  contactId: isVoice.value
    ? call.value?.contact_id ||
      (!callDetails.value?.customer?.ambiguous &&
      callDetails.value?.customer?.contacts?.length === 1
        ? callDetails.value.customer.contacts[0].id
        : null)
    : conversation.value?.meta?.sender?.id,
}));
const features = computed(() => ({
  crm: featureEnabled.value(props.accountId, FEATURE_FLAGS.JRC_CRM) === true,
  master:
    featureEnabled.value(props.accountId, FEATURE_FLAGS.JRC_CUSTOMER_MASTER) ===
    true,
}));
const {
  contact,
  company,
  addresses,
  crm,
  cases,
  loading: customerLoading,
  failed: customerFailed,
  unavailable,
} = useInboxCustomer360(identity, features);
const whatsappTarget = computed(() => {
  const item = props.conversations.find(
    conversationItem =>
      conversationItem.meta?.sender?.id === identity.value.contactId &&
      getInboxChannelKey(props.inboxFor(conversationItem)) === 'whatsapp'
  );
  return item
    ? {
        name: 'inbox_view_conversation',
        params: {
          accountId: props.accountId,
          type: 'conversation',
          id: item.id,
        },
        query: { assignee: props.assigneeFilter },
      }
    : null;
});
const customerProps = computed(() => ({
  accountId: props.accountId,
  contact: contact.value,
  company: company.value,
  addresses: addresses.value,
  crm: crm.value,
  cases: cases.value,
  loading: customerLoading.value,
  failed: customerFailed.value,
  unavailable: unavailable.value,
  crmEnabled: features.value.crm,
  interaction: isVoice.value
    ? { callSessionId: props.currentCallId }
    : { conversationId: props.currentConversationId },
  whatsappTarget: whatsappTarget.value,
}));
const categories = computed(() => [
  ...new Set(cases.value.map(item => item.category).filter(Boolean)),
]);
const channelKey = computed(() =>
  isVoice.value
    ? 'voice'
    : getInboxChannelKey(props.inboxFor(conversation.value || {}))
);
const isWhatsApp = computed(() => channelKey.value === 'whatsapp');
const requiresWhatsAppClosing = computed(() => {
  const inbox = props.inboxFor(conversation.value || {});
  const type = inbox.channel_type || inbox.channelType;
  return (
    type === 'Channel::Whatsapp' ||
    (type === 'Channel::TwilioSms' && inbox.medium === 'whatsapp')
  );
});
const supportsClosing = computed(
  () => isVoice.value || requiresWhatsAppClosing.value
);
const workspaceTabs = computed(() => [
  'CONVERSATION',
  'SCRIPT',
  'CUSTOMER_DATA',
  'ORDERS',
  'CASES',
  'HISTORY',
  'TASKS',
  ...(supportsClosing.value ? ['CLOSING'] : []),
]);
const channel = computed(() =>
  isVoice.value
    ? props.channels.find(item => item.key === 'voice')
    : INBOX_CHANNEL_PRESENTATION[channelKey.value]
);
const customerName = computed(
  () =>
    company.value?.trade_name ||
    company.value?.name ||
    contact.value?.name ||
    conversation.value?.meta?.sender?.name ||
    ''
);
const title = computed(() =>
  isVoice.value
    ? call.value?.ani ||
      call.value?.dnis ||
      props.calls.find(item => item.id === props.currentCallId)?.ani ||
      `#${props.currentCallId}`
    : customerName.value || `#${props.currentConversationId}`
);
const callLabels = computed(() => callStateLabels(t));
const conversationLabels = computed(() => conversationStateLabels(t));
const statusLabel = computed(() =>
  isVoice.value
    ? callLabels.value[
        call.value?.status ||
          props.calls.find(item => item.id === props.currentCallId)?.status
      ]
    : conversationLabels.value[conversation.value?.status]
);
const duration = computed(() => {
  const start = call.value?.answered_at || call.value?.started_at;
  const end = call.value?.ended_at
    ? new Date(call.value.ended_at).getTime()
    : now.value;
  const seconds = start
    ? Math.max(0, Math.floor((end - new Date(start).getTime()) / 1000))
    : 0;
  return [
    Math.floor(seconds / 3600),
    Math.floor(seconds / 60) % 60,
    seconds % 60,
  ]
    .map(value => String(value).padStart(2, '0'))
    .join(':');
});
// Never operate the singleton webphone for a different call or account.
const matchingSip = computed(
  () =>
    canOperate.value &&
    props.context?.provider?.capabilities?.sip_webrtc === 'available' &&
    Number(sip.accountId.value) === props.accountId &&
    Boolean(call.value?.external_session_id) &&
    call.value.external_session_id === sip.callId.value
);
const phoneError = computed(() =>
  matchingSip.value ? sip.errorMessage.value : ''
);
const voiceActions = computed(() => [
  {
    key: 'ANSWER',
    icon: 'i-lucide-phone',
    enabled: matchingSip.value && sip.incoming.value,
    action: () => sip.answer(),
  },
  {
    key: 'HANGUP',
    icon: 'i-lucide-phone-off',
    enabled: matchingSip.value && sip.hasCall.value,
    action: () => sip.hangup(),
    danger: true,
  },
  {
    key: 'MUTE',
    icon: sip.muted.value ? 'i-lucide-mic-off' : 'i-lucide-mic',
    enabled: matchingSip.value && sip.established.value,
    action: () => sip.setMuted(!sip.muted.value),
  },
  {
    key: 'HOLD',
    icon: 'i-lucide-pause-circle',
    enabled:
      matchingSip.value &&
      sip.established.value &&
      !sip.holdPending.value &&
      props.context?.provider?.capabilities?.hold === 'available',
    action: () => sip.setHold(!sip.held.value),
  },
  {
    key: 'TRANSFER',
    icon: 'i-lucide-phone-forwarded',
    enabled:
      canOperate.value &&
      ['transfer_blind', 'transfer_attended'].some(
        key => props.context?.provider?.capabilities?.[key] === 'available'
      ) &&
      call.value &&
      !['ended', 'failed'].includes(call.value.status),
    action: () => {
      tab.value = 'CONVERSATION';
      voiceSection.value = 'transfer';
    },
  },
]);
const runAction = async action => {
  if (!action.enabled) return;
  const version = actionGeneration;
  const key = [
    props.accountId,
    props.currentCallId,
    props.currentConversationId,
  ].join(':');
  actionError.value = false;
  try {
    await action.action();
  } catch {
    if (
      version === actionGeneration &&
      key ===
        [
          props.accountId,
          props.currentCallId,
          props.currentConversationId,
        ].join(':')
    )
      actionError.value = true;
  }
};
const closing = useAttendanceClosing({
  props,
  supportsClosing,
  isVoice,
  now,
  showClosing: () => {
    tab.value = 'CLOSING';
  },
  restoreSelection: record => {
    if (
      record.call_session_id &&
      Number(record.call_session_id) !== props.currentCallId
    )
      emit('selectCall', { id: Number(record.call_session_id) });
    if (
      record.conversation_display_id &&
      Number(record.conversation_display_id) !== props.currentConversationId
    )
      emit('selectConversation', {
        id: Number(record.conversation_display_id),
      });
  },
});
const {
  reason: closingReason,
  result: closingResult,
  note: closingNote,
  pending: closingPending,
  records: closingRecords,
  error: closingError,
  saving: closingSaving,
  blocked: closingBlocked,
  overdue: acwOverdue,
  limit: acwLimitSeconds,
  elapsed: acwElapsedSeconds,
} = closing;
const displayAgent = computed(() => closing.agent.value || agent.value);
const pausedElapsed = computed(() => {
  const seconds =
    Math.max(
      0,
      Math.floor(
        (now.value - new Date(displayAgent.value?.started_at).getTime()) / 1000
      )
    ) || 0;
  return [
    Math.floor(seconds / 3600),
    Math.floor(seconds / 60) % 60,
    seconds % 60,
  ]
    .map(value => String(value).padStart(2, '0'))
    .join(':');
});

const formatSeconds = seconds =>
  [Math.floor(seconds / 60), seconds % 60]
    .map(value => String(value).padStart(2, '0'))
    .join(':');
watch(closing.attendance, value => {
  if (
    isVoice.value &&
    value?.id === props.currentCallId &&
    callDetails.value?.call
  ) {
    callDetails.value = {
      ...callDetails.value,
      call: { ...callDetails.value.call, ...value },
    };
  }
});
const startClosing = async () => {
  if (!supportsClosing.value) return;
  if (isVoice.value) {
    const hangup = voiceActions.value.find(action => action.key === 'HANGUP');
    if (!hangup?.enabled) {
      actionError.value = true;
      return;
    }
    const account = props.accountId;
    const attendance = props.currentCallId;
    const version = actionGeneration;
    await runAction(hangup);
    if (
      version === actionGeneration &&
      account === props.accountId &&
      attendance === props.currentCallId
    ) {
      if (phoneError.value) actionError.value = true;
      if (!actionError.value) await closing.load();
    }
    return;
  }
  await closing.start();
};
const finishClosing = async () => {
  const key = [
    props.accountId,
    props.currentCallId,
    props.currentConversationId,
  ].join(':');
  const persisted = await closing.complete();
  if (
    !persisted ||
    key !==
      [props.accountId, props.currentCallId, props.currentConversationId].join(
        ':'
      )
  )
    return;
  if (isWhatsApp.value) {
    store.commit('CHANGE_CONVERSATION_STATUS', {
      conversationId: props.currentConversationId,
      status: 'resolved',
      snoozedUntil: null,
    });
  }
  tab.value = 'CLOSING';
  emit('refresh');
};
watch([() => call.value?.status, () => sip.hasCall.value], () => {
  if (isVoice.value) closing.load();
});
const openQuick = kind => quickActions.value.open(kind);
const insertReply = content => {
  if (isVoice.value) {
    scriptReply.value = content;
    tab.value = 'SCRIPT';
    return;
  }
  if (nativeConversationReady.value)
    emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, content);
};
const qualify = async value => {
  qualification.value = value;
  if (isVoice.value) {
    tab.value = 'CASES';
    voiceSection.value = 'case';
    const version = actionGeneration;
    await nextTick();
    if (version === actionGeneration) callWorkspace.value?.setCategory(value);
  }
};
const showTab = value => {
  tab.value = value;
  customerDialog.value?.close();
};
const selectCall = value => {
  if (!closing.allowSelection('voice', value.id)) return;
  listOpen.value = false;
  emit('selectCall', value);
};
const selectConversation = value => {
  if (!closing.allowSelection('whatsapp', value.id)) return;
  listOpen.value = false;
  emit('selectConversation', value);
};
const loaded = value => {
  if (value?.call?.id !== props.currentCallId) return;
  if (closing.attendance.value?.id === value.call.id) {
    value = { ...value, call: { ...value.call, ...closing.attendance.value } };
  }
  callDetails.value = value;
  if (value?.agent) agent.value = value.agent;
};

watch(
  () => [props.accountId, props.currentCallId, props.currentConversationId],
  () => {
    actionGeneration += 1;
    tab.value = 'CONVERSATION';
    voiceSection.value = 'journey';
    callDetails.value = null;
    qualification.value = '';
    scriptReply.value = '';
    actionError.value = false;
    pauseDialog.value?.close();
    customerDialog.value?.close();
    detailsDialog.value?.close();
  }
);
watch(
  () => props.accountId,
  async () => {
    agentGeneration += 1;
    const version = agentGeneration;
    agent.value = null;
    try {
      const response = await ContactCenterAPI.agentState(props.accountId);
      if (version === agentGeneration) agent.value = response.data.item;
    } catch {
      if (version === agentGeneration) agent.value = null;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  actionGeneration += 1;
  agentGeneration += 1;
  clearInterval(clock);
});
</script>

<template>
  <section
    class="relative flex h-full min-h-0 w-full min-w-0 flex-col overflow-hidden bg-n-background"
    data-testid="hoya-inbox-workspace"
  >
    <header
      class="flex min-h-14 shrink-0 items-center gap-2 overflow-x-auto border-b border-n-weak bg-n-solid-1 px-3 py-2"
      :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.OPERATIONAL_BAR')"
    >
      <button
        type="button"
        class="grid size-8 shrink-0 place-items-center rounded-md border border-n-weak text-n-slate-11 xl:hidden"
        :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.TOGGLE_LIST')"
        :aria-expanded="listOpen"
        @click="listOpen = !listOpen"
      >
        <span class="i-lucide-panel-left size-4" />
      </button>
      <template v-if="isVoice">
        <button
          v-for="action in voiceActions"
          :key="action.key"
          type="button"
          :disabled="!action.enabled"
          :title="labels[action.key]"
          :aria-label="labels[action.key]"
          class="grid size-8 shrink-0 place-items-center rounded-md border border-n-weak transition disabled:cursor-not-allowed disabled:opacity-40"
          :class="
            action.danger
              ? 'bg-n-ruby-9 text-white'
              : 'bg-n-blue-2 text-n-brand hover:bg-n-blue-3'
          "
          @click="runAction(action)"
        >
          <span class="size-4" :class="action.icon" />
        </button>
      </template>
      <MoreActions
        v-else-if="nativeConversationReady"
        class="shrink-0"
        :request-closing="requiresWhatsAppClosing ? startClosing : null"
      />
      <button
        type="button"
        :disabled="!canOperate"
        class="flex h-8 shrink-0 items-center gap-2 rounded-md border border-n-weak px-2.5 text-xs font-medium text-n-slate-11 disabled:opacity-40"
        @click="pauseDialog.open()"
      >
        <span class="i-lucide-pause size-3.5" />
        {{ displayAgent?.state === 'paused' ? labels.RESUME : labels.PAUSE }}
      </button>
      <span
        class="hidden shrink-0 items-center gap-2 border-l border-n-weak px-2 text-xs text-n-slate-11 2xl:flex"
      >
        <span
          class="size-2 rounded-full"
          :class="
            displayAgent?.state === 'paused'
              ? 'bg-n-amber-9'
              : displayAgent?.state === 'available'
                ? 'bg-n-teal-9'
                : 'bg-n-slate-8'
          "
        />
        {{
          displayAgent?.state === 'paused'
            ? t('JRC_CONTACT_CENTER.COMMON.CODE_DETAIL', {
                code: pauseLabels[agent.reason_code],
                detail: pausedElapsed,
              })
            : agentLabels[displayAgent?.state || 'offline']
        }}
      </span>
      <button
        type="button"
        :disabled="!hasSelection"
        class="flex h-8 min-w-28 max-w-56 flex-1 items-center gap-2 rounded-md border border-n-weak px-2.5 text-left text-xs font-medium text-n-slate-12 disabled:opacity-40"
        @click="openQuick('QUALIFICATIONS')"
      >
        <span class="i-lucide-tag size-4 shrink-0 text-n-brand" />
        <span class="truncate">
          {{
            qualification || t('JRC_CONTACT_CENTER.INBOX_360.QUALIFICATIONS')
          }}
        </span>
        <span class="i-lucide-chevron-down ml-auto size-3 shrink-0" />
      </button>
      <button
        type="button"
        :disabled="!hasSelection"
        class="flex h-8 shrink-0 items-center gap-2 rounded-md border border-n-weak px-2.5 text-xs font-medium text-n-slate-11 disabled:opacity-40"
        :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.REPLIES')"
        :title="t('JRC_CONTACT_CENTER.INBOX_360.REPLIES')"
        @click="openQuick('REPLIES')"
      >
        <span class="i-lucide-message-square-text size-4" />
        <span class="hidden 2xl:inline">
          {{ t('JRC_CONTACT_CENTER.INBOX_360.REPLIES') }}
        </span>
      </button>
      <RouterLink
        :to="{ name: 'search', params: { accountId } }"
        class="grid size-8 shrink-0 place-items-center rounded-md border border-n-weak text-n-slate-11"
        :aria-label="t('JRC_CONTACT_CENTER.INBOX.SEARCH')"
      >
        <span class="i-lucide-search size-4" />
      </RouterLink>
      <RouterLink
        v-if="isVoice"
        :to="{ name: 'ramal_index', params: { accountId } }"
        class="ml-auto flex h-8 shrink-0 items-center gap-2 rounded-md bg-n-brand px-3 text-xs font-semibold text-white"
      >
        <span class="i-lucide-headset size-4" />
        <span class="hidden 2xl:inline">
          {{ t('JRC_CONTACT_CENTER.INBOX_360.WEBPHONE') }}
        </span>
      </RouterLink>
    </header>
    <p
      v-if="actionError || phoneError"
      role="alert"
      class="m-0 shrink-0 bg-n-ruby-2 px-4 py-2 text-xs text-n-ruby-11"
    >
      {{ phoneError || t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <div class="relative flex min-h-0 min-w-0 flex-1 gap-2 p-2">
      <aside
        class="z-20 h-full min-h-0 shrink-0 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 xl:relative xl:inset-auto xl:z-auto xl:flex xl:w-56 2xl:w-60"
        :class="
          listOpen ? 'absolute inset-y-2 left-2 flex w-72 shadow-xl' : 'hidden'
        "
        data-testid="inbox-list"
      >
        <header class="border-b border-n-weak p-3">
          <div class="flex items-center justify-between gap-2">
            <h1 class="m-0 text-xs font-semibold leading-5 text-n-slate-12">
              {{
                t('JRC_CONTACT_CENTER.INBOX_360.LABEL_COUNT', {
                  label: labels.ACTIVE_INTERACTIONS,
                  count:
                    conversations.length +
                    (['all', 'voice'].includes(channelFilter)
                      ? calls.length
                      : 0),
                })
              }}
            </h1>
            <button
              v-if="listOpen"
              type="button"
              class="grid size-6 shrink-0 place-items-center text-n-slate-10 xl:hidden"
              :aria-label="t('DIALOG.BUTTONS.CANCEL')"
              @click="listOpen = false"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </div>
          <div class="mt-2 flex gap-1.5">
            <select
              :value="assigneeFilter"
              :aria-label="t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE_FILTER_LABEL')"
              class="h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-solid-1 px-1.5 !py-0 text-[11px] text-n-slate-11"
              @change="emit('assigneeChange', $event.target.value)"
            >
              <option
                v-for="option in assignees"
                :key="option.key"
                :value="option.key"
              >
                {{ option.label }}
              </option>
            </select>
            <select
              :value="channelFilter"
              :aria-label="t('JRC_CONTACT_CENTER.INBOX.CHANNEL_FILTER_LABEL')"
              class="h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-solid-1 px-1.5 !py-0 text-[11px] text-n-slate-11"
              @change="emit('channelChange', $event.target.value)"
            >
              <option
                v-for="option in channels"
                :key="option.key"
                :value="option.key"
              >
                {{ option.label }}
              </option>
            </select>
          </div>
        </header>
        <div class="min-h-0 flex-1 overflow-y-auto p-2">
          <InboxChannelGroups
            :calls="calls"
            :conversations="conversations"
            :channels="channels"
            :channel-filter="channelFilter"
            :inbox-for="inboxFor"
            :current-call-id="currentCallId"
            :current-conversation-id="currentConversationId"
            :selected-customer-name="customerName"
            @select-call="selectCall"
            @select-conversation="selectConversation"
          />
          <div v-if="loading" class="flex justify-center py-5">
            <Spinner />
          </div>
          <p
            v-else-if="voiceError"
            role="alert"
            class="p-3 text-xs text-n-ruby-11"
          >
            {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
          </p>
          <button
            v-if="canLoadMore"
            type="button"
            class="w-full rounded-md border border-n-weak py-2 text-xs text-n-brand"
            @click="emit('loadMore')"
          >
            {{ t('JRC_CONTACT_CENTER.INBOX.LOAD_MORE') }}
          </button>
        </div>
      </aside>
      <main
        class="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
        data-testid="interaction-workspace"
      >
        <header
          class="flex h-12 shrink-0 items-center justify-between gap-3 bg-n-brand px-4 text-white"
        >
          <div class="flex min-w-0 items-center gap-2.5">
            <span
              class="size-5 shrink-0"
              :class="channel?.icon || 'i-lucide-inbox'"
            />
            <h2 class="m-0 truncate text-sm font-medium text-white">
              {{ hasSelection ? title : t('JRC_CONTACT_CENTER.INBOX.TITLE') }}
              <span v-if="hasSelection" class="ml-2 text-xs opacity-80">
                {{ statusLabel }}
              </span>
            </h2>
          </div>
          <span
            v-if="isVoice && call"
            class="flex shrink-0 items-center gap-2 text-xs tabular-nums"
          >
            <span class="size-2 rounded-full bg-n-ruby-9" />
            {{ duration }}
          </span>
          <span
            v-else-if="hasSelection"
            class="shrink-0 rounded-full bg-white/15 px-2 py-1 text-[10px]"
          >
            {{ channel?.label }}
          </span>
          <button
            v-if="
              (isVoice && call && !['ended', 'failed'].includes(call.status)) ||
              (requiresWhatsAppClosing && conversation?.status !== 'resolved')
            "
            type="button"
            class="ml-auto flex h-8 shrink-0 items-center gap-2 rounded-md bg-n-ruby-9 px-3 text-xs font-semibold text-white hover:bg-n-ruby-10"
            :disabled="
              closingSaving ||
              (isVoice &&
                !voiceActions.find(action => action.key === 'HANGUP')?.enabled)
            "
            @click="startClosing"
          >
            <span
              class="size-4"
              :class="
                isVoice ? 'i-lucide-phone-off' : 'i-lucide-message-square-off'
              "
            />
            {{
              isVoice
                ? t('JRC_CONTACT_CENTER.INBOX_360.END_CALL')
                : t('JRC_CONTACT_CENTER.INBOX_360.END_ATTENDANCE')
            }}
          </button>
          <button
            type="button"
            class="grid size-7 shrink-0 place-items-center rounded-md bg-white/15 text-white xl:hidden"
            :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.CUSTOMER')"
            @click="customerDialog.open()"
          >
            <span class="i-lucide-contact-round size-4" />
          </button>
        </header>
        <nav
          class="flex h-11 shrink-0 overflow-x-auto border-b border-n-weak px-2"
          :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.WORKSPACE_TABS')"
        >
          <button
            v-for="key in workspaceTabs"
            :key="key"
            type="button"
            class="shrink-0 border-b-2 px-2 py-2 text-[11px] font-medium transition"
            :class="
              tab === key
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
            "
            :aria-pressed="tab === key"
            :aria-label="labels[key]"
            :title="labels[key]"
            @click="
              tab = key;
              voiceSection =
                key === 'CASES'
                  ? 'case'
                  : key === 'TASKS'
                    ? 'callback'
                    : 'journey';
            "
          >
            <span class="hidden 2xl:inline">
              {{ labels[key] }}
            </span>
            <span class="2xl:hidden">
              {{
                key === 'SCRIPT'
                  ? t('JRC_CONTACT_CENTER.INBOX_360.SCRIPT_SHORT')
                  : key === 'CUSTOMER_DATA'
                    ? labels.CUSTOMER
                    : labels[key]
              }}
            </span>
          </button>
        </nav>
        <template v-if="isVoice">
          <div v-show="tab === 'CONVERSATION'" class="shrink-0 p-4 pb-0">
            <div
              class="flex items-center gap-3 rounded-lg border border-n-weak bg-n-alpha-1 p-3"
            >
              <span
                class="grid size-10 shrink-0 place-items-center rounded-full bg-n-teal-3 text-n-teal-11"
              >
                <span class="i-lucide-phone-incoming size-5" />
              </span>
              <div class="min-w-0 flex-1">
                <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                  {{ t('JRC_CONTACT_CENTER.INBOX_360.CURRENT_CALL') }}
                </h3>
                <p class="mb-0 mt-1 truncate text-xs text-n-slate-10">
                  {{ title }}
                  <span v-if="customerName">
                    {{ customerName }}
                  </span>
                </p>
              </div>
              <span
                class="rounded-full bg-n-blue-3 px-2 py-1 text-[10px] text-n-blue-11"
              >
                {{ statusLabel }}
              </span>
            </div>
          </div>
          <div
            v-show="['CONVERSATION', 'CASES', 'TASKS'].includes(tab)"
            class="min-h-0 flex-1 overflow-y-auto"
          >
            <InboxContextContent
              v-if="
                (tab === 'CASES' && cases.length) ||
                (tab === 'TASKS' && crm?.timeline?.length)
              "
              :tab="tab"
              :crm="crm"
              :cases="cases"
            />
            <p
              v-if="voiceError"
              role="alert"
              class="p-4 text-xs text-n-ruby-11"
            >
              {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
            </p>
            <CallWorkspace
              v-else-if="context"
              ref="callWorkspace"
              :key="`${accountId}-${currentCallId}`"
              :account-id="accountId"
              :call-id="currentCallId"
              :context="context"
              compact
              :section="voiceSection"
              class="!rounded-none !border-0 !bg-transparent !shadow-none"
              @loaded="loaded"
              @created="emit('refresh')"
            />
            <div v-else class="flex justify-center py-12">
              <Spinner />
            </div>
          </div>
        </template>
        <div v-else v-show="tab === 'CONVERSATION'" class="flex min-h-0 flex-1">
          <RouterView
            v-if="ready"
            :key="`${accountId}-${currentConversationId}`"
            embedded
          />
          <div v-else class="grid flex-1 place-items-center">
            <Spinner />
          </div>
        </div>
        <div
          v-if="supportsClosing && tab === 'CLOSING'"
          class="min-h-0 flex-1 overflow-y-auto p-4"
        >
          <div
            v-if="closingError || closingBlocked"
            role="alert"
            class="mb-3 rounded-md bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
          >
            {{
              closingBlocked
                ? t('JRC_CONTACT_CENTER.ACW_OPERATION.SELECTION_BLOCKED')
                : t('JRC_CONTACT_CENTER.ACW_OPERATION.SAVE_ERROR')
            }}
          </div>
          <div class="flex min-w-0 flex-col gap-4">
            <section
              v-if="closingPending"
              class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
            >
              <div
                :class="
                  acwOverdue
                    ? 'bg-n-ruby-2 text-n-ruby-11'
                    : 'bg-n-blue-2 text-n-blue-11'
                "
                class="mb-4 flex flex-wrap items-center justify-between gap-2 rounded-lg p-3"
              >
                <span class="text-sm font-semibold">{{
                  acwOverdue
                    ? t('JRC_CONTACT_CENTER.ACW_OPERATION.OVERDUE')
                    : t('JRC_CONTACT_CENTER.INBOX_360.ACW')
                }}</span>
                <span class="text-2xl font-bold tabular-nums">{{
                  formatSeconds(acwElapsedSeconds)
                }}</span>
                <span class="w-full text-xs">{{
                  t('JRC_CONTACT_CENTER.ACW_OPERATION.APPLIED_LIMIT', {
                    time: formatSeconds(acwLimitSeconds),
                  })
                }}</span>
                <progress
                  class="h-2 w-full"
                  :value="Math.min(acwElapsedSeconds, acwLimitSeconds)"
                  :max="acwLimitSeconds"
                />
              </div>
              <h3 class="m-0 text-sm font-semibold text-n-slate-12">
                {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_TITLE') }}
              </h3>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_HISTORY') }}
              </p>
              <div class="mt-4 grid min-w-0 grid-cols-1 gap-3">
                <label class="text-xs font-medium text-n-slate-11">
                  {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.REASON_REQUIRED') }}
                  <select
                    v-model="closingReason"
                    class="mt-1 h-9 w-full rounded-md border border-n-weak bg-n-solid-1 px-2 text-xs"
                  >
                    <option value="">
                      {{
                        t(
                          'JRC_CONTACT_CENTER.INBOX_360.CLOSING_REASON_PLACEHOLDER'
                        )
                      }}
                    </option>
                    <option value="resolved">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_RESOLVED') }}
                    </option>
                    <option value="information">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_INFORMATION') }}
                    </option>
                    <option value="order">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_ORDER') }}
                    </option>
                    <option value="callback">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_CALLBACK') }}
                    </option>
                    <option value="transfer">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_TRANSFER') }}
                    </option>
                  </select>
                </label>
                <label class="text-xs font-medium text-n-slate-11">
                  {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.RESULT_REQUIRED') }}
                  <select
                    v-model="closingResult"
                    class="mt-1 h-9 w-full rounded-md border border-n-weak bg-n-solid-1 px-2 text-xs"
                  >
                    <option value="">
                      {{
                        t(
                          'JRC_CONTACT_CENTER.INBOX_360.CLOSING_RESULT_PLACEHOLDER'
                        )
                      }}
                    </option>
                    <option value="completed">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_COMPLETED') }}
                    </option>
                    <option value="pending">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_PENDING') }}
                    </option>
                    <option value="callback">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_CALLBACK') }}
                    </option>
                    <option value="forwarded">
                      {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_FORWARDED') }}
                    </option>
                  </select>
                </label>
              </div>
              <label class="mt-3 block text-xs font-medium text-n-slate-11">
                {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_NOTE') }}
                <textarea
                  v-model="closingNote"
                  rows="5"
                  class="mt-1 w-full resize-none rounded-md border border-n-weak bg-n-solid-1 p-3 text-xs"
                  :placeholder="
                    t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_NOTE_PLACEHOLDER')
                  "
                />
              </label>
              <button
                type="button"
                :disabled="closingSaving || !closingReason || !closingResult"
                class="mt-4 w-full rounded-md bg-n-brand px-4 py-2 text-xs font-semibold text-white disabled:opacity-40"
                @click="finishClosing"
              >
                {{ t('JRC_CONTACT_CENTER.INBOX_360.FINISH_TABULATION') }}
              </button>
            </section>
            <p
              v-else-if="!closingRecords.some(record => record.completed_at)"
              class="text-sm text-n-slate-11"
            >
              {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.AWAITING_TERMINAL') }}
            </p>
            <QualificationHistory :records="closingRecords" />
          </div>
        </div>
        <QualificationHistory
          v-if="tab === 'HISTORY' && supportsClosing"
          class="p-4"
          :records="closingRecords"
        />
        <InboxContextContent
          v-if="
            tab !== 'CONVERSATION' &&
            tab !== 'CLOSING' &&
            !(isVoice && ['CASES', 'TASKS'].includes(tab))
          "
          :tab="tab"
          :crm="crm"
          :contact="contact"
          :company="company"
          :cases="cases"
          :script-reply="scriptReply"
          @replies="openQuick('REPLIES')"
        />
        <footer
          v-if="isVoice && hasSelection"
          class="flex shrink-0 items-center gap-3 border-t border-n-weak px-4 py-3 text-[11px]"
        >
          <button
            type="button"
            class="shrink-0 whitespace-nowrap text-n-brand"
            @click="
              tab = 'CASES';
              voiceSection = 'case';
            "
          >
            {{ t('JRC_CONTACT_CENTER.INBOX_360.FINALIZE') }}
          </button>
          <button
            type="button"
            class="shrink-0 whitespace-nowrap text-n-brand"
            @click="
              tab = 'TASKS';
              voiceSection = 'callback';
            "
          >
            {{ t('JRC_CONTACT_CENTER.INBOX_360.CALLBACK') }}
          </button>
          <span class="ml-auto text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.SURVEY_RULES') }}
          </span>
        </footer>
      </main>
      <aside
        class="hidden h-full min-h-0 w-60 shrink-0 overflow-y-auto xl:block 2xl:w-[280px]"
        data-testid="customer-column"
      >
        <InboxCustomerPanel
          v-bind="customerProps"
          :key="`${accountId}-${identity.contactId}`"
          @show-tab="showTab"
          @more="detailsDialog.open()"
        />
      </aside>
    </div>
    <Dialog
      ref="pauseDialog"
      :title="t('JRC_CONTACT_CENTER.INBOX_360.PAUSE')"
      :show-confirm-button="false"
      show-close-button
      width="3xl"
    >
      <AgentStatePanel
        compact
        :account-id="accountId"
        :can-operate="canOperate"
        @state-change="agent = $event"
      />
    </Dialog>
    <Dialog
      ref="customerDialog"
      :show-confirm-button="false"
      :show-cancel-button="false"
      width="sm"
    >
      <div class="max-h-[calc(100dvh-6rem)] overflow-y-auto">
        <InboxCustomerPanel
          v-bind="customerProps"
          closable
          @close="customerDialog.close()"
          @show-tab="showTab"
          @more="detailsDialog.open()"
        />
      </div>
    </Dialog>
    <Dialog
      ref="detailsDialog"
      :title="t('JRC_CONTACT_CENTER.INBOX_360.MORE')"
      :show-confirm-button="false"
      show-close-button
      width="lg"
    >
      <div class="flex max-h-[70vh] min-w-0 overflow-y-auto">
        <ConversationSidebar
          v-if="nativeConversationReady"
          :current-chat="selectedChat"
        />
        <InboxContextContent
          v-else
          tab="CUSTOMER_DATA"
          :contact="contact"
          :company="company"
        />
      </div>
    </Dialog>
    <InboxQuickActions
      ref="quickActions"
      :account-id="accountId"
      :conversation-id="currentConversationId"
      :call-id="currentCallId"
      :categories="categories"
      @insert="insertReply"
      @qualify="qualify"
      @labels-updated="
        store.dispatch('conversationLabels/setConversationLabel', $event)
      "
    />
  </section>
</template>
