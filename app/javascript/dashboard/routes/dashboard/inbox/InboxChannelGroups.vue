<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { callStateLabels } from './inboxPresentation';
import { getInboxChannelKey, CHANNEL_TYPES } from 'dashboard/helper/inbox';
import ConversationCard from 'dashboard/components/widgets/conversation/ConversationCard.vue';
import { CHANNEL_APPEARANCE } from './inboxAppearance';
import {
  conversationMessageTimestamp,
  inboxOrigin,
} from 'dashboard/helper/inboxOrigin';

const props = defineProps({
  calls: { type: Array, default: () => [] },
  conversations: { type: Array, default: () => [] },
  channels: { type: Array, default: () => [] },
  inboxFor: { type: Function, required: true },
  currentCallId: { type: [Number, String], default: null },
  currentConversationId: { type: Number, default: null },
  channelFilter: { type: String, default: 'all' },
  selectedCustomerName: { type: String, default: '' },
  now: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['selectCall', 'selectConversation']);
const { t } = useI18n();
const callLabels = computed(() => callStateLabels(t));
const appearance = key => CHANNEL_APPEARANCE[key] || CHANNEL_APPEARANCE.default;
const collapsed = ref([]);
const callCustomer = call =>
  (props.currentCallId === call.id && props.selectedCustomerName) ||
  props.conversations.find(
    conversation => conversation.meta?.sender?.id === call.contact_id
  )?.meta?.sender?.name;
const callPhone = call =>
  call.direction === 'outbound' ? call.dnis : call.ani || call.dnis;
const callDuration = call => {
  if (call.local) return call.duration;
  const start = Date.parse(call.answered_at);
  const end = call.ended_at ? Date.parse(call.ended_at) : props.now;
  if (!Number.isFinite(start) || !Number.isFinite(end)) return '';
  const seconds = Math.max(0, Math.floor((end - start) / 1000));
  return [
    Math.floor(seconds / 3600),
    Math.floor(seconds / 60) % 60,
    seconds % 60,
  ]
    .map(value => String(value).padStart(2, '0'))
    .join(':');
};
const social = [
  CHANNEL_TYPES.FACEBOOK,
  CHANNEL_TYPES.INSTAGRAM,
  CHANNEL_TYPES.TIKTOK,
];
const visibleCalls = computed(() =>
  ['all', 'voice'].includes(props.channelFilter) ? props.calls : []
);
const groups = computed(() => {
  const inboxes = new Map();
  props.conversations.forEach(conversation => {
    const inbox = props.inboxFor(conversation) || {};
    const channelKey = getInboxChannelKey(inbox);
    const filterKey = social.includes(channelKey) ? 'social' : channelKey;
    if (props.channelFilter !== 'all' && props.channelFilter !== filterKey)
      return;
    const id = conversation.inbox_id;
    if (!inboxes.has(id)) {
      const channel = props.channels.find(item => item.key === filterKey);
      inboxes.set(id, {
        key: `inbox-${id}`,
        inboxId: id,
        channelKey,
        label:
          inbox.name ||
          t('JRC_CONTACT_CENTER.INBOX_360.SOURCE_INBOX_ID', { id }),
        icon: channel?.icon || 'i-lucide-inbox',
        inbox,
        items: [],
      });
    }
    inboxes.get(id).items.push(conversation);
  });
  const result = [...inboxes.values()];
  result.forEach(group => {
    group.unreadCount = group.items.reduce(
      (total, item) => total + (item.unread_count || 0),
      0
    );
    group.items.sort(
      (a, b) =>
        (conversationMessageTimestamp(b) || 0) -
          (conversationMessageTimestamp(a) || 0) || a.id - b.id
    );
  });
  result.sort(
    (a, b) => a.label.localeCompare(b.label) || a.inboxId - b.inboxId
  );
  const voice = props.channels.find(item => item.key === 'voice');
  if (
    visibleCalls.value.length ||
    (voice && ['all', 'voice'].includes(props.channelFilter))
  ) {
    result.unshift({
      ...voice,
      key: 'voice',
      channelKey: 'voice',
      items: visibleCalls.value,
    });
  }
  return result;
});
const toggle = key => {
  collapsed.value = collapsed.value.includes(key)
    ? collapsed.value.filter(item => item !== key)
    : [...collapsed.value, key];
};
const originFor = group => inboxOrigin(group.inbox, props.now);
</script>

<template>
  <section
    v-for="group in groups"
    :key="group.key"
    class="mb-4 overflow-hidden rounded-xl border border-l-4 bg-n-solid-1 shadow-sm"
    :class="appearance(group.channelKey).border"
    :data-channel="group.channelKey"
    :data-inbox-id="group.inboxId"
  >
    <button
      type="button"
      class="flex w-full items-center gap-2 px-3 py-3 text-left text-xs font-bold focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
      :class="appearance(group.channelKey).heading"
      :aria-expanded="!collapsed.includes(group.key)"
      @click="toggle(group.key)"
    >
      <span class="size-5 shrink-0" :class="group.icon" />
      <span class="min-w-0 flex-1">
        <span class="block truncate">{{
          t('JRC_CONTACT_CENTER.INBOX_360.INBOX_LOADED_COUNT', {
            label: group.label,
            count: group.items.length,
          })
        }}</span>
        <span
          v-if="group.channelKey === 'whatsapp'"
          class="mt-1 block truncate text-[11px] font-normal"
        >
          {{
            originFor(group).ownNumber ||
            t('JRC_CONTACT_CENTER.INBOX_360.NUMBER_UNCONFIRMED')
          }}
        </span>
      </span>
      <span
        v-if="group.unreadCount > 0"
        class="shrink-0 rounded-full bg-n-solid-1 px-2 py-1 text-[10px]"
      >
        {{
          t('JRC_CONTACT_CENTER.INBOX_360.UNREAD_COUNT', {
            count: group.unreadCount,
          })
        }}
      </span>
      <span
        class="size-3"
        :class="
          collapsed.includes(group.key)
            ? 'i-lucide-chevron-down'
            : 'i-lucide-chevron-up'
        "
      />
    </button>
    <div v-show="!collapsed.includes(group.key)">
      <template v-if="group.key === 'voice'">
        <button
          v-for="call in group.items"
          :key="call.id"
          type="button"
          class="flex w-full items-start gap-2.5 border-t border-n-weak px-3 py-3 text-left hover:bg-n-blue-2"
          :class="
            currentCallId === call.id
              ? 'bg-n-blue-2 ring-1 ring-inset ring-n-blue-6'
              : 'bg-n-solid-1'
          "
          :aria-pressed="currentCallId === call.id"
          @click="emit('selectCall', call)"
        >
          <span
            class="grid size-9 shrink-0 place-items-center rounded-full bg-n-teal-3 text-n-teal-11"
          >
            <span class="i-lucide-phone-incoming size-4" />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-semibold text-n-slate-12">
              {{ callCustomer(call) || callPhone(call) || `#${call.id}` }}
            </span>
            <span class="mt-1 block truncate text-xs text-n-slate-10">
              {{
                callPhone(call) ||
                (call.direction === 'outbound'
                  ? t('JRC_CONTACT_CENTER.INBOX.DIRECTIONS.OUTBOUND')
                  : t('JRC_CONTACT_CENTER.INBOX.DIRECTIONS.INBOUND'))
              }}
            </span>
            <span
              class="mt-2 inline-block rounded-full bg-n-teal-3 px-2 py-0.5 text-[10px] font-medium text-n-teal-11"
            >
              {{ callLabels[call.status] }}
            </span>
          </span>
          <span
            v-if="callDuration(call)"
            class="mt-1 shrink-0 text-[10px] tabular-nums text-n-slate-10"
            >{{ callDuration(call) }}</span
          >
        </button>
      </template>
      <ConversationCard
        v-for="conversation in group.key === 'voice' ? [] : group.items"
        :key="conversation.id"
        :chat="conversation"
        :current-contact="conversation.meta?.sender || {}"
        :assignee="conversation.meta?.assignee || {}"
        :inbox="inboxFor(conversation)"
        :is-active-chat="currentConversationId === conversation.id"
        compact
        operational
        show-assignee
        :now="now"
        @click="emit('selectConversation', conversation)"
      />
      <p
        v-if="!group.items.length"
        class="m-0 px-3 py-4 text-xs text-n-slate-10"
      >
        {{ t('JRC_CONTACT_CENTER.INBOX_360.GROUP_EMPTY') }}
      </p>
    </div>
  </section>
</template>
