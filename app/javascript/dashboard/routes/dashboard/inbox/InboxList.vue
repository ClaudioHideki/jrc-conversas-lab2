<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { hasPermissions } from 'dashboard/helper/permissionsHelper';
import {
  CHANNEL_TYPES,
  getInboxChannelKey,
  INBOX_CHANNEL_PRESENTATION,
} from 'dashboard/helper/inbox';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import ConversationAPI from 'dashboard/api/conversations';

import HoyaInboxWorkspace from './HoyaInboxWorkspace.vue';
import {
  ASSIGNEE_FILTERS,
  matchesAssigneeFilter,
  canManageAssigneeFilters,
  assigneeFilterOptions as buildAssigneeFilterOptions,
  resolveAssigneeFilter as resolveAssigneeFilterValue,
} from './omnichannelFilters';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const page = ref(1);
const resolveStatus = value =>
  ['open', 'pending', 'all'].includes(value)
    ? value
    : wootConstants.STATUS_TYPE.OPEN;
const statusFilter = ref(resolveStatus(route.query.status));
const channelFilter = ref(route.query.channel || 'all');
const assigneeFilter = ref(ASSIGNEE_FILTERS.ME);
const sharedScope = ref({ enabled: false, inbox_ids: [] });
const admittedSharedConversations = ref(new Set());
const supervisedInboxIds = ref([]);
const voiceCalls = ref([]);
const voiceLoading = ref(false);
const contactCenterContext = ref(null);
const voiceError = ref(false);
const isInitializing = ref(true);
let accountGeneration = 0;
let voiceGeneration = 0;
let sharingGeneration = 0;
let listGeneration = 0;
const listRequests = ref(0);
let sharingRequest = false;
let sharingDirty = false;
let sharingTimer;

const accountId = computed(() => Number(route.params.accountId));
const currentUser = useMapGetter('getCurrentUser');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const inboxById = useMapGetter('inboxes/getInboxById');
const allStatusConversations = useMapGetter('getAllStatusChats');
const isLoading = useMapGetter('getChatListLoadingStatus');
const conversationError = useMapGetter('getChatListErrorStatus');
const hasEndReached = useMapGetter('conversationPage/getHasEndReached');
const isFeatureEnabledOnAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const currentAccount = computed(() =>
  currentUser.value?.accounts?.find(
    account => Number(account.id) === accountId.value
  )
);

const accountPermissions = computed(
  () => currentAccount.value?.permissions || []
);
// SIP already has its own authorized route and credential checks. Its central
// presentation must not depend on enabling the external Contact Center API.
const hasSoftphoneAccess = computed(
  () =>
    Boolean(currentAccount.value) &&
    hasPermissions(
      router.resolve({
        name: 'ramal_index',
        params: { accountId: accountId.value },
      }).meta.permissions,
      accountPermissions.value
    )
);

const canManageAssignments = computed(
  () =>
    supervisedInboxIds.value.length > 0 ||
    canManageAssigneeFilters({
      role: store.getters.getCurrentRole,
      customRoleId: store.getters.getCurrentCustomRoleId,
      permissions: accountPermissions.value,
    })
);

const hasContactCenter = computed(
  () =>
    isFeatureEnabledOnAccount.value(
      accountId.value,
      FEATURE_FLAGS.JRC_CONTACT_CENTER
    ) === true &&
    accountPermissions.value.some(permission =>
      ['administrator', 'agent', 'jrc_contact_center_view'].includes(permission)
    )
);

const assigneeFilterOptions = computed(() =>
  buildAssigneeFilterOptions(
    canManageAssignments.value,
    sharedScope.value.enabled
  ).map(option => ({
    ...option,
    label: {
      me: t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ME'),
      mine_or_shared: t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.MINE_OR_SHARED'),
      unassigned: t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.UNASSIGNED'),
      all: t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ALL'),
    }[option.key],
  }))
);

const resolveAssigneeFilter = value =>
  resolveAssigneeFilterValue(
    value,
    canManageAssignments.value,
    sharedScope.value.enabled
  );

const statusFilterOptions = computed(() => [
  { key: 'open', label: t('JRC_CONTACT_CENTER.INBOX.STATUSES.OPEN') },
  { key: 'pending', label: t('JRC_CONTACT_CENTER.INBOX.STATUSES.PENDING') },
  { key: 'all', label: t('JRC_CONTACT_CENTER.INBOX.STATUSES.ALL') },
]);

const conversationFilters = computed(() => ({
  assigneeType: assigneeFilter.value,
  includeParticipating: true,
  status: statusFilter.value,
  sortBy: wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC,
  page: page.value,
}));

