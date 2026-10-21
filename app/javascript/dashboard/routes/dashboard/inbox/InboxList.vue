<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  CHANNEL_TYPES,
  getInboxChannelKey,
  INBOX_CHANNEL_PRESENTATION,
} from 'dashboard/helper/inbox';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';

import ConversationCard from 'dashboard/components/widgets/conversation/ConversationCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CallWorkspace from 'dashboard/routes/dashboard/jrcContactCenter/views/CallWorkspace.vue';
import HoyaInboxWorkspace from './HoyaInboxWorkspace.vue';
import {
  ASSIGNEE_FILTERS,
  canManageAssigneeFilters,
  assigneeFilterOptions as buildAssigneeFilterOptions,
  resolveAssigneeFilter as resolveAssigneeFilterValue,
} from './omnichannelFilters';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const page = ref(1);
const channelFilter = ref(route.query.channel || 'all');
const assigneeFilter = ref(ASSIGNEE_FILTERS.ME);
const isListExpanded = ref(false);
const voiceCalls = ref([]);
const voiceLoading = ref(false);
const contactCenterContext = ref(null);
const voiceError = ref(false);
const isInitializing = ref(true);
let accountGeneration = 0;
let voiceGeneration = 0;

const accountId = computed(() => Number(route.params.accountId));
const currentUser = useMapGetter('getCurrentUser');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const inboxById = useMapGetter('inboxes/getInboxById');
const allOpenConversations = useMapGetter('getAllStatusChats');
const isLoading = useMapGetter('getChatListLoadingStatus');
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

const canManageAssignments = computed(() =>
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
  buildAssigneeFilterOptions(canManageAssignments.value).map(option => ({
    ...option,
    label: {
      me: t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ME'),
      unassigned: t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.UNASSIGNED'),
      all: t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ALL'),
    }[option.key],
  }))
);

const resolveAssigneeFilter = value =>
  resolveAssigneeFilterValue(value, canManageAssignments.value);

