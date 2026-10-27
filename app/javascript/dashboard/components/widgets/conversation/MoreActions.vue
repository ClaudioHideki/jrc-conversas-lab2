<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import ConversationAssignmentMenu from './ConversationAssignmentMenu.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

defineProps({ requestClosing: { type: Function, default: null } });
const store = useStore();
const { t } = useI18n();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const assignmentMenu = ref(null);
const actionsPopover = ref(null);
const isSavingAction = ref(false);

const TEXT = Object.freeze({
  snooze: 'Adiar',
});

const currentChat = computed(() => store.getters.getSelectedChat);

const openSnoozeModal = () => {
  document.querySelector('ninja-keys')?.open({ parent: 'snooze_conversation' });
};

watch(
  () => [
    currentChat.value.id,
    store.getters.getCurrentAccountId,
    store.getters.getCurrentUserID,
  ],
  () => {
    actionsPopover.value?.hide();
    toggleEmailModal(false);
  }
);

const actionMenuItems = computed(() => {
  const items = [];

  if (!currentChat.value.muted) {
    items.push({
      icon: 'i-lucide-volume-off',
      label: t('CONTACT_PANEL.MUTE_CONTACT'),
      action: 'mute',
      value: 'mute',
      disabled: isSavingAction.value,
    });
  } else {
    items.push({
      icon: 'i-lucide-volume-1',
      label: t('CONTACT_PANEL.UNMUTE_CONTACT'),
      action: 'unmute',
      value: 'unmute',
      disabled: isSavingAction.value,
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

const handleActionClick = async ({ action }) => {
  if (action === 'send_transcript') {
    actionsPopover.value?.hide();
    toggleEmailModal(true);
    return;
  }
  if (isSavingAction.value || !currentChat.value.id) return;
  const conversationId = currentChat.value.id;
  const accountId = store.getters.getCurrentAccountId;
  const userId = store.getters.getCurrentUserID;
  isSavingAction.value = true;
  try {
    const saved = await store.dispatch(
      action === 'mute' ? 'muteConversation' : 'unmuteConversation',
      conversationId
    );
    if (
      currentChat.value.id !== conversationId ||
      store.getters.getCurrentAccountId !== accountId ||
      store.getters.getCurrentUserID !== userId
    )
      return;
    if (saved) actionsPopover.value?.hide();
    const successMessage =
      action === 'mute'
        ? t('CONTACT_PANEL.MUTED_SUCCESS')
        : t('CONTACT_PANEL.UNMUTED_SUCCESS');
    useAlert(
      saved ? successMessage : t('JRC_CONTACT_CENTER.INBOX_360.ACTION_ERROR')
    );
  } finally {
    isSavingAction.value = false;
  }
};

const mute = () => handleActionClick({ action: 'mute' });
const unmute = () => handleActionClick({ action: 'unmute' });

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
    <ConversationAssignmentMenu
      ref="assignmentMenu"
      @show="actionsPopover?.hide()"
    />
    <Popover
      ref="actionsPopover"
      :modal-label="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
      @show="assignmentMenu?.hide()"
    >
      <template #default="{ isOpen }">
        <ButtonV4
          v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-more-vertical"
          :aria-label="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
          :aria-expanded="isOpen"
          aria-haspopup="menu"
          data-testid="conversation-more-actions-trigger"
          class="rounded-lg"
        />
      </template>
      <template #content>
        <DropdownMenu
          data-testid="conversation-more-actions-menu"
          :menu-items="actionMenuItems"
          class="!static !shadow-none !outline-none min-w-56"
          @action="handleActionClick"
        />
      </template>
    </Popover>
    <Teleport to="body">
      <EmailTranscriptModal
        v-if="showEmailActionsModal"
        :show="showEmailActionsModal"
        :current-chat="currentChat"
        @cancel="toggleEmailModal(false)"
      />
    </Teleport>
  </div>
</template>
