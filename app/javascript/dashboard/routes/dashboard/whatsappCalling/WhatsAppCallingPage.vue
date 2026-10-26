<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import ContactAPI from 'dashboard/api/contacts';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import CallsAPI from 'dashboard/api/calls';
import WhatsappCallsAPI from 'dashboard/api/channel/whatsapp/whatsappCallsAPI';
import WhatsappCallingConfigurationAPI from 'dashboard/api/whatsappCallingConfiguration';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import { useCallsStore } from 'dashboard/stores/calls';
import { useCallActions } from 'dashboard/composables/useCallSession';
import {
  getVoiceCallProvider,
  VOICE_CALL_PROVIDERS,
} from 'dashboard/helper/inbox';
import {
  VOICE_CALL_DIRECTION,
  VOICE_CALL_OUTBOUND_INIT_STATUS,
} from 'dashboard/components-next/message/constants';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const callsStore = useCallsStore();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const whatsappCallSession = useWhatsappCallSession();
const callActions = useCallActions();

const CONTACT_PAGE_SIZE = 15;
const CONTACT_SEARCH_DEBOUNCE = 300;
const KEYPAD_KEYS = [
  { value: '1', letters: '' },
  { value: '2', letters: 'ABC' },
  { value: '3', letters: 'DEF' },
  { value: '4', letters: 'GHI' },
  { value: '5', letters: 'JKL' },
  { value: '6', letters: 'MNO' },
  { value: '7', letters: 'PQRS' },
  { value: '8', letters: 'TUV' },
  { value: '9', letters: 'WXYZ' },
  { value: '*', letters: '' },
  { value: '0', letters: '+' },
  { value: '#', letters: '' },
];

const destination = ref('');
const currentContact = ref(null);
const currentContactNumber = ref('');
const contactSearchQuery = ref('');
const contactSearchResults = ref([]);
const contactSearching = ref(false);
const contactLoadingMore = ref(false);
const contactSearchPage = ref(1);
const contactHasMore = ref(false);
const contactConversations = ref([]);
const conversationsLoading = ref(false);
const whatsappConversations = ref([]);
const whatsappConversationsLoading = ref(false);
const whatsappConversationSearch = ref('');
const messageDraft = ref('');
const messageSending = ref(false);
const showCallKeypad = ref(false);
const configuration = ref({
  enabled: false,
  status: 'not_configured',
  active: false,
});
const selectedInboxId = ref(null);
const callState = ref('idle');
const isEndingCall = ref(false);
const historyCalls = ref([]);
const historyLoading = ref(false);
const historyPeriod = ref(7);
const historyDirection = ref('');
const historyStatus = ref('');
const historyStats = ref({ total: 0, answered: 0, missed: 0 });
const permission = ref({
  status: 'idle',
  can_start_call: false,
  can_request_permission: false,
});
const permissionLoading = ref(false);
let contactSearchVersion = 0;
let hadWhatsappCall = false;

const contactPhoneNumber = contact =>
  contact?.phone_number || contact?.phoneNumber || '';
const normalizePhone = phone => String(phone || '').replace(/\D/g, '');
const contactsWithPhone = contacts =>
  (contacts || []).filter(contact => contactPhoneNumber(contact));
const mergeContactResults = (current, incomingContacts) => {
  const contacts = new Map(current.map(contact => [contact.id, contact]));
  incomingContacts.forEach(contact => contacts.set(contact.id, contact));
  return [...contacts.values()];
};

const whatsappInboxes = computed(() =>
  (inboxes.value || []).filter(inbox => {
    const medium = String(inbox?.medium || '').toLowerCase();
    const channelType = inbox?.channel_type || inbox?.channelType;
    return (
      medium === 'whatsapp' ||
      channelType === 'Channel::Whatsapp' ||
      getVoiceCallProvider(inbox) === VOICE_CALL_PROVIDERS.WHATSAPP
    );
  })
);
const whatsappInboxIds = computed(() =>
  new Set(whatsappInboxes.value.map(inbox => Number(inbox.id)))
);

