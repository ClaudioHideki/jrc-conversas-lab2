<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import ConversationHome from 'dashboard/components-next/Conversation/ConversationHome/ConversationHome.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
    ConversationHome,
    Dialog,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();

    return {
      uiSettings,
      updateUISettings,
      accountId,
    };
  },
  data() {
    return {
      showSearchModal: false,
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    isOnExpandedLayout() {
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },

    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
      this.ensureContactSidebarOpen();
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
    this.ensureContactSidebarOpen();
  },

  methods: {
    ensureContactSidebarOpen() {
      if (
        !this.conversationId ||
        window.innerWidth < wootConstants.LARGE_SCREEN_BREAKPOINT ||
        this.uiSettings.is_contact_sidebar_open
      ) {
        return;
      }
      this.updateUISettings({
        is_contact_sidebar_open: true,
        is_copilot_panel_open: false,
      });
    },
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        this.$store.dispatch('getConversation', this.conversationId);
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
  },
};
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 overflow-hidden bg-n-background lg:gap-3 lg:p-3"
  >
    <ChatList
      class="lg:h-full lg:overflow-hidden lg:rounded-2xl lg:border lg:border-n-weak lg:bg-n-solid-1 lg:shadow-sm"
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @conversation-load="onConversationLoad"
    >
      <button
        v-if="isOnExpandedLayout && !conversationId"
        type="button"
        class="m-3 flex min-h-10 items-center justify-center gap-2 rounded-xl border border-n-blue-6 bg-n-blue-2 px-3 text-sm font-semibold text-n-blue-11 hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="$refs.homeDialog.open()"
      >
        <span class="i-lucide-sparkles size-4" aria-hidden="true" />
        {{ $t('JRC_HOME.QUICK_ACTIONS') }}
      </button>
    </ChatList>
    <ConversationBox
      v-if="showMessageView"
      class="lg:h-full lg:min-w-0 lg:overflow-hidden lg:rounded-2xl lg:border lg:border-n-weak lg:bg-n-solid-1 lg:shadow-sm"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
    >
      <SidepanelSwitch v-if="currentChat.id && !shouldShowSidebar" />
    </ConversationBox>
    <ConversationSidebar
      v-if="shouldShowSidebar"
      class="lg:!h-full lg:!overflow-hidden lg:!rounded-2xl lg:!border lg:!border-n-weak lg:!shadow-sm"
      :current-chat="currentChat"
    />
    <CmdBarConversationSnooze />
    <Dialog ref="homeDialog" width="3xl" overflow-y-auto :title="$t('JRC_HOME.QUICK_ACTIONS')" :cancel-button-label="$t('GENERAL.CLOSE')" :show-confirm-button="false">
      <div class="h-[min(42rem,70dvh)] min-h-0 overflow-hidden">
        <ConversationHome @navigate="$refs.homeDialog.close()" />
      </div>
    </Dialog>
  </section>
</template>
