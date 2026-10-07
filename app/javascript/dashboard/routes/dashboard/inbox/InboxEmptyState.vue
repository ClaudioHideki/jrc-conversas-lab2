<script setup>
import { computed, watch, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import ConversationApi from 'dashboard/api/inbox/conversation';
import {
  CHANNEL_TYPES,
  getInboxChannelKey,
  INBOX_CHANNEL_PRESENTATION,
} from 'dashboard/helper/inbox';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useSipWebphone } from '../webphone/useSipWebphone';
import WhatsappCallingConfigurationAPI from 'dashboard/api/whatsappCallingConfiguration';
import { useJrcModuleAvailability } from 'dashboard/composables/useJrcModuleAvailability';
import { homeTones } from 'dashboard/components-next/Conversation/ConversationHome/presentation';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';

defineProps({
  emptyStateMessage: { type: String, default: '' },
});

const store = useStore();
const { t } = useI18n();
const uiFlags = useMapGetter('notifications/getUIFlags');
const notificationMeta = useMapGetter('notifications/getMeta');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const { configured, connecting, reconnecting, registered, extensionEnabled } =
  useSipWebphone();
const openStats = ref(null);
const pendingStats = ref(null);
const whatsappCallingActive = ref(false);
const accountId = useMapGetter('getCurrentAccountId');
const userId = useMapGetter('getCurrentUserID');
const { modules, statusLabel: moduleStatusLabel } = useJrcModuleAvailability();
const { openQuick } = useJrcCopilot();
const remoteStatus = ref('LOADING');
const whatsappCallingStatus = computed(() => {
  if (remoteStatus.value !== 'READY') return remoteStatus.value;
  return whatsappCallingActive.value ? 'ENABLED' : 'DISABLED_GENERIC';
});
const visibleChannelKeys = [
  CHANNEL_TYPES.WEBSITE,
  CHANNEL_TYPES.FACEBOOK,
  CHANNEL_TYPES.API,
  CHANNEL_TYPES.WHATSAPP,
  CHANNEL_TYPES.SMS,
  CHANNEL_TYPES.EMAIL,
  CHANNEL_TYPES.TELEGRAM,
];

const channelConfigurationStatus = channelInboxes => {
  if (!channelInboxes.length) return 'NOT_CONFIGURED';
  if (channelInboxes.some(inbox => inbox.reauthorizationRequired)) {
    return 'REAUTHORIZATION_REQUIRED';
  }
  return 'CONFIGURED';
};
const telephonyStatus = computed(() => {
  if (!configured.value) return 'NOT_CONFIGURED';
  if (!extensionEnabled.value) return 'DISABLED';
  if (registered.value) return 'ACTIVE';
  if (connecting.value || reconnecting.value) return 'RECONNECTING';
  return 'DISCONNECTED';
});
const statusClass = statusKey => {
  if (['ACTIVE', 'CONFIGURED', 'ENABLED'].includes(statusKey)) {
    return 'border-n-teal-6 bg-n-teal-3 text-n-teal-11';
  }
  if (['RECONNECTING', 'REAUTHORIZATION_REQUIRED'].includes(statusKey)) {
    return 'border-n-amber-6 bg-n-amber-3 text-n-amber-11';
  }
  if (['DISCONNECTED', 'DISABLED', 'DISABLED_GENERIC'].includes(statusKey))
    return 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11';
  return 'border-n-weak bg-n-alpha-2 text-n-slate-11';
};
const statusLabel = statusKey =>
  ({
    ACTIVE: t('INBOX.OVERVIEW.CHANNEL_STATUS.ACTIVE'),
    CONFIGURED: t('INBOX.OVERVIEW.CHANNEL_STATUS.CONFIGURED'),
    RECONNECTING: t('INBOX.OVERVIEW.CHANNEL_STATUS.RECONNECTING'),
    REAUTHORIZATION_REQUIRED: t(
      'INBOX.OVERVIEW.CHANNEL_STATUS.REAUTHORIZATION_REQUIRED'
    ),
    DISCONNECTED: t('INBOX.OVERVIEW.CHANNEL_STATUS.DISCONNECTED'),
    DISABLED: t('INBOX.OVERVIEW.CHANNEL_STATUS.DISABLED'),
    NOT_CONFIGURED: t('INBOX.OVERVIEW.CHANNEL_STATUS.NOT_CONFIGURED'),
    ENABLED: t('INBOX.OVERVIEW.CHANNEL_STATUS.ENABLED'),
    DISABLED_GENERIC: t('INBOX.OVERVIEW.CHANNEL_STATUS.DISABLED_GENERIC'),
    LOADING: moduleStatusLabel('LOADING'),
    UNAVAILABLE: moduleStatusLabel('UNAVAILABLE'),
  })[statusKey];