const conversationFilters = computed(() => ({
  assigneeType: assigneeFilter.value,
  status: wootConstants.STATUS_TYPE.OPEN,
  sortBy: wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC,
  page: page.value,
}));

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
  ...(hasContactCenter.value
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
  const items = allOpenConversations.value({
    assigneeType: assigneeFilter.value,
    status: wootConstants.STATUS_TYPE.OPEN,
  });

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
const visibleItemCount = computed(
  () =>
    conversations.value.length +
    (['all', 'voice'].includes(channelFilter.value)
      ? voiceCalls.value.length
      : 0)
);
const inboxDescription = computed(
  () =>
    ({
      me: t('JRC_CONTACT_CENTER.INBOX.DESCRIPTIONS.ME'),
      unassigned: t('JRC_CONTACT_CENTER.INBOX.DESCRIPTIONS.UNASSIGNED'),
      all: t('JRC_CONTACT_CENTER.INBOX.DESCRIPTIONS.ALL'),
    })[assigneeFilter.value]
);
const isCurrentListLoading = computed(() =>
  channelFilter.value === 'voice'
    ? voiceLoading.value
    : isLoading.value || (channelFilter.value === 'all' && voiceLoading.value)
);

const asideWidthClass = computed(() =>
  isListExpanded.value
    ? 'lg:w-[48%] lg:min-w-[520px] lg:max-w-[680px] xl:w-[50%] xl:min-w-[600px] xl:max-w-[760px]'
    : 'lg:w-[40%] lg:min-w-[420px] lg:max-w-[500px] xl:w-[38%] xl:min-w-[460px] xl:max-w-[580px] 2xl:max-w-[640px]'
);
const layoutToggleTitle = computed(() =>
  isListExpanded.value
    ? t('JRC_CONTACT_CENTER.INBOX.COLLAPSE_LIST')
    : t('JRC_CONTACT_CENTER.INBOX.EXPAND_LIST')
);
const canLoadMore = computed(
  () =>
    channelFilter.value !== 'voice' &&
    !isLoading.value &&
    !hasEndReached.value(assigneeFilter.value)
);

const fetchConversations = async ({ reset = false } = {}) => {
  if (reset) {
    page.value = 1;
    store.dispatch('conversationPage/reset');
    store.dispatch('emptyAllConversations');
  }
  store.dispatch('updateChatListFilters', conversationFilters.value);
  await store.dispatch('fetchAllConversations');
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
        assignee_type: assigneeFilter.value,
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
  if (!canLoadMore.value) return;
  page.value += 1;
  await fetchConversations();
};

const contactFor = conversation => conversation.meta?.sender || {};
const assigneeFor = conversation => conversation.meta?.assignee || {};
const inboxFor = conversation => inboxById.value(conversation.inbox_id) || {};
const channelToneClass = option => {
  const tones = {
    all: 'border-n-blue-6 bg-n-blue-3 text-n-blue-11',
    voice: 'border-n-teal-7 bg-n-teal-3 text-n-teal-11',
    social: 'border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11',
    [CHANNEL_TYPES.WHATSAPP]: 'border-n-teal-7 bg-n-teal-3 text-n-teal-11',
    [CHANNEL_TYPES.FACEBOOK]: 'border-n-blue-7 bg-n-blue-3 text-n-blue-11',
    [CHANNEL_TYPES.INSTAGRAM]: 'border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11',
    [CHANNEL_TYPES.EMAIL]: 'border-n-blue-7 bg-n-blue-3 text-n-blue-11',
    [CHANNEL_TYPES.API]: 'border-n-amber-7 bg-n-amber-3 text-n-amber-11',
    [CHANNEL_TYPES.SMS]: 'border-n-violet-7 bg-n-violet-3 text-n-violet-11',
    [CHANNEL_TYPES.WEBSITE]: 'border-n-slate-7 bg-n-slate-3 text-n-slate-11',
    [CHANNEL_TYPES.TELEGRAM]: 'border-n-blue-7 bg-n-blue-3 text-n-blue-11',
    [CHANNEL_TYPES.LINE]: 'border-n-teal-7 bg-n-teal-3 text-n-teal-11',
    [CHANNEL_TYPES.TIKTOK]: 'border-n-slate-7 bg-n-slate-3 text-n-slate-12',
  };
  return tones[option.key] || 'border-n-weak bg-n-alpha-2 text-n-slate-11';
};
const filterButtonClass = option =>
  channelFilter.value === option.key
    ? `${channelToneClass(option)} shadow-sm`
    : 'border-transparent text-n-slate-11 hover:border-n-weak hover:bg-n-alpha-2 hover:text-n-slate-12';
const filterIconClass = option =>
  channelFilter.value === option.key
    ? ''
    : option.iconClass || 'text-n-slate-10';
const callDirectionLabel = call =>
  call.direction === 'outbound'
    ? t('JRC_CONTACT_CENTER.INBOX.DIRECTIONS.OUTBOUND')
    : t('JRC_CONTACT_CENTER.INBOX.DIRECTIONS.INBOUND');
const callIdentifier = call => call.ani || call.dnis || `#${call.id}`;
const callTime = call => {
  const value = call.started_at || call.answered_at;
  if (!value) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
};

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
    accountId,
    () => route.query.assignee,
    canManageAssignments,
    hasContactCenter,
  ],
  async () => {
    accountGeneration += 1;
    const version = accountGeneration;
    isInitializing.value = true;
    voiceGeneration += 1;
    page.value = 1;
    voiceCalls.value = [];
    contactCenterContext.value = null;
    voiceError.value = false;
    store.dispatch('clearSelectedState');
    store.dispatch('emptyAllConversations');

    if (!inboxes.value?.length) await store.dispatch('inboxes/get');
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
});
</script>

