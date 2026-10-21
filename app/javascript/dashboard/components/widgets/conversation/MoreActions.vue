<script setup>
import { computed, onUnmounted } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { useMapGetter } from 'dashboard/composables/store';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

defineProps({ requestClosing: { type: Function, default: null } });
const store = useStore();
const { t } = useI18n();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);
const [showAssignDropdown, toggleAssignDropdown] = useToggle(false);

const TEXT = Object.freeze({
  snooze: 'Adiar',
  assign: 'Atribuir',
});

const currentChat = computed(() => store.getters.getSelectedChat);
const assignableAgentsByInbox = useMapGetter(
  'inboxAssignableAgents/getAssignableAgents'
);
const assignableAgents = computed(() =>
  assignableAgentsByInbox.value(String(currentChat.value.inbox_id || ''))
);
const agentMenuItems = computed(() =>
  assignableAgents.value.map(agent => ({
    action: 'assign',
    value: agent.id,
    label: agent.name,
    thumbnail: { name: agent.name, src: agent.thumbnail },
  }))
);

const openSnoozeModal = () => {
  document.querySelector('ninja-keys')?.open({ parent: 'snooze_conversation' });
};

const openAssignDropdown = () => {
  const willOpen = !showAssignDropdown.value;
  toggleAssignDropdown();
  toggleDropdown(false);
  if (willOpen && currentChat.value.inbox_id) {
    store.dispatch('inboxAssignableAgents/fetch', [currentChat.value.inbox_id]);
  }
};

const assignAgent = async ({ value }) => {
  await store.dispatch('assignAgent', {
    conversationId: currentChat.value.id,
    agentId: value,
  });
  toggleAssignDropdown(false);
};

const actionMenuItems = computed(() => {
  const items = [];

  if (!currentChat.value.muted) {
    items.push({
      icon: 'i-lucide-volume-off',
      label: t('CONTACT_PANEL.MUTE_CONTACT'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    items.push({
      icon: 'i-lucide-volume-1',
      label: t('CONTACT_PANEL.UNMUTE_CONTACT'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  items.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  return items;
});

const handleActionClick = ({ action }) => {
  toggleDropdown(false);

  if (action === 'mute') {
    store.dispatch('muteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
  } else if (action === 'unmute') {
    store.dispatch('unmuteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  }
};

// These functions are needed for the event listeners
const mute = () => {
  store.dispatch('muteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
};

const unmute = () => {
  store.dispatch('unmuteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
};

emitter.on(CMD_MUTE_CONVERSATION, mute);
emitter.on(CMD_UNMUTE_CONVERSATION, unmute);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, mute);
  emitter.off(CMD_UNMUTE_CONVERSATION, unmute);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
});
</script>

<template>
  <div class="actions--container relative flex items-center gap-2">
    <ResolveAction
      :request-closing="requestClosing"
      :conversation-id="currentChat.id"
      :status="currentChat.status"
      prominent
      hide-additional-actions
    />
    <ButtonV4
      :label="TEXT.snooze"
      icon="i-lucide-clock-3"
      size="sm"
      color="amber"
      @click="openSnoozeModal"
    />
    <div
      v-on-clickaway="() => toggleAssignDropdown(false)"
      class="relative flex items-center"
    >
      <ButtonV4
        :label="TEXT.assign"
        icon="i-lucide-user-round-check"
        size="sm"
        color="blue"
        @click="openAssignDropdown"
      />
      <DropdownMenu
        v-if="showAssignDropdown"
        :menu-items="agentMenuItems"
        class="top-full mt-1 ltr:right-0 rtl:left-0"
        @action="assignAgent"
      />
    </div>
    <div
      v-on-clickaway="() => toggleDropdown(false)"
      class="relative flex items-center group"
    >
      <ButtonV4
        v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-more-vertical"
        class="rounded-lg group-hover:bg-n-alpha-2"
        @click="toggleDropdown()"
      />
      <DropdownMenu
        v-if="showActionsDropdown"
        :menu-items="actionMenuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
  </div>
</template>
