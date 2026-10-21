<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { callStateLabels } from './inboxPresentation';
import { getInboxChannelKey, CHANNEL_TYPES } from 'dashboard/helper/inbox';
import ConversationCard from 'dashboard/components/widgets/conversation/ConversationCard.vue';

const props = defineProps({
  calls: { type: Array, default: () => [] },
  conversations: { type: Array, default: () => [] },
  channels: { type: Array, default: () => [] },
  inboxFor: { type: Function, required: true },
  currentCallId: { type: Number, default: null },
  currentConversationId: { type: Number, default: null },
  channelFilter: { type: String, default: 'all' },
  selectedCustomerName: { type: String, default: '' },
});
const emit = defineEmits(['selectCall', 'selectConversation']);
const { t } = useI18n();
const callLabels = computed(() => callStateLabels(t));
const collapsed = ref([]);
const callCustomer = call =>
  (props.currentCallId === call.id && props.selectedCustomerName) ||
  props.conversations.find(
    conversation => conversation.meta?.sender?.id === call.contact_id
  )?.meta?.sender?.name;
const social = [
  CHANNEL_TYPES.FACEBOOK,
  CHANNEL_TYPES.INSTAGRAM,
  CHANNEL_TYPES.TIKTOK,
];
const groups = computed(() =>
  props.channels
    .filter(
      channel =>
        channel.key !== 'all' &&
        (props.channelFilter === 'all' || props.channelFilter === channel.key)
    )
    .map(channel => ({
      ...channel,
      items:
        channel.key === 'voice'
          ? props.calls
          : props.conversations.filter(conversation => {
              const key = getInboxChannelKey(props.inboxFor(conversation));
              return channel.key === 'social'
                ? social.includes(key)
                : key === channel.key;
            }),
    }))
    .sort((a, b) => {
      const order = ['voice', 'whatsapp', 'email', 'social'];
      return (
        (order.indexOf(a.key) < 0 ? 9 : order.indexOf(a.key)) -
        (order.indexOf(b.key) < 0 ? 9 : order.indexOf(b.key))
      );
    })
);
const toggle = key => {
  collapsed.value = collapsed.value.includes(key)
    ? collapsed.value.filter(item => item !== key)
    : [...collapsed.value, key];
};
</script>

<template>
  <section
    v-for="group in groups"
    :key="group.key"
    class="mb-3 overflow-hidden rounded-lg border border-n-weak"
    :data-channel="group.key"
  >
    <button
      type="button"
      class="flex w-full items-center gap-2 bg-n-alpha-2 px-3 py-2.5 text-left text-xs font-semibold text-n-slate-12"
      :aria-expanded="!collapsed.includes(group.key)"
      @click="toggle(group.key)"
    >
      <span class="size-4 shrink-0" :class="[group.icon, group.iconClass]" />
      <span class="min-w-0 flex-1 truncate">
        {{
          t('JRC_CONTACT_CENTER.INBOX_360.LABEL_COUNT', {
            label: group.label,
            count: group.items.length,
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
    <div v-if="!collapsed.includes(group.key)">
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
          @click="emit('selectCall', call)"
        >
          <span
            class="grid size-9 shrink-0 place-items-center rounded-full bg-n-teal-3 text-n-teal-11"
          >
            <span class="i-lucide-phone-incoming size-4" />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-semibold text-n-slate-12">
              {{ call.ani || call.dnis || `#${call.id}` }}
            </span>
            <span class="mt-1 block truncate text-xs text-n-slate-10">
              {{
                callCustomer(call) ||
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
          <span class="i-lucide-phone-call mt-1 size-3 text-n-brand" />
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