// Only preserve rows whose access-relevant identity was already checked. A new
// realtime row or changed assignment must wait for the next authoritative scope.
const sharingIdentity = conversation =>
  JSON.stringify([
    conversation.id,
    conversation.inbox_id,
    conversation.meta?.assignee?.id,
    conversation.meta?.assignee_type,
    conversation.meta?.team?.id,
  ]);

const acceptSharedScope = scope => {
  supervisedInboxIds.value = Array.isArray(scope?.supervised_inbox_ids)
    ? scope.supervised_inbox_ids.filter(
        id => Number.isSafeInteger(id) && id > 0
      )
    : [];
  const valid =
    scope?.enabled === true &&
    Array.isArray(scope.inbox_ids) &&
    scope.inbox_ids.every(id => Number.isInteger(id) && id > 0);
  sharedScope.value = valid ? scope : { enabled: false, inbox_ids: [] };
  admittedSharedConversations.value = new Set(
    valid
      ? allStatusConversations
          .value({ status: statusFilter.value })
          .filter(conversation =>
            scope.inbox_ids.includes(conversation.inbox_id)
          )
          .map(sharingIdentity)
      : []
  );
  if (!valid && assigneeFilter.value === ASSIGNEE_FILTERS.MINE_OR_SHARED) {
    assigneeFilter.value = ASSIGNEE_FILTERS.ME;
    store.dispatch('updateChatListFilters', conversationFilters.value);
  }
};

const socialChannelKeys = [
  CHANNEL_TYPES.FACEBOOK,
  CHANNEL_TYPES.INSTAGRAM,
  CHANNEL_TYPES.TIKTOK,
];

const configuredChannelKeys = computed(() => [
  ...new Set((inboxes.value || []).map(getInboxChannelKey)),
]);

const hasSocialChannels = computed(() =>
  configuredChannelKeys.value.some(key => socialChannelKeys.includes(key))
);

const individualChannelKeys = computed(() =>
  configuredChannelKeys.value.filter(key => !socialChannelKeys.includes(key))
);

const channelFilterOptions = computed(() => [
  {
    key: 'all',
    label: t('JRC_CONTACT_CENTER.INBOX.CHANNELS.ALL'),
    icon: 'i-lucide-inbox',
    iconClass: 'text-n-blue-10',
  },
  ...(hasContactCenter.value || hasSoftphoneAccess.value
    ? [
        {
          key: 'voice',
          label: t('JRC_CONTACT_CENTER.INBOX.CHANNELS.VOICE'),
          icon: 'i-lucide-phone-call',
          iconClass: 'text-n-teal-10',
        },
      ]
    : []),
  ...(hasSocialChannels.value
    ? [
        {
          key: 'social',
          label: t('JRC_CONTACT_CENTER.INBOX.CHANNELS.SOCIAL'),
          icon: 'i-lucide-share-2',
          iconClass: 'text-n-ruby-10',
        },
      ]
    : []),
  ...individualChannelKeys.value.map(key => ({
    key,
    ...(INBOX_CHANNEL_PRESENTATION[key] || INBOX_CHANNEL_PRESENTATION.api),
  })),
]);

const conversations = computed(() => {
  const items = allStatusConversations
    .value({
      assigneeType: assigneeFilter.value,
      status: statusFilter.value,
    })
    .filter(conversation =>
      inboxes.value.some(
        inbox => Number(inbox.id) === Number(conversation.inbox_id)
      )
    )
    .filter(conversation =>
      matchesAssigneeFilter(
        conversation,
        assigneeFilter.value,
        currentUser.value?.id,
        admittedSharedConversations.value.has(sharingIdentity(conversation))
          ? sharedScope.value.inbox_ids
          : []
      )
    );

  if (channelFilter.value === 'all') return items;
  if (channelFilter.value === 'voice') return [];

  return items.filter(conversation => {
    const inbox = inboxById.value(conversation.inbox_id);
    const channelKey = getInboxChannelKey(inbox);
    if (channelFilter.value === 'social') {
      return socialChannelKeys.includes(channelKey);
    }
    return channelKey === channelFilter.value;
  });
});

const currentConversationId = computed(() =>
  route.params.type === 'conversation' ? Number(route.params.id) : null
);
const currentCallId = computed(() =>
  route.params.type === 'call' ? Number(route.params.id) : null
);
const isCurrentListLoading = computed(() =>
  channelFilter.value === 'voice'
    ? voiceLoading.value
    : isLoading.value ||
      listRequests.value > 0 ||
      (channelFilter.value === 'all' && voiceLoading.value)
);