const fetchWhatsappCallingStatus = async isCurrent => {
  try {
    const data = await WhatsappCallingConfigurationAPI.get();
    if (!isCurrent()) return;
    whatsappCallingActive.value = Boolean(data?.active);
    remoteStatus.value = 'READY';
  } catch {
    if (isCurrent()) remoteStatus.value = 'UNAVAILABLE';
  }
};

const stats = computed(() => [
  {
    key: 'UNREAD',
    label: t('INBOX.OVERVIEW.STATS.UNREAD'),
    icon: 'i-lucide-mail',
    iconClass: 'bg-n-blue-3 text-n-blue-11',
    valueClass: 'text-n-blue-11',
    value: notificationMeta.value?.unreadCount ?? 0,
  },
  {
    key: 'PENDING',
    label: t('INBOX.OVERVIEW.STATS.PENDING'),
    icon: 'i-lucide-clock-3',
    iconClass: 'bg-n-amber-3 text-n-amber-11',
    valueClass: 'text-n-amber-11',
    value: pendingStats.value?.all_count ?? '—',
  },
  {
    key: 'MINE',
    label: t('INBOX.OVERVIEW.STATS.MINE'),
    icon: 'i-lucide-user-round',
    iconClass: 'bg-n-teal-3 text-n-teal-11',
    valueClass: 'text-n-teal-11',
    value: openStats.value?.mine_count ?? '—',
  },
  {
    key: 'OPEN',
    label: t('INBOX.OVERVIEW.STATS.OPEN'),
    icon: 'i-lucide-messages-square',
    iconClass: 'bg-n-ruby-3 text-n-ruby-11',
    valueClass: 'text-n-ruby-11',
    value: openStats.value?.all_count ?? '—',
  },
]);
const channels = computed(() => {
  const groupedChannels = (inboxes.value || []).reduce((groups, inbox) => {
    const key = getInboxChannelKey(inbox);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(inbox);
    return groups;
  }, new Map());

  const channelKeys = [
    ...visibleChannelKeys,
    ...[...groupedChannels.keys()].filter(
      key => !visibleChannelKeys.includes(key)
    ),
  ];

  const configuredChannels = channelKeys.map(key => {
    const channelInboxes = groupedChannels.get(key) || [];
    return {
      key,
      ...(INBOX_CHANNEL_PRESENTATION[key] || INBOX_CHANNEL_PRESENTATION.api),
      status: channelConfigurationStatus(channelInboxes),
      count: channelInboxes.length,
      countLabel: `(${channelInboxes.length})`,
    };
  });

  return [
    ...configuredChannels,
    {
      key: 'telephony',
      label: t('INBOX.OVERVIEW.CHANNELS.TELEPHONY'),
      icon: 'i-lucide-phone',
      iconClass: 'text-n-violet-10',
      status: telephonyStatus.value,
      route: { name: 'ramal_index' },
    },
    {
      key: 'whatsapp_calling',
      label: t('INBOX.OVERVIEW.CHANNELS.WHATSAPP_CALLING'),
      icon: 'i-lucide-message-circle-more',
      iconClass: 'text-n-teal-10',
      status: whatsappCallingStatus.value,
      route: whatsappCallingActive.value
        ? { name: 'whatsapp_calling_index' }
        : null,
    },
    ...modules.value.map(module => ({
      ...module,
      iconClass: homeTones[module.tone],
      module: true,
    })),
  ];
});

