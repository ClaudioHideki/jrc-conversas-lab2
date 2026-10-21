<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';

import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import InboxEmptyState from './InboxEmptyState.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';

defineProps({ embedded: { type: Boolean, default: false } });
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const { uiSettings } = useUISettings();

const isConversationLoading = ref(false);
const isConversationFailed = ref(false);
let generation = 0;
const currentChat = useMapGetter('getSelectedChat');
const conversationById = useMapGetter('getConversationById');

const inboxId = computed(() => Number(route.params.inboxId));
const conversationId = computed(() => Number(route.params.id));
const showEmptyState = computed(() => !conversationId.value);

const isContactPanelOpen = computed(() => {
  if (!currentChat.value.id) return false;
  return uiSettings.value.is_contact_sidebar_open;
});

const setActiveChat = async (conversation, version) => {
  if (!conversation) return;
  await store.dispatch('setActiveChat', { data: conversation });
  if (version === generation) emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
};

const fetchConversationById = async () => {
  generation += 1;
  const version = generation;
  if (!conversationId.value) return;

  store.dispatch('clearSelectedState');
  isConversationLoading.value = true;
  isConversationFailed.value = false;
  try {
    if (!conversationById.value(conversationId.value)) {
      await store.dispatch('getConversation', conversationId.value);
    }
    if (version !== generation) return;
    const conversation = conversationById.value(conversationId.value);
    if (!conversation) {
      isConversationFailed.value = true;
      return;
    }
    await setActiveChat(conversation, version);
  } catch {
    if (version === generation) isConversationFailed.value = true;
  } finally {
    if (version === generation) isConversationLoading.value = false;
  }
};

watch(conversationId, fetchConversationById, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
});

onMounted(async () => {
  await store.dispatch('agents/get');
});
</script>

<template>
  <main class="h-full min-w-0 flex-1 bg-n-background">
    <div v-if="showEmptyState" class="flex h-full w-full">
      <InboxEmptyState />
    </div>
    <div v-else class="h-full" :class="embedded ? 'p-0' : 'p-0 lg:p-3 lg:pl-0'">
      <div
        v-if="isConversationLoading"
        class="grid h-full place-items-center rounded-2xl border border-n-weak bg-n-solid-1"
      >
        <Spinner class="text-n-brand" />
      </div>
      <div
        v-else-if="isConversationFailed"
        role="alert"
        class="grid h-full place-content-center p-6 text-center text-sm text-n-ruby-11"
      >
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </div>
      <div v-else class="flex h-full min-w-0 gap-3">
        <ConversationBox
          class="min-w-0 flex-1 overflow-hidden bg-n-solid-1"
          :class="
            embedded ? '' : 'border-n-weak shadow-sm lg:rounded-2xl lg:border'
          "
          :hide-header="embedded"
          is-inbox-view
          :inbox-id="inboxId"
          :is-on-expanded-layout="false"
        >
          <SidepanelSwitch
            v-if="!embedded && currentChat.id && !isContactPanelOpen"
          />
        </ConversationBox>
        <ConversationSidebar
          v-if="!embedded && isContactPanelOpen"
          class="overflow-hidden border-n-weak bg-n-solid-1 shadow-sm lg:!rounded-2xl lg:!border"
          :current-chat="currentChat"
        />
      </div>
    </div>
  </main>
</template>