const whatsappVoiceInboxes = computed(() =>
  (inboxes.value || []).filter(
    inbox => getVoiceCallProvider(inbox) === VOICE_CALL_PROVIDERS.WHATSAPP
  )
);
const normalizedDestination = computed(() => normalizePhone(destination.value));
const hasValidDestination = computed(() =>
  /^\+?[1-9]\d{7,14}$/.test(
    String(destination.value || '').replace(/[\s()-]/g, '')
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
const incomingWhatsappCall = computed(() =>
  callsStore.incomingCalls.find(
    call =>
      call.provider === VOICE_CALL_PROVIDERS.WHATSAPP &&
      call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND
  ) || null
);
const formattedCallDuration = callActions.formattedCallDuration;
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
const canEndCall = computed(
  () => !!currentWhatsappCall.value && !isEndingCall.value
);
const canAnswerCall = computed(
  () =>
    !!incomingWhatsappCall.value &&
    !callsStore.hasActiveCall &&
    !isEndingCall.value &&
    !callActions.isJoining.value
);
const canCall = computed(
  () =>
    configuration.value.active &&
    hasWhatsappInbox.value &&
    hasValidDestination.value &&
    selectedInboxId.value &&
    permission.value.status === 'approved' &&
    permission.value.can_start_call &&
    permission.value.target_key === permissionTargetKey.value &&
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
  () => canCheckPermission.value && permission.value.can_request_permission
);

const configurationLabel = computed(() =>
  configuration.value.active
    ? t('WHATSAPP_CALLING.ACTIVE')
    : t('WHATSAPP_CALLING.INACTIVE')
);
const configurationDescription = computed(() => {
  if (!configuration.value.active)
    return t('WHATSAPP_CALLING.STATUS.AWAITING_META');
  if (!hasWhatsappInbox.value)
    return t('WHATSAPP_CALLING.STATUS.AWAITING_INBOX');
  return t('WHATSAPP_CALLING.STATUS.VALIDATED');
});
const buttonHelp = computed(() => {
  if (!configuration.value.active)
    return t('WHATSAPP_CALLING.HELP.NOT_CONFIGURED');
  if (!hasWhatsappInbox.value) return t('WHATSAPP_CALLING.HELP.NO_INBOX');
  if (!hasValidDestination.value)
    return t('WHATSAPP_CALLING.HELP.INVALID_NUMBER');
  if (permission.value.status !== 'approved')
    return t('WHATSAPP_CALLING.HELP.CHECK_PERMISSION');
  return t('WHATSAPP_CALLING.HELP.READY');
});

const permissionMessage = computed(() => {
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
  return messages[permission.value.status] || '';
});


const conversationSender = conversation => conversation?.meta?.sender || {};
const conversationPhone = conversation =>
  contactPhoneNumber(conversationSender(conversation));
const filteredWhatsappConversations = computed(() => {
  const query = String(whatsappConversationSearch.value || '')
    .trim()
    .toLowerCase();
  if (!query) return whatsappConversations.value;
  return whatsappConversations.value.filter(conversation => {
    const sender = conversationSender(conversation);
    const preview = conversationPreview(conversation);
    return [sender?.name, contactPhoneNumber(sender), preview]
      .filter(Boolean)
      .some(value => String(value).toLowerCase().includes(query));
  });
});
const formatConversationListTime = conversation => {
  const timestamp =
    conversation?.last_activity_at ||
    conversation?.updated_at ||
    conversation?.created_at;
  if (!timestamp) return '';
  const numeric = Number(timestamp);
  const date = Number.isFinite(numeric)
    ? new Date(numeric < 1_000_000_000_000 ? numeric * 1000 : numeric)
    : new Date(timestamp);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};

const activeConversation = computed(() => contactConversations.value[0] || null);
const activeConversationDetails = computed(() => {
  const conversation = activeConversation.value;
  if (!conversation) return null;
  return store.getters.getConversationById?.(conversation.id) || conversation;
});
const conversationMessages = computed(() =>
  [...(activeConversationDetails.value?.messages || [])]
    .filter(
      message =>
        [0, 1].includes(message.message_type) &&
        message.private !== true &&
        (message.content || message.attachments?.length)
    )
    .sort((a, b) => Number(a.created_at || 0) - Number(b.created_at || 0))
    .slice(-40)
);
const isOutgoingMessage = message => Number(message?.message_type) === 1;
const formatMessageTime = timestamp => {
  if (!timestamp) return '';
  const date = new Date(Number(timestamp) * 1000);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
};
const sendConversationMessage = async () => {
  const message = messageDraft.value.trim();
  const conversation = activeConversation.value;
  if (!message || !conversation || messageSending.value) return;
  messageSending.value = true;
  try {
    await store.dispatch('createPendingMessageAndSend', {
      conversationId: conversation.id,
      message,
      private: false,
    });
    messageDraft.value = '';
    if (conversation.id) await store.dispatch('getConversation', conversation.id);
    useAlert('Mensagem enviada com sucesso.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não foi possível enviar a mensagem.');
  } finally {
    messageSending.value = false;
  }
};

const loadWhatsappConversations = async () => {
  const inboxIds = [...whatsappInboxIds.value];
  if (!inboxIds.length) {
    whatsappConversations.value = [];
    return;
  }

  whatsappConversationsLoading.value = true;
  try {
    const responses = await Promise.all(
      inboxIds.map(inboxId =>
        ConversationAPI.get({
          inboxId,
          status: 'all',
          page: 1,
        })
      )
    );
    const byId = new Map();
    responses.forEach(response => {
      const payload = response?.data?.data?.payload || [];
      payload.forEach(conversation => byId.set(conversation.id, conversation));
    });
    whatsappConversations.value = [...byId.values()].sort(
      (a, b) =>
        Number(b.last_activity_at || b.updated_at || 0) -
        Number(a.last_activity_at || a.updated_at || 0)
    );
  } catch (error) {
    whatsappConversations.value = [];
    useAlert(
      error?.response?.data?.error ||
        'Não foi possível carregar as conversas do WhatsApp.'
    );
  } finally {
    whatsappConversationsLoading.value = false;
  }
};

const selectWhatsappConversation = async conversation => {
  if (!conversation) return;
  const sender = conversationSender(conversation);
  const phone = conversationPhone(conversation);
  currentContact.value = sender?.id ? sender : null;
  currentContactNumber.value = phone || '';
  destination.value = phone || '';
  contactConversations.value = [conversation];

  const conversationInboxId = Number(
    conversation?.inbox_id || conversation?.inbox?.id
  );
  const matchingVoiceInbox = whatsappVoiceInboxes.value.find(
    inbox => Number(inbox.id) === conversationInboxId
  );
  selectedInboxId.value =
    matchingVoiceInbox?.id || whatsappVoiceInboxes.value[0]?.id || null;

  if (conversation.id) {
    await store.dispatch('getConversation', conversation.id);
  }
  if (configuration.value.active && selectedInboxId.value && phone) {
    await checkPermission();
  }
};

const loadContactConversations = async contactId => {
  if (!contactId) {
    contactConversations.value = [];
    return;
  }
  conversationsLoading.value = true;
  try {
    const { data } = await ContactAPI.getConversations(contactId);
    contactConversations.value = data?.payload || [];
    const firstConversation = contactConversations.value[0];
    if (firstConversation?.id) {
      await store.dispatch('getConversation', firstConversation.id);
    }
  } catch {
    contactConversations.value = [];
  } finally {
    conversationsLoading.value = false;
  }
};

const openConversation = conversation => {
  if (!conversation) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: conversation.display_id || conversation.id,
    },
  });
};