watch(
  [accountId, userId],
  async (_, __, onCleanup) => {
    let current = true;
    onCleanup(() => {
      current = false;
    });
    openStats.value = null;
    pendingStats.value = null;
    whatsappCallingActive.value = false;
    remoteStatus.value = 'LOADING';
    if (!inboxes.value?.length) store.dispatch('inboxes/get');
    const [openResult, pendingResult] = await Promise.allSettled([
      ConversationApi.meta({ status: 'open' }),
      ConversationApi.meta({ status: 'pending' }),
      fetchWhatsappCallingStatus(() => current),
    ]);
    if (!current) return;
    if (openResult.status === 'fulfilled') {
      openStats.value = openResult.value.data.meta;
    }
    if (pendingResult.status === 'fulfilled') {
      pendingStats.value = pendingResult.value.data.meta;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    class="hidden h-full w-full overflow-y-auto bg-n-background p-5 lg:block"
  >
    <div v-if="uiFlags.isFetching" class="grid h-full place-items-center">
      <Spinner class="text-n-brand" />
    </div>
    <div v-else class="mx-auto flex min-h-full max-w-6xl flex-col gap-5 py-2">
      <section
        class="relative overflow-hidden rounded-2xl border border-n-blue-4 bg-n-blue-2 px-8 py-7"
      >
        <div
          class="absolute -right-12 -top-20 size-72 rounded-full bg-n-blue-4/60 blur-3xl"
        />
        <div class="relative max-w-2xl">
          <span class="i-lucide-inbox mb-4 block size-10 text-n-brand" />
          <h2 class="text-2xl font-semibold tracking-tight text-n-slate-12">
            {{ $t('INBOX.OVERVIEW.TITLE') }}
          </h2>
          <p class="mt-2 text-sm leading-6 text-n-slate-11">
            {{ $t('INBOX.OVERVIEW.DESCRIPTION') }}
          </p>
          <div class="mt-5 flex flex-wrap gap-3">
            <RouterLink
              :to="{ name: 'home' }"
              class="flex h-10 items-center gap-2 rounded-lg bg-n-brand px-4 text-sm font-semibold text-white transition hover:brightness-110"
            >
              <span class="i-lucide-message-square-plus size-4" />
              {{ $t('INBOX.OVERVIEW.START_CONVERSATION') }}
            </RouterLink>
            <RouterLink
              :to="{ name: 'search' }"
              class="flex h-10 items-center gap-2 rounded-lg border border-n-blue-7 bg-n-solid-1 px-4 text-sm font-semibold text-n-blue-11 transition hover:bg-n-blue-3"
            >
              <span class="i-lucide-search size-4" />
              {{ $t('INBOX.OVERVIEW.SEARCH_CONTACT') }}
            </RouterLink>
          </div>
        </div>
      </section>

      <section class="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <article
          v-for="item in stats"
          :key="item.key"
          class="flex items-center gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
        >
          <span
            class="grid size-11 shrink-0 place-items-center rounded-full"
            :class="item.iconClass"
          >
            <span class="size-5" :class="item.icon" />
          </span>
          <div>
            <strong
              class="block text-2xl font-semibold"
              :class="item.valueClass"
            >
              {{ item.value }}
            </strong>
            <span class="text-sm text-n-slate-11">
              {{ item.label }}
            </span>
          </div>
        </article>
      </section>

      <section
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 xl:max-w-3xl"
      >
        <div class="mb-4 flex items-center gap-2">
          <span class="i-lucide-plug size-5 text-n-brand" />
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ $t('INBOX.OVERVIEW.CHANNELS.TITLE') }}
          </h3>
        </div>
        <div
          class="divide-y divide-n-weak overflow-hidden rounded-xl border border-n-weak"
        >
          <component
            :is="
              channel.route ? 'RouterLink' : channel.command ? 'button' : 'div'
            "
            v-for="channel in channels"
            :key="channel.key"
            :to="channel.route"
            :type="channel.command ? 'button' : undefined"
            class="flex w-full min-h-14 items-center gap-3 bg-n-solid-1 px-4 text-left transition hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="channel.command === 'nico' && openQuick()"
          >
            <span
              class="grid size-9 shrink-0 place-items-center rounded-xl"
              :class="channel.module ? channel.iconClass : 'bg-n-alpha-2'"
              ><span
                class="size-5"
                :class="[channel.icon, !channel.module && channel.iconClass]"
            /></span>
            <span class="flex-1 text-sm font-medium text-n-slate-12">
              {{ channel.label }}
              <span
                v-if="channel.count > 1"
                class="ml-1 text-xs font-normal text-n-slate-9"
              >
                {{ channel.countLabel }}
              </span>
            </span>
            <span
              class="shrink-0 rounded-full border px-2.5 py-1 text-xs font-semibold"
              :class="statusClass(channel.status)"
            >
              {{ statusLabel(channel.status) }}
            </span>
            <span
              v-if="channel.route || channel.command"
              class="i-lucide-chevron-right size-4"
            />
          </component>
        </div>
      </section>

      <div
        class="mt-auto flex items-center gap-3 rounded-xl border border-n-blue-4 bg-n-blue-2 px-4 py-3 text-sm text-n-slate-11"
      >
        <span class="i-lucide-bell-ring size-5 shrink-0 text-n-brand" />
        {{ emptyStateMessage || $t('INBOX.OVERVIEW.FOOTER') }}
      </div>
    </div>
  </div>
</template>
