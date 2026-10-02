<script setup>
import OperationsLinks from 'dashboard/routes/dashboard/jrcOperations/components/OperationsLinks.vue';
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import MasterContactPanel from 'dashboard/routes/dashboard/jrcCustomers/components/MasterContactPanel.vue';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import ConversationCrmWidget from 'dashboard/routes/dashboard/crm/components/conversation/ConversationCrmWidget.vue';
import { dealsAPI, leadsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const { uiSettings, updateUISettings } = useUISettings();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const linkedDeal = ref(null);
const linkedLead = ref(null);
const isConvertingToLead = ref(false);
const hasCrm = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.JRC_CRM)
);
const { width: windowWidth } = useWindowSize();

const activeTab = computed(() => {
  const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;

  if (isContactSidebarOpen) {
    return 0;
  }
  return null;
});

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const closeContactPanel = () => {
  if (isSmallScreen.value && uiSettings.value?.is_contact_sidebar_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};

const loadCrmLinks = async () => {
  linkedDeal.value = null;
  linkedLead.value = null;
  if (!hasCrm.value || !props.currentChat?.id) return;

  try {
    const [dealsResponse, leadsResponse] = await Promise.all([
      dealsAPI.list({ conversation_id: props.currentChat.id }),
      leadsAPI.list({ conversation_id: props.currentChat.id }),
    ]);
    linkedDeal.value = dealsResponse.data[0] || null;
    linkedLead.value = leadsResponse.data[0] || null;
  } catch {
    // The conversation remains usable if the optional CRM panel cannot load.
  }
};

const convertConversationToLead = async () => {
  isConvertingToLead.value = true;
  try {
    const { data } = await leadsAPI.fromConversation(props.currentChat.id);
    linkedLead.value = data.lead;
    useAlert(
      data.created
        ? 'Conversa transformada em lead.'
        : `Esta conversa já está vinculada ao lead ${data.lead.name}.`
    );
  } catch (error) {
    useAlert(
      error.response?.data?.error ||
        'Não foi possível transformar esta conversa em lead.'
    );
  } finally {
    isConvertingToLead.value = false;
  }
};

const openDealCreation = () => {
  router.push({
    name: 'crm_deals',
    query: {
      conversationId: props.currentChat.id,
      contactId: props.currentChat.contact_id,
    },
  });
};

const openActivityCreation = dealId => {
  router.push({ name: 'crm_activities', query: { dealId } });
};

watch(() => [props.currentChat?.id, hasCrm.value], loadCrmLinks, {
  immediate: true,
});
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeContactPanel(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': activeTab === 0,
        'md:hidden': activeTab !== 0,
      },
    ]"
  >
    <div class="flex flex-1 flex-col overflow-auto">
      <ContactPanel
        v-show="activeTab === 0"
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
      <OperationsLinks :conversation-id="currentChat.id" compact />
      <MasterContactPanel
        :contact-id="currentChat.contact_id || currentChat.meta?.sender?.id"
      />
      <ConversationCrmWidget
        v-if="hasCrm"
        :linked-deal="linkedDeal"
        :linked-lead="linkedLead"
        :converting-lead="isConvertingToLead"
        @create-deal="openDealCreation"
        @create-activity="openActivityCreation"
        @convert-to-lead="convertConversationToLead"
      />
    </div>
  </div>
</template>
