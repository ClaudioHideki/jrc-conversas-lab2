<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import {
  CHANNEL_TYPES,
  getInboxChannelKey,
  INBOX_CHANNEL_PRESENTATION,
} from 'dashboard/helper/inbox';

import ConversationCard from 'dashboard/components/widgets/conversation/ConversationCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();

const TEXT = Object.freeze({
  title: 'Caixa de Entrada',
  description: 'Conversas abertas em todos os canais',
  openConversationHub: 'Abrir central de conversas',
  expandList: 'Expandir lista',
  collapseList: 'Recolher lista',
  search: 'Buscar conversas ou contatos...',
  filterLabel: 'Filtrar conversas por canal',
  empty: 'Nenhuma conversa aberta neste canal.',
  loadMore: 'Carregar mais conversas',
});

const page = ref(1);
const conversationsPerPage = 25;
const channelFilter = ref(route.query.channel || 'all');
const isListExpanded = ref(false);

const inboxes = useMapGetter('inboxes/getAllInboxes');
const inboxById = useMapGetter('inboxes/getInboxById');
const allOpenConversations = useMapGetter('getAllStatusChats');
const isLoading = useMapGetter('getChatListLoadingStatus');

const conversationFilters = computed(() => ({
  assigneeType: wootConstants.ASSIGNEE_TYPE.ALL,
  status: wootConstants.STATUS_TYPE.OPEN,
  sortBy: wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC,
  page: page.value,
}));

const configuredChannelKeys = computed(() => [
  ...new Set((inboxes.value || []).map(getInboxChannelKey)),
]);

const channelFilterOptions = computed(() => [
  {
    key: 'all',
    label: 'Todas',
    icon: 'i-lucide-inbox',
    iconClass: 'text-n-blue-10',
  },
  ...configuredChannelKeys.value.map(key => ({
    key,
    ...(INBOX_CHANNEL_PRESENTATION[key] || INBOX_CHANNEL_PRESENTATION.api),
  })),
]);

const conversations = computed(() => {
  const items = allOpenConversations.value({
    assigneeType: wootConstants.ASSIGNEE_TYPE.ALL,
    status: wootConstants.STATUS_TYPE.OPEN,
  });

  if (channelFilter.value === 'all') return items;
  return items.filter(conversation => {
    const inbox = inboxById.value(conversation.inbox_id);
    return getInboxChannelKey(inbox) === channelFilter.value;
  });
});

const currentConversationId = computed(() => Number(route.params.id));
const asideWidthClass = computed(() =>
  isListExpanded.value
    ? 'lg:w-[48%] lg:min-w-[520px] lg:max-w-[680px] xl:w-[50%] xl:min-w-[600px] xl:max-w-[760px]'
    : 'lg:w-[40%] lg:min-w-[420px] lg:max-w-[500px] xl:w-[38%] xl:min-w-[460px] xl:max-w-[580px] 2xl:max-w-[640px]'
);
const layoutToggleTitle = computed(() =>
  isListExpanded.value ? TEXT.collapseList : TEXT.expandList
);
const canLoadMore = computed(
  () =>
    !isLoading.value &&
    conversations.value.length >= page.value * conversationsPerPage
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

const setChannelFilter = key => {
  channelFilter.value = key;
  router.replace({
    name: route.params.id ? 'inbox_view_conversation' : 'inbox_view',
    params: route.params,
    query: { ...route.query, channel: key === 'all' ? undefined : key },
  });
};

const openConversation = conversation => {
  if (currentConversationId.value === conversation.id) return;
  router.push({
    name: 'inbox_view_conversation',
    params: {
      inboxId: conversation.inbox_id,
      type: 'conversation',
      id: conversation.id,
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

watch(
  () => route.query.channel,
  key => {
    const available = channelFilterOptions.value.some(
      option => option.key === key
    );
    channelFilter.value = available ? key : 'all';
  }
);

onMounted(async () => {
  if (!inboxes.value?.length) await store.dispatch('inboxes/get');
  await fetchConversations({ reset: true });
});
</script>

<template>
  <section class="flex h-full w-full bg-n-surface-1">
    <aside
      class="flex h-full w-full flex-col border-n-weak bg-n-solid-1 shadow-[6px_0_24px_rgba(8,43,82,0.04)] transition-[width,max-width,min-width] duration-200 ltr:border-r rtl:border-l"
      :class="[
        !currentConversationId ? 'flex' : 'hidden xl:flex',
        asideWidthClass,
      ]"
    >
      <header class="border-b border-n-weak px-4 pb-3 pt-5">
        <div class="flex items-center justify-between gap-3">
          <div>
            <div class="flex items-center gap-2">
              <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
                {{ TEXT.title }}
              </h1>
              <span
                class="rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-semibold text-n-blue-11"
              >
                {{ conversations.length }}
              </span>
            </div>
            <p class="mt-1 text-xs text-n-slate-10">
              {{ TEXT.description }}
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
              :title="TEXT.openConversationHub"
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
          <span>{{ TEXT.search }}</span>
        </RouterLink>
      </header>

      <nav
        class="flex gap-2 overflow-x-auto border-b border-n-weak px-3 py-3"
        :aria-label="TEXT.filterLabel"
      >
        <button
          v-for="option in channelFilterOptions"
          :key="option.key"
          type="button"
          class="flex h-9 shrink-0 items-center gap-2 rounded-xl border px-3 text-xs font-semibold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :class="filterButtonClass(option)"
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

        <div v-if="isLoading" class="flex justify-center py-6">
          <Spinner class="text-n-brand" />
        </div>
        <div
          v-else-if="!conversations.length"
          class="mx-4 my-8 rounded-xl border border-dashed border-n-weak bg-n-alpha-1 px-5 py-8 text-center"
        >
          <span
            class="i-lucide-message-circle-off mx-auto mb-3 block size-7 text-n-slate-9"
          />
          <p class="text-sm font-medium text-n-slate-11">
            {{ TEXT.empty }}
          </p>
        </div>
        <button
          v-if="canLoadMore"
          type="button"
          class="mx-auto my-4 block rounded-lg border border-n-weak px-4 py-2 text-sm font-medium text-n-slate-11 hover:border-n-blue-7 hover:text-n-brand"
          @click="loadMore"
        >
          {{ TEXT.loadMore }}
        </button>
      </div>
    </aside>
    <router-view />
  </section>
</template>