const conversationPreview = conversation =>
  conversation?.last_non_activity_message?.content ||
  conversation?.last_activity_message?.content ||
  'Conversa disponível para atendimento.';

const conversationStatusLabel = conversation => ({
  open: 'Aberta',
  pending: 'Pendente',
  resolved: 'Resolvida',
  snoozed: 'Adiada',
}[conversation?.status] || conversation?.status || 'Conversa');

const selectContact = contact => {
  const phone = contactPhoneNumber(contact);
  if (!phone) return;
  currentContact.value = contact;
  currentContactNumber.value = phone;
  destination.value = phone;
  loadContactConversations(contact.id);
};

const pressKey = key => {
  if (isBusy.value) return;
  destination.value = `${destination.value}${key}`;
};

const clearDestination = () => {
  if (isBusy.value) return;
  destination.value = '';
  currentContact.value = null;
  currentContactNumber.value = '';
  contactConversations.value = [];
};

const loadContacts = async ({ query = '', page = 1, append = false } = {}) => {
  contactSearchVersion += 1;
  const version = contactSearchVersion;
  if (append) contactLoadingMore.value = true;
  else contactSearching.value = true;

  try {
    const { data } = query
      ? await ContactAPI.search(query, page, 'name')
      : await ContactAPI.get(page, '-last_activity_at');
    if (version !== contactSearchVersion) return;

    const results = contactsWithPhone(data.payload);
    contactSearchResults.value = append
      ? mergeContactResults(contactSearchResults.value, results)
      : results;
    contactSearchPage.value = page;
    contactHasMore.value = results.length >= CONTACT_PAGE_SIZE;
  } catch {
    if (!append) contactSearchResults.value = [];
    contactHasMore.value = false;
  } finally {
    if (version === contactSearchVersion) {
      contactSearching.value = false;
      contactLoadingMore.value = false;
    }
  }
};

const searchContacts = debounce(query => {
  loadContacts({ query: String(query || '').trim(), page: 1 });
}, CONTACT_SEARCH_DEBOUNCE);

const loadMoreContacts = () => {
  if (!contactHasMore.value || contactLoadingMore.value) return;
  loadContacts({
    query: String(contactSearchQuery.value || '').trim(),
    page: contactSearchPage.value + 1,
    append: true,
  });
};

const loadConfiguration = async () => {
  try {
    configuration.value = await WhatsappCallingConfigurationAPI.get();
  } catch {
    configuration.value = { enabled: false, status: 'error', active: false };
  }
};

const dateRange = computed(() => {
  const until = Math.floor(Date.now() / 1000);
  const since = until - historyPeriod.value * 24 * 60 * 60;
  return { since, until };
});

const callCount = async extraParams => {
  const response = await CallsAPI.get({
    provider: 'whatsapp',
    ...dateRange.value,
    ...extraParams,
  });
  return response.data.meta.count;
};

const loadHistory = async () => {
  historyLoading.value = true;
  const params = {
    provider: 'whatsapp',
    ...dateRange.value,
    direction: historyDirection.value || undefined,
    status: historyStatus.value || undefined,
  };
  try {
    const [listResponse, total, answered, missed] = await Promise.all([
      CallsAPI.get(params),
      callCount({}),
      callCount({ status: 'completed' }),
      callCount({ status: 'no-answer', direction: 'inbound' }),
    ]);
    historyCalls.value = listResponse.data.payload;
    historyStats.value = { total, answered, missed };
  } catch {
    historyCalls.value = [];
    historyStats.value = { total: 0, answered: 0, missed: 0 };
  } finally {
    historyLoading.value = false;
  }
};

const callTarget = computed(() => {
  const selectedPhone = normalizePhone(currentContactNumber.value);
  return currentContact.value && selectedPhone === normalizedDestination.value
    ? { contactId: currentContact.value.id, inboxId: selectedInboxId.value }
    : {
        phoneNumber: normalizedDestination.value,
        inboxId: selectedInboxId.value,
      };
});

const applyPermission = response => {
  permission.value = {
    status: response?.status || 'permission_unavailable',
    can_start_call: Boolean(response?.can_start_call),
    can_request_permission: Boolean(response?.can_request_permission),
    target_key: permissionTargetKey.value,
  };
};

const functionalResponse = error => error?.response?.data;

const checkPermission = async () => {
  if (!canCheckPermission.value) return;
  permissionLoading.value = true;
  try {
    applyPermission(await WhatsappCallsAPI.permission(callTarget.value));
  } catch (error) {
    const response = functionalResponse(error);
    applyPermission(response);
    useAlert(response?.error || t('WHATSAPP_CALLING.PERMISSION.UNAVAILABLE'));
  } finally {
    permissionLoading.value = false;
  }
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
      useAlert(permissionMessage.value);
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

  if (response) {
    callState.value = 'active';
  }
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
    loadHistory();
  } catch (error) {
    useAlert(
      functionalResponse(error)?.error || t('WHATSAPP_CALLING.ALERT.END_FAILED')
    );
  } finally {
    isEndingCall.value = false;
  }
};