const canLoadMore = computed(
  () =>
    channelFilter.value !== 'voice' &&
    !listRequests.value &&
    !isLoading.value &&
    !conversationError.value &&
    !hasEndReached.value(assigneeFilter.value)
);

// Keep admitted rows stable while refreshing. New rows remain fenced until the
// response, and errors/revocations still remove the grant. Coalesce event bursts.
const refreshSharedScope = async () => {
  if (
    isInitializing.value ||
    assigneeFilter.value !== ASSIGNEE_FILTERS.MINE_OR_SHARED
  )
    return;
  sharingGeneration += 1;
  const request = sharingGeneration;
  const generation = accountGeneration;
  if (document.visibilityState === 'hidden') return;
  if (sharingRequest || listRequests.value) {
    sharingDirty = true;
    return;
  }
  sharingRequest = true;
  sharingDirty = false;
  try {
    const response = await ConversationAPI.sharedContext(accountId.value);
    if (request === sharingGeneration && generation === accountGeneration)
      acceptSharedScope(response.data?.meta?.shared_scope);
  } catch {
    if (request === sharingGeneration && generation === accountGeneration)
      acceptSharedScope(null);
  } finally {
    sharingRequest = false;
    if (sharingDirty) refreshSharedScope();
  }
};

const fetchConversations = async ({ reset = false } = {}) => {
  listGeneration += 1;
  const request = listGeneration;
  sharingGeneration += 1;
  if (reset) {
    page.value = 1;
    store.dispatch('conversationPage/reset');
    store.dispatch('emptyAllConversations');
  }
  store.dispatch('updateChatListFilters', conversationFilters.value);
  const generation = accountGeneration;
  listRequests.value += 1;
  try {
    const data = await store.dispatch('fetchAllConversations');
    if (
      generation === accountGeneration &&
      request === listGeneration &&
      (data?.meta?.shared_scope ||
        assigneeFilter.value === ASSIGNEE_FILTERS.MINE_OR_SHARED)
    ) {
      acceptSharedScope(data?.meta?.shared_scope);
    }
  } finally {
    if (generation === accountGeneration) {
      listRequests.value -= 1;
      if (!listRequests.value && sharingDirty) refreshSharedScope();
    }
  }
};

const fetchVoiceCalls = async () => {
  voiceGeneration += 1;
  const version = voiceGeneration;
  voiceError.value = false;
  if (!hasContactCenter.value) {
    voiceCalls.value = [];
    contactCenterContext.value = null;
    voiceLoading.value = false;
    return;
  }

  voiceLoading.value = true;
  try {
    const [callsResponse, contextResponse] = await Promise.all([
      JrcContactCenterAPI.calls(accountId.value, {
        limit: 50,
        assignee_type:
          assigneeFilter.value === ASSIGNEE_FILTERS.MINE_OR_SHARED
            ? ASSIGNEE_FILTERS.ME
            : assigneeFilter.value,
      }),
      JrcContactCenterAPI.context(accountId.value),
    ]);
    if (version !== voiceGeneration) return;
    voiceCalls.value = callsResponse.data.items || [];
    contactCenterContext.value = contextResponse.data;
  } catch {
    if (version === voiceGeneration) {
      voiceCalls.value = [];
      contactCenterContext.value = null;
      voiceError.value = true;
    }
  } finally {
    if (version === voiceGeneration) voiceLoading.value = false;
  }
};

const replaceInboxRoute = query =>
  router.replace({
    name: 'inbox_view',
    params: { accountId: route.params.accountId },
    query,
  });

const setChannelFilter = async key => {
  channelFilter.value = key;
  await replaceInboxRoute({
    ...route.query,
    channel: key === 'all' ? undefined : key,
    assignee: assigneeFilter.value,
  });
};

const setAssigneeFilter = async key => {
  const resolved = resolveAssigneeFilter(key);
  if (resolved === assigneeFilter.value) return;

  assigneeFilter.value = resolved;
  await replaceInboxRoute({
    ...route.query,
    assignee: resolved,
    channel: channelFilter.value === 'all' ? undefined : channelFilter.value,
  });
};

const setStatusFilter = async key => {
  const resolved = resolveStatus(key);
  if (resolved === statusFilter.value) return;
  statusFilter.value = resolved;
  await replaceInboxRoute({
    ...route.query,
    status: resolved === wootConstants.STATUS_TYPE.OPEN ? undefined : resolved,
  });
};

const openConversation = conversation => {
  if (currentConversationId.value === conversation.id) return;
  router.push({
    name: 'inbox_view_conversation',
    params: {
      accountId: route.params.accountId,
      type: 'conversation',
      id: conversation.id,
    },
    query: route.query,
  });
};