<template>
  <HoyaInboxWorkspace
    v-if="hasContactCenter"
    :key="accountId"
    :account-id="accountId"
    :calls="voiceCalls"
    :conversations="conversations"
    :channels="channelFilterOptions"
    :assignees="assigneeFilterOptions"
    :assignee-filter="assigneeFilter"
    :channel-filter="channelFilter"
    :current-call-id="currentCallId"
    :current-conversation-id="currentConversationId"
    :inbox-for="inboxFor"
    :context="contactCenterContext"
    :loading="isCurrentListLoading"
    :ready="!isInitializing"
    :voice-error="voiceError"
    :can-load-more="canLoadMore"
    @select-call="openVoiceCall"
    @select-conversation="openConversation"
    @channel-change="setChannelFilter"
    @assignee-change="setAssigneeFilter"
    @load-more="loadMore"
    @refresh="fetchVoiceCalls"
  />
  <section v-else class="flex h-full w-full bg-n-surface-1">
    <aside
      class="flex h-full w-full flex-col border-n-weak bg-n-solid-1 shadow-[6px_0_24px_rgba(8,43,82,0.04)] transition-[width,max-width,min-width] duration-200 ltr:border-r rtl:border-l"
      :class="[
        !currentConversationId && !currentCallId ? 'flex' : 'hidden xl:flex',
        asideWidthClass,
      ]"
    >
      <header class="border-b border-n-weak px-4 pb-3 pt-5">
        <div class="flex items-center justify-between gap-3">
          <div>
            <div class="flex items-center gap-2">
              <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
                {{ t('JRC_CONTACT_CENTER.INBOX.TITLE') }}
              </h1>
              <span
                class="rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-semibold text-n-blue-11"
              >
                {{ visibleItemCount }}
              </span>
            </div>
            <p class="mt-1 text-xs text-n-slate-10">
              {{ inboxDescription }}
            </p>
          </div>
          <div class="flex shrink-0 items-center gap-2">
            <button
              type="button"
              class="grid size-9 place-items-center rounded-lg border border-n-weak text-n-slate-11 transition hover:border-n-blue-7 hover:bg-n-alpha-2 hover:text-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
              :title="layoutToggleTitle"
              @click="isListExpanded = !isListExpanded"
            >
              <span
                class="size-4"
                :class="
                  isListExpanded
                    ? 'i-lucide-panel-left-close'
                    : 'i-lucide-panel-left-open'
                "
              />
            </button>
            <RouterLink
              :to="{ name: 'home' }"
              class="grid size-9 place-items-center rounded-lg border border-n-weak text-n-slate-11 transition hover:border-n-blue-7 hover:text-n-brand"
              :title="t('JRC_CONTACT_CENTER.INBOX.OPEN_CONVERSATION_HUB')"
            >
              <span class="i-lucide-messages-square size-4" />
            </RouterLink>
          </div>
        </div>
        <RouterLink
          :to="{ name: 'search' }"
          class="mt-4 flex h-10 items-center gap-2 rounded-xl border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-10 transition hover:border-n-blue-7"
        >
          <span class="i-lucide-search size-4" />
          <span>{{ t('JRC_CONTACT_CENTER.INBOX.SEARCH') }}</span>
        </RouterLink>
      </header>

      <nav
        class="flex gap-2 overflow-x-auto border-b border-n-weak px-3 py-3"
        :aria-label="t('JRC_CONTACT_CENTER.INBOX.ASSIGNEE_FILTER_LABEL')"
      >
        <button
          v-for="option in assigneeFilterOptions"
          :key="option.key"
          type="button"
          class="flex h-9 shrink-0 items-center gap-2 rounded-xl border px-3 text-xs font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :class="
            assigneeFilter === option.key
              ? 'border-n-blue-6 bg-n-blue-3 text-n-blue-11 shadow-sm'
              : 'border-transparent text-n-slate-11 hover:border-n-weak hover:bg-n-alpha-2'
          "
          :aria-pressed="assigneeFilter === option.key"
          @click="setAssigneeFilter(option.key)"
        >
          <span class="size-3.5" :class="option.icon" />
          {{ option.label }}
        </button>
      </nav>

      <nav
        class="flex gap-2 overflow-x-auto border-b border-n-weak px-3 py-3"
        :aria-label="t('JRC_CONTACT_CENTER.INBOX.CHANNEL_FILTER_LABEL')"
      >
        <button
          v-for="option in channelFilterOptions"
          :key="option.key"
          type="button"
          class="flex h-9 shrink-0 items-center gap-2 rounded-xl border px-3 text-xs font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :class="filterButtonClass(option)"
          :aria-pressed="channelFilter === option.key"
          @click="setChannelFilter(option.key)"
        >
          <span
            class="grid size-5 place-items-center rounded-lg"
            :class="
              channelFilter === option.key ? 'bg-n-solid-1/70' : 'bg-n-alpha-1'
            "
          >
            <span
              class="size-3.5"
              :class="[option.icon, filterIconClass(option)]"
            />
          </span>
          {{ option.label }}
        </button>
      </nav>

      <div class="min-h-0 flex-1 overflow-y-auto py-2">
        <template v-if="['all', 'voice'].includes(channelFilter)">
          <button
            v-for="call in voiceCalls"
            :key="call.id"
            type="button"
            class="flex w-full items-center gap-3 border-b border-n-weak px-4 py-4 text-left transition hover:bg-n-alpha-1"
            :class="currentCallId === call.id ? 'bg-n-blue-2' : ''"
            @click="openVoiceCall(call)"
          >
            <span
              class="grid size-11 shrink-0 place-items-center rounded-2xl bg-n-teal-3 text-n-teal-11"
            >
              <span
                class="size-5"
                :class="
                  call.direction === 'outbound'
                    ? 'i-lucide-phone-outgoing'
                    : 'i-lucide-phone-incoming'
                "
              />
            </span>
            <span class="min-w-0 flex-1">
              <span
                class="block break-words text-sm font-semibold text-n-slate-12"
              >
                {{ callIdentifier(call) }}
              </span>
              <span class="mt-1 block break-words text-xs text-n-slate-10">
                {{
                  t('JRC_CONTACT_CENTER.COMMON.CODE_DETAIL', {
                    code: callDirectionLabel(call),
                    detail: callTime(call),
                  })
                }}
              </span>
            </span>
            <span
              class="rounded-full bg-n-alpha-2 px-2.5 py-1 text-[10px] font-semibold uppercase text-n-slate-10"
            >
              {{ call.status }}
            </span>
          </button>
        </template>

        <template v-if="channelFilter !== 'voice'">
          <ConversationCard
            v-for="conversation in conversations"
            :key="conversation.id"
            :chat="conversation"
            :current-contact="contactFor(conversation)"
            :assignee="assigneeFor(conversation)"
            :inbox="inboxFor(conversation)"
            :is-active-chat="currentConversationId === conversation.id"
            show-assignee
            show-inbox-name
            @click="openConversation(conversation)"
          />
        </template>

        <div v-if="isCurrentListLoading" class="flex justify-center py-6">
          <Spinner class="text-n-brand" />
        </div>
        <p
          v-else-if="['all', 'voice'].includes(channelFilter) && voiceError"
          role="alert"
          class="p-5 text-sm text-n-ruby-11"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
        </p>
        <div
          v-else-if="visibleItemCount === 0"
          class="mx-4 my-8 rounded-xl border border-dashed border-n-weak bg-n-alpha-1 px-5 py-8 text-center"
        >
          <span
            class="i-lucide-message-circle-off mx-auto mb-3 block size-7 text-n-slate-9"
          />
          <p class="text-sm font-medium text-n-slate-11">
            {{ t('JRC_CONTACT_CENTER.INBOX.EMPTY') }}
          </p>
        </div>
        <button
          v-if="canLoadMore"
          type="button"
          class="mx-auto my-4 block rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-11 hover:border-n-blue-7 hover:text-n-brand"
          @click="loadMore"
        >
          {{ t('JRC_CONTACT_CENTER.INBOX.LOAD_MORE') }}
        </button>
      </div>
    </aside>

    <main
      v-if="currentCallId"
      class="min-h-0 min-w-0 flex-1 overflow-y-auto bg-n-background p-4 sm:p-6"
    >
      <div class="mx-auto max-w-6xl">
        <RouterLink
          :to="{
            name: 'inbox_view',
            params: { accountId },
            query: route.query,
          }"
          class="mb-4 inline-flex items-center gap-2 text-sm font-medium text-n-blue-11 xl:hidden"
        >
          <span class="i-lucide-arrow-left size-4" />
          {{ t('JRC_CONTACT_CENTER.INBOX.BACK_TO_LIST') }}
        </RouterLink>
        <div class="mb-4 flex items-center gap-3">
          <span
            class="grid size-10 place-items-center rounded-xl bg-n-teal-3 text-n-teal-11"
          >
            <span class="i-lucide-phone-call size-5" />
          </span>
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('JRC_CONTACT_CENTER.INBOX.CALL_WORKSPACE') }}
          </h2>
        </div>
        <CallWorkspace
          v-if="contactCenterContext"
          :key="`${accountId}-${currentCallId}`"
          :account-id="accountId"
          :call-id="currentCallId"
          :context="contactCenterContext"
          @created="fetchVoiceCalls"
        />
        <p
          v-else-if="voiceError || !hasContactCenter"
          role="alert"
          class="p-5 text-sm text-n-ruby-11"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
        </p>
        <div v-else class="flex justify-center py-16">
          <Spinner class="text-n-brand" />
        </div>
      </div>
    </main>

    <router-view
      v-else-if="!isInitializing"
      :key="`${accountId}-${currentConversationId}`"
    />
  </section>
</template>