const callStatusLabel = computed(() => {
  const incoming = callsStore.incomingCalls?.find(
    call => call.provider === VOICE_CALL_PROVIDERS.WHATSAPP
  );
  if (callsStore.activeCall?.provider === VOICE_CALL_PROVIDERS.WHATSAPP)
    return t('WHATSAPP_CALLING.CALL_STATE.IN_PROGRESS');
  if (incoming?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND)
    return t('WHATSAPP_CALLING.CALL_STATE.CALLING');
  if (incoming) return t('WHATSAPP_CALLING.CALL_STATE.INCOMING');
  if (callState.value === 'calling')
    return t('WHATSAPP_CALLING.CALL_STATE.CALLING');
  if (callState.value === 'ended')
    return t('WHATSAPP_CALLING.CALL_STATE.ENDED');
  if (callState.value === 'failed')
    return t('WHATSAPP_CALLING.CALL_STATE.FAILED');
  if (!configuration.value.active || !hasWhatsappInbox.value)
    return 'Configuração necessária';
  return 'Disponível';
});

const phoneReadyLabel = computed(() => {
  if (activeWhatsappCall.value) return 'Chamada conectada';
  if (incomingWhatsappCall.value) return 'Chamada recebida';
  if (!configuration.value.active) return 'Ative o WhatsApp Calling nas configurações';
  if (!hasWhatsappInbox.value) return 'Configure uma caixa WhatsApp compatível com chamadas';
  return 'Pronto para ligar';
});

const formatCallDate = timestamp => {
  if (timestamp === null || timestamp === undefined || timestamp === '') {
    return '—';
  }

  const numericTimestamp = Number(timestamp);
  const date = Number.isFinite(numericTimestamp)
    ? new Date(
        numericTimestamp < 1_000_000_000_000
          ? numericTimestamp * 1000
          : numericTimestamp
      )
    : new Date(timestamp);

  if (Number.isNaN(date.getTime())) return '—';

  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(date);
};

const callSummary = call => {
  const direction =
    call.direction === 'inbound'
      ? t('WHATSAPP_CALLING.HISTORY.INBOUND')
      : t('WHATSAPP_CALLING.HISTORY.OUTBOUND');
  const statusLabels = {
    ringing: t('WHATSAPP_CALLING.HISTORY.STATUS.RINGING'),
    'in-progress': t('WHATSAPP_CALLING.HISTORY.STATUS.IN_PROGRESS'),
    completed: t('WHATSAPP_CALLING.HISTORY.STATUS.COMPLETED'),
    'no-answer': t('WHATSAPP_CALLING.HISTORY.STATUS.NO_ANSWER'),
    failed: t('WHATSAPP_CALLING.HISTORY.STATUS.FAILED'),
    rejected: t('WHATSAPP_CALLING.HISTORY.STATUS.REJECTED'),
  };
  const status = statusLabels[call.status] || call.status;
  return `${direction} · ${status}`;
};

watch(contactSearchQuery, query => searchContacts(query));
watch(
  whatsappInboxes,
  list => {
    if (list.length) loadWhatsappConversations();
    else whatsappConversations.value = [];
  },
  { immediate: true }
);
watch(
  currentWhatsappCall,
  call => {
    if (!call?.conversationId) return;
    const conversation = whatsappConversations.value.find(
      item => Number(item.id) === Number(call.conversationId)
    );
    if (conversation && activeConversation.value?.id !== conversation.id) {
      selectWhatsappConversation(conversation);
    }
  }
);

watch(
  whatsappVoiceInboxes,
  list => {
    if (!list.some(inbox => inbox.id === selectedInboxId.value)) {
      selectedInboxId.value = list[0]?.id || null;
    }
  },
  { immediate: true }
);
watch([historyPeriod, historyDirection, historyStatus], loadHistory);
watch([normalizedDestination, selectedInboxId], () => {
  permission.value = {
    status: 'idle',
    can_start_call: false,
    can_request_permission: false,
    target_key: null,
  };
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
      loadHistory();
    }
  }
);

onMounted(async () => {
  await loadConfiguration();
  loadHistory();
});
</script>