const openVoiceCall = call => {
  if (currentCallId.value === call.id) return;
  router.push({
    name: 'inbox_view_conversation',
    params: {
      accountId: route.params.accountId,
      type: 'call',
      id: call.id,
    },
    query: route.query,
  });
};

const loadMore = async () => {
  if (!canLoadMore.value || listRequests.value) return;
  page.value += 1;
  await fetchConversations();
};

const inboxFor = conversation => inboxById.value(conversation.inbox_id) || {};

watch(
  () => route.query.channel,
  key => {
    const available = channelFilterOptions.value.some(
      option => option.key === key
    );
    channelFilter.value = available ? key : 'all';
  }
);

watch(
  [
    () => JSON.stringify(inboxes.value),
    () =>
      allStatusConversations
        .value({ status: statusFilter.value })
        .map(conversation =>
          [
            conversation.id,
            conversation.inbox_id,
            conversation.updated_at,
            conversation.status,
            conversation.meta?.assignee?.id,
            conversation.meta?.assignee_type,
            conversation.meta?.team?.id,
          ].join(':')
        )
        .join('|'),
  ],
  refreshSharedScope
);

onMounted(() => {
  // Broker automation changes need not emit a local inbox event. Bound freshness while visible.
  sharingTimer = setInterval(refreshSharedScope, 15000);
  document.addEventListener('visibilitychange', refreshSharedScope);
});

watch(
  [
    accountId,
    () => route.query.assignee,
    () => route.query.status,
    canManageAssignments,
    () => store.getters.getCurrentCustomRoleId,
    () => accountPermissions.value.join(','),
    hasContactCenter,
  ],
  async () => {
    accountGeneration += 1;
    listRequests.value = 0;
    sharingGeneration += 1;
    sharingDirty = false;
    const version = accountGeneration;
    isInitializing.value = true;
    voiceGeneration += 1;
    page.value = 1;
    statusFilter.value = resolveStatus(route.query.status);
    // Invalidate the previous request key and end marker before awaiting routing metadata.
    store.dispatch('updateChatListFilters', conversationFilters.value);
    store.dispatch('conversationPage/reset');
    voiceCalls.value = [];
    contactCenterContext.value = null;
    voiceError.value = false;
    sharedScope.value = { enabled: false, inbox_ids: [] };
    admittedSharedConversations.value = new Set();
    store.dispatch('clearSelectedState');
    store.dispatch('emptyAllConversations');

    if (!inboxes.value?.length) await store.dispatch('inboxes/get');
    if (version !== accountGeneration) return;

    try {
      const response = await ConversationAPI.sharedContext(accountId.value);
      if (version !== accountGeneration) return;
      acceptSharedScope(response.data?.meta?.shared_scope);
    } catch {
      // Keep the individual scope when a fresh routing snapshot is unavailable.
    }
    if (version !== accountGeneration) return;

    assigneeFilter.value = resolveAssigneeFilter(route.query.assignee);
    channelFilter.value = channelFilterOptions.value.some(
      option => option.key === route.query.channel
    )
      ? route.query.channel
      : 'all';

    await Promise.all([
      fetchConversations({ reset: true }).finally(() => {
        if (version === accountGeneration) isInitializing.value = false;
      }),
      fetchVoiceCalls(),
    ]);
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  accountGeneration += 1;
  voiceGeneration += 1;
  sharingGeneration += 1;
  listGeneration += 1;
  sharingDirty = false;
  clearInterval(sharingTimer);
  document.removeEventListener('visibilitychange', refreshSharedScope);
});
</script>

<template>
  <HoyaInboxWorkspace
    :key="accountId"
    :account-id="accountId"
    :calls="voiceCalls"
    :conversations="conversations"
    :channels="channelFilterOptions"
    :assignees="assigneeFilterOptions"
    :assignee-filter="assigneeFilter"
    :statuses="statusFilterOptions"
    :status-filter="statusFilter"
    :channel-filter="channelFilter"
    :current-call-id="currentCallId"
    :current-conversation-id="currentConversationId"
    :inbox-for="inboxFor"
    :context="contactCenterContext"
    :loading="isCurrentListLoading"
    :ready="!isInitializing"
    :softphone-access="hasSoftphoneAccess"
    :voice-error="voiceError"
    :conversation-error="channelFilter !== 'voice' && conversationError"
    :can-load-more="canLoadMore"
    @select-call="openVoiceCall"
    @select-conversation="openConversation"
    @channel-change="setChannelFilter"
    @assignee-change="setAssigneeFilter"
    @status-change="setStatusFilter"
    @load-more="loadMore"
    @refresh="fetchVoiceCalls"
    @retry-conversations="fetchConversations({ reset: true })"
  />
</template>