<template>
  <section class="h-full w-full overflow-y-auto bg-gradient-to-br from-n-blue-2 via-n-background to-n-teal-2 p-3 lg:p-4 xl:overflow-hidden">
    <div class="mx-auto grid max-w-[1580px] gap-3 xl:h-full xl:min-h-0 xl:grid-cols-[320px_minmax(430px,1fr)_minmax(430px,0.95fr)]">
      <aside class="flex min-h-[760px] flex-col overflow-hidden rounded-[22px] border border-n-weak bg-n-solid-2 shadow-sm xl:h-full xl:min-h-0">
        <div class="border-b border-n-weak p-4">
          <div class="flex items-center justify-between gap-3">
            <div>
              <div class="flex items-center gap-2">
                <span class="i-ri-whatsapp-fill size-5 text-emerald-500" />
                <h2 class="text-base font-semibold text-n-slate-12">WhatsApp</h2>
                <span class="rounded-full bg-emerald-500/10 px-2 py-0.5 text-[10px] font-semibold text-emerald-700">{{ whatsappConversations.length }}</span>
              </div>
              <p class="mt-1 text-xs text-n-slate-9">Conversas e chamadas no mesmo atendimento</p>
            </div>
            <button type="button" class="flex size-9 items-center justify-center rounded-lg border border-n-weak text-n-slate-9" :disabled="whatsappConversationsLoading" title="Atualizar conversas" @click="loadWhatsappConversations">
              <span class="i-lucide-refresh-cw size-4" :class="whatsappConversationsLoading ? 'animate-spin' : ''" />
            </button>
          </div>
          <div class="relative mt-3">
            <span class="i-lucide-search absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-8" />
            <input v-model="whatsappConversationSearch" type="search" class="h-10 w-full rounded-xl border border-n-weak bg-n-background pl-9 pr-3 text-sm text-n-slate-12 outline-none focus:border-emerald-500" placeholder="Buscar conversa, nome ou telefone" />
          </div>
        </div>

        <div class="min-h-0 flex-1 overflow-y-auto p-3">
          <div v-if="whatsappConversationsLoading" class="grid min-h-40 place-content-center text-sm text-n-slate-9">
            <span class="i-lucide-loader-circle mx-auto mb-2 size-5 animate-spin" />
            Carregando conversas…
          </div>
          <div v-else-if="filteredWhatsappConversations.length" class="space-y-2">
            <button v-for="conversation in filteredWhatsappConversations" :key="conversation.id" type="button" class="w-full rounded-xl border p-3 text-left transition" :class="activeConversation?.id === conversation.id ? 'border-emerald-500 bg-emerald-500/5 shadow-sm' : 'border-n-weak bg-n-background hover:border-emerald-300'" @click="selectWhatsappConversation(conversation)">
              <div class="flex items-start gap-3">
                <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-emerald-500/10 font-semibold text-emerald-700">{{ (conversationSender(conversation)?.name || 'W').slice(0, 1).toUpperCase() }}</span>
                <div class="min-w-0 flex-1">
                  <div class="flex items-center justify-between gap-2">
                    <strong class="truncate text-sm text-n-slate-12">{{ conversationSender(conversation)?.name || conversationPhone(conversation) || 'Contato WhatsApp' }}</strong>
                    <time class="shrink-0 text-[10px] text-n-slate-8">{{ formatConversationListTime(conversation) }}</time>
                  </div>
                  <p class="mt-1 truncate text-xs text-n-slate-9">{{ conversationPreview(conversation) }}</p>
                  <div class="mt-2 flex items-center justify-between">
                    <span class="flex items-center gap-1 text-[10px] font-semibold text-emerald-600"><span class="i-ri-whatsapp-fill size-3" /> WhatsApp</span>
                    <span v-if="conversation.unread_count" class="min-w-5 rounded-full bg-blue-500 px-1.5 py-0.5 text-center text-[10px] font-bold text-white">{{ conversation.unread_count }}</span>
                  </div>
                </div>
              </div>
            </button>
          </div>
          <div v-else class="grid min-h-48 place-content-center rounded-xl border border-dashed border-n-weak text-center text-sm text-n-slate-9">
            <span class="i-ri-whatsapp-line mx-auto mb-2 size-7 text-emerald-500" />
            <strong class="text-n-slate-11">Nenhuma conversa WhatsApp</strong>
            <span class="mt-1 text-xs">As conversas recebidas aparecerão aqui.</span>
          </div>
        </div>
      </aside>

      <main class="flex min-h-[760px] flex-col overflow-hidden rounded-[22px] border border-n-weak bg-n-solid-2 shadow-sm xl:h-full xl:min-h-0">
        <header class="border-b border-n-weak px-5 py-4">
          <div class="flex items-center justify-between gap-3">
            <div class="flex min-w-0 items-center gap-3">
              <span class="flex size-11 shrink-0 items-center justify-center rounded-full bg-emerald-500/10 font-semibold text-emerald-700">
                {{ currentContact ? (currentContact.name || 'C').slice(0, 1).toUpperCase() : 'WA' }}
              </span>
              <div class="min-w-0">
                <h1 class="truncate text-lg font-semibold text-n-slate-12">{{ currentContact?.name || 'WhatsApp' }}</h1>
                <p class="truncate text-xs text-n-slate-9">{{ currentContactNumber || 'Selecione uma conversa do WhatsApp' }}</p>
              </div>
              <span v-if="currentContact" class="rounded-full bg-emerald-500/10 px-2 py-1 text-[11px] font-semibold text-emerald-700">WhatsApp</span><span v-if="currentContact" class="rounded-full bg-blue-500/10 px-2 py-1 text-[11px] font-semibold text-blue-700">{{ contactConversations.length }} conversa(s)</span>
            </div>
            <div class="flex gap-2">
              <button type="button" class="flex size-9 items-center justify-center rounded-lg border border-n-weak text-n-slate-10"><span class="i-lucide-user-plus size-4" /></button>
              <button type="button" class="flex size-9 items-center justify-center rounded-lg border border-n-weak text-n-slate-10"><span class="i-lucide-tags size-4" /></button>
              <button type="button" class="flex size-9 items-center justify-center rounded-lg border border-n-weak text-n-slate-10"><span class="i-lucide-ellipsis-vertical size-4" /></button>
            </div>
          </div>
        </header>

        <div class="flex flex-1 flex-col overflow-y-auto p-5">
          <div class="flex flex-1 flex-col min-h-0">
            <div v-if="!currentContact" class="grid min-h-[520px] flex-1 place-content-center rounded-2xl border border-dashed border-n-weak bg-n-alpha-2 text-center">
              <span class="i-lucide-message-circle-more mx-auto size-10 text-blue-500" />
              <h3 class="mt-3 font-semibold text-n-slate-12">Selecione uma conversa</h3>
              <p class="mt-1 max-w-sm text-sm text-n-slate-9">A conversa ficará no centro e a chamada WhatsApp do mesmo cliente ficará disponível no painel da direita.</p>
            </div>

            <div v-else class="flex min-h-0 flex-1 flex-col">
              <div class="mb-3 flex items-center justify-between gap-3 rounded-xl border border-amber-300/60 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                <span><strong>WhatsApp:</strong> mensagens e chamadas ficam juntas nesta área. O módulo Conversas geral continua separado para os demais canais.</span>
                <button v-if="activeConversation" type="button" class="shrink-0 rounded-lg border border-amber-400 bg-white px-3 py-1.5 text-xs font-semibold text-amber-800" @click="openConversation(activeConversation)">Abrir em Conversas</button>
              </div>

              <div v-if="conversationsLoading" class="grid flex-1 place-content-center text-sm text-n-slate-9">
                <span class="i-lucide-loader-circle mr-2 inline-block size-4 animate-spin" /> Carregando conversa…
              </div>

              <div v-else-if="activeConversation" class="flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-background">
                <div class="flex items-center justify-between border-b border-n-weak px-4 py-3">
                  <div class="flex items-center gap-2">
                    <span class="i-ri-whatsapp-fill size-5 text-emerald-500" />
                    <div>
                      <strong class="block text-sm text-n-slate-12">Conversa WhatsApp</strong>
                      <span class="text-[11px] text-n-slate-9">{{ conversationStatusLabel(activeConversation) }} · {{ activeConversation.inbox?.name || 'WhatsApp' }}</span>
                    </div>
                  </div>
                  <span class="rounded-full bg-blue-50 px-2 py-1 text-[10px] font-semibold text-blue-700">#{{ activeConversation.display_id || activeConversation.id }}</span>
                </div>

                <div class="flex-1 space-y-3 overflow-y-auto bg-n-alpha-1 px-4 py-4">
                  <template v-if="conversationMessages.length">
                    <div v-for="message in conversationMessages" :key="message.id" class="flex" :class="isOutgoingMessage(message) ? 'justify-end' : 'justify-start'">
                      <div class="max-w-[78%] rounded-2xl px-4 py-2.5 text-sm leading-5 shadow-sm" :class="isOutgoingMessage(message) ? 'rounded-br-md bg-emerald-100 text-emerald-950' : 'rounded-bl-md border border-n-weak bg-white text-n-slate-12'">
                        <p class="whitespace-pre-wrap break-words">{{ message.content || 'Anexo enviado' }}</p>
                        <div class="mt-1 text-right text-[10px]" :class="isOutgoingMessage(message) ? 'text-emerald-700' : 'text-n-slate-8'">{{ formatMessageTime(message.created_at) }}</div>
                      </div>
                    </div>
                  </template>
                  <div v-else class="grid min-h-64 place-content-center text-center text-sm text-n-slate-9">
                    <span class="i-lucide-message-square-dashed mx-auto size-9 text-n-slate-8" />
                    <p class="mt-2 font-semibold text-n-slate-11">Conversa encontrada</p>
                    <p class="mt-1 text-xs">Ainda não há mensagens de texto disponíveis para exibir.</p>
                  </div>
                </div>

                <div class="border-t border-n-weak bg-n-solid-2 p-4">
                  <div class="flex gap-4 border-b border-n-weak text-xs font-semibold">
                    <button class="border-b-2 border-blue-500 px-1 pb-2 text-blue-600">Responder</button>
                    <button class="px-1 pb-2 text-n-slate-9">Observação interna</button>
                  </div>
                  <div class="mt-3 flex items-end gap-2">
                    <textarea v-model="messageDraft" rows="3" class="min-h-20 flex-1 resize-none rounded-xl border border-n-weak bg-n-background p-3 text-sm text-n-slate-12" placeholder="Digite sua mensagem…" @keydown.ctrl.enter.prevent="sendConversationMessage" />
                    <button type="button" class="flex h-11 shrink-0 items-center gap-2 rounded-xl bg-[#087cf0] px-4 text-sm font-semibold text-white shadow-md disabled:opacity-40" :disabled="!messageDraft.trim() || !activeConversation || messageSending" title="Enviar mensagem" @click="sendConversationMessage">
                      <i :class="messageSending ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-send'" class="size-5" />
                      Enviar
                    </button>
                  </div>
                </div>
              </div>

              <div v-else class="grid flex-1 place-content-center rounded-2xl border border-dashed border-n-weak bg-n-alpha-2 text-center">
                <span class="i-lucide-message-square-dashed mx-auto size-9 text-n-slate-8" />
                <p class="mt-2 text-sm font-semibold text-n-slate-11">Nenhuma conversa encontrada</p>
                <p class="mt-1 text-xs text-n-slate-9">Você ainda pode ligar para este contato pelo painel da direita.</p>
              </div>
            </div>
          </div>
        </div>
      </main>

      <aside class="space-y-3 overflow-y-auto xl:h-full xl:min-h-0">
        <section class="overflow-hidden rounded-[22px] border border-n-weak bg-n-solid-2 shadow-sm">
          <div class="flex items-center justify-between bg-emerald-500 px-5 py-3 text-white"><div class="flex items-center gap-2 font-semibold"><span class="i-ri-whatsapp-fill size-6" />WhatsApp Calling</div><span class="rounded-full bg-emerald-700/40 px-3 py-1 text-xs">{{ callStatusLabel }}</span></div>
          <div class="p-5">
            <div class="flex items-center justify-between gap-4"><div class="flex min-w-0 items-center gap-3"><span class="flex size-12 items-center justify-center rounded-full bg-emerald-500/10 text-lg font-bold text-emerald-700">{{ currentContact ? (currentContact.name || 'C').slice(0, 1).toUpperCase() : 'WA' }}</span><div><h2 class="truncate text-lg font-semibold text-n-slate-12">{{ currentContact?.name || 'Telefone WhatsApp' }}</h2><p class="text-xs text-n-slate-9">{{ currentContactNumber || destination || 'Selecione um contato ou abra o teclado' }}</p></div></div><div class="text-right"><strong v-if="activeWhatsappCall" class="text-2xl text-n-slate-12">{{ formattedCallDuration }}</strong><span v-else class="i-lucide-phone size-7 text-emerald-500" /><p class="mt-1 text-xs text-emerald-600">{{ phoneReadyLabel }}</p></div></div>
            <div class="mt-4 grid grid-cols-2 gap-3">
              <button v-if="!incomingWhatsappCall && !activeWhatsappCall" type="button" style="background-color:#22c55e;color:#ffffff;border:1px solid #16a34a;" class="rounded-xl px-2 py-3 text-xs font-semibold shadow-sm disabled:cursor-not-allowed disabled:opacity-40" :disabled="!canCall" @click="startCall"><span class="i-lucide-phone-outgoing mx-auto mb-1 block size-5" />Ligar</button>
              <button v-if="incomingWhatsappCall && !activeWhatsappCall" type="button" class="rounded-xl bg-[#087cf0] px-2 py-3 text-xs font-semibold text-white shadow-sm disabled:cursor-not-allowed disabled:opacity-40" :disabled="!canAnswerCall" @click="answerIncomingCall"><span class="i-lucide-phone-call mx-auto mb-1 block size-5" />Atender</button>
              <button type="button" style="background-color:#f59e0b;color:#ffffff;border:1px solid #d97706;" class="rounded-xl px-2 py-3 text-xs font-semibold shadow-sm" @click="showCallKeypad = !showCallKeypad"><span class="i-lucide-grid-3x3 mx-auto mb-1 block size-5" />{{ showCallKeypad ? 'Ocultar teclado' : 'Teclado' }}</button>
            </div>
            <p v-if="!configuration.active || !hasWhatsappInbox" class="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-[11px] text-amber-800">O telefone permanece disponível na interface, mas as chamadas reais exigem uma configuração ativa do WhatsApp Calling e uma caixa WhatsApp compatível.</p>

            <div v-if="showCallKeypad" class="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3">
              <div class="mb-3 grid gap-2" :class="whatsappVoiceInboxes.length > 1 ? 'grid-cols-[1fr_140px]' : 'grid-cols-1'">
                <input v-model="destination" type="tel" inputmode="tel" :disabled="isBusy" placeholder="Número do WhatsApp" class="h-10 rounded-lg border border-amber-200 bg-white px-3 text-sm font-semibold text-n-slate-12 outline-none focus:border-amber-500" />
                <select v-if="whatsappVoiceInboxes.length > 1" v-model="selectedInboxId" class="h-10 rounded-lg border border-amber-200 bg-white px-2 text-xs text-n-slate-11"><option v-for="inbox in whatsappVoiceInboxes" :key="inbox.id" :value="inbox.id">{{ inbox.name }}</option></select>
              </div>
              <div class="grid grid-cols-3 gap-2"><button v-for="key in KEYPAD_KEYS" :key="`call-${key.value}`" type="button" class="rounded-lg bg-white py-2 text-sm font-bold text-n-slate-12 shadow-sm disabled:opacity-40" :disabled="isBusy" @click="pressKey(key.value)">{{ key.value }}<small class="ml-1 text-[8px] font-normal text-n-slate-8">{{ key.letters }}</small></button></div>
              <div v-if="hasValidDestination" class="mt-3 rounded-lg bg-white/80 p-2 text-center"><p class="text-[11px] text-n-slate-9">{{ permissionMessage }}</p><div class="mt-2 flex justify-center gap-2"><button v-if="permission.status !== 'approved'" type="button" class="rounded-lg border border-n-weak bg-white px-3 py-1.5 text-[11px] font-semibold" :disabled="!canCheckPermission" @click="checkPermission">Verificar permissão</button><button v-if="canRequestPermission" type="button" class="rounded-lg bg-emerald-500 px-3 py-1.5 text-[11px] font-semibold text-white" :disabled="permissionLoading" @click="requestPermission">Solicitar permissão</button></div></div>
            </div>

            <button v-if="currentWhatsappCall" type="button" class="mt-3 w-full rounded-xl bg-red-500 py-3 text-sm font-semibold text-white shadow-sm disabled:opacity-40" :disabled="!canEndCall" @click="endCall"><span class="i-lucide-phone-off me-1 inline-block size-4 align-text-bottom" />Encerrar chamada</button>
          </div>
        </section>

        <section class="rounded-[22px] border border-n-weak bg-n-solid-2 p-4 shadow-sm">
          <div class="flex items-center justify-between"><h3 class="font-semibold text-n-slate-12">Informações do cliente e negócio</h3><span class="text-xs font-semibold text-blue-600">Ver no CRM ↗</span></div>
          <div class="mt-3 grid grid-cols-3 gap-2 rounded-xl border border-n-weak bg-n-alpha-2 p-3 text-xs"><div><span class="text-n-slate-8">Negócio</span><strong class="mt-1 block text-n-slate-12">{{ currentContact ? 'Relacionamento ativo' : '—' }}</strong></div><div><span class="text-n-slate-8">Valor</span><strong class="mt-1 block text-emerald-600">CRM</strong></div><div><span class="text-n-slate-8">Etapa</span><strong class="mt-1 block text-n-slate-12">Atendimento</strong></div></div>
        </section>

        <section class="rounded-[22px] border border-n-weak bg-n-solid-2 p-4 shadow-sm">
          <div class="flex items-center justify-between"><div><h3 class="font-semibold text-n-slate-12">IA de sentimento</h3><p class="text-xs text-n-slate-9">Escuta e resumo da chamada</p></div><span class="rounded-full px-2.5 py-1 text-[11px] font-semibold" :class="activeWhatsappCall ? 'bg-emerald-500/10 text-emerald-700' : 'bg-n-alpha-2 text-n-slate-9'">{{ activeWhatsappCall ? 'Preparada para análise' : 'Aguardando chamada' }}</span></div>
          <div class="mt-3 grid grid-cols-3 gap-2 text-center"><div class="rounded-xl bg-emerald-500/5 p-3"><span class="i-lucide-smile mx-auto block size-5 text-emerald-500" /><strong class="mt-1 block text-xs text-n-slate-12">Sentimento</strong><small class="text-n-slate-9">Aguardando</small></div><div class="rounded-xl bg-blue-500/5 p-3"><span class="i-lucide-message-square-text mx-auto block size-5 text-blue-500" /><strong class="mt-1 block text-xs text-n-slate-12">Resumo</strong><small class="text-n-slate-9">Após áudio</small></div><div class="rounded-xl bg-amber-500/5 p-3"><span class="i-lucide-triangle-alert mx-auto block size-5 text-amber-500" /><strong class="mt-1 block text-xs text-n-slate-12">Risco</strong><small class="text-n-slate-9">Sem alerta</small></div></div>
          <textarea rows="3" class="mt-3 w-full resize-none rounded-xl border border-n-weak bg-n-background p-3 text-xs text-n-slate-10" placeholder="Anotações em tempo real e resumo da IA aparecerão aqui." />
          <div class="mt-2 flex items-center justify-between text-[11px] text-n-slate-9"><span class="flex items-center gap-1"><span class="i-lucide-circle-check size-3 text-emerald-500" />Integração preparada com Voice Quality</span><button type="button" class="rounded-lg border border-blue-500 px-3 py-1.5 font-semibold text-blue-600">Gerar resumo com IA</button></div>
        </section>

        <section class="rounded-[22px] border border-n-weak bg-n-solid-2 p-4 shadow-sm">
          <div class="flex items-center justify-between"><h3 class="font-semibold text-n-slate-12">Histórico de chamadas</h3><button class="text-n-slate-9" :disabled="historyLoading" @click="loadHistory"><span class="i-lucide-refresh-cw size-4" :class="historyLoading ? 'animate-spin' : ''" /></button></div>
          <div class="mt-3 grid grid-cols-3 gap-2"><div class="rounded-xl border border-n-weak p-3"><strong class="text-xl text-n-slate-12">{{ historyStats.total }}</strong><small class="mt-1 block text-n-slate-9">Total</small></div><div class="rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-3"><strong class="text-xl text-n-slate-12">{{ historyStats.answered }}</strong><small class="mt-1 block text-n-slate-9">Atendidas</small></div><div class="rounded-xl border border-red-500/30 bg-red-500/5 p-3"><strong class="text-xl text-n-slate-12">{{ historyStats.missed }}</strong><small class="mt-1 block text-n-slate-9">Não atendidas</small></div></div>
          <div class="mt-3 flex gap-2"><button v-for="period in [1, 7, 30]" :key="period" type="button" class="rounded-lg px-3 py-1.5 text-xs font-semibold" :class="historyPeriod === period ? 'bg-blue-500 text-white' : 'bg-n-alpha-2 text-n-slate-10'" @click="historyPeriod = period">{{ period === 1 ? 'Hoje' : `${period} dias` }}</button></div>
          <div v-if="historyCalls.length" class="mt-3 max-h-44 divide-y divide-n-weak overflow-y-auto rounded-xl border border-n-weak"><div v-for="call in historyCalls" :key="call.id" class="flex items-center gap-3 p-3"><span class="i-ri-whatsapp-fill size-4 text-emerald-500" /><div class="min-w-0 flex-1"><p class="truncate text-xs font-semibold text-n-slate-12">{{ call.contact.name || call.contact.phoneNumber }}</p><p class="text-[11px] text-n-slate-9">{{ callSummary(call) }}</p></div><time class="text-[10px] text-n-slate-8">{{ formatCallDate(call.createdAt) }}</time></div></div>
          <div v-else class="mt-3 rounded-xl border border-dashed border-n-weak p-5 text-center text-xs text-n-slate-9">Nenhuma chamada disponível para os filtros selecionados.</div>
        </section>
      </aside>
    </div>
  </section>
</template>

