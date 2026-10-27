<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ConversationAction from '../conversation/ConversationAction.vue';
import MacrosList from '../conversation/Macros/List.vue';
import ConversationInfo from '../conversation/ConversationInfo.vue';
import CustomAttributes from '../conversation/customAttributes/CustomAttributes.vue';
import ContactNotes from '../conversation/contact/ContactNotes.vue';
import SharedFiles from '../conversation/SharedFiles.vue';
import ContactConversations from '../conversation/ContactConversations.vue';
import ConversationParticipant from '../conversation/ConversationParticipant.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { CONVERSATION_TOOLS } from './conversationTools';

const props = defineProps({
  accountId: { type: Number, required: true },
  conversationId: { type: Number, required: true },
  tool: { type: String, required: true },
});
const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const contactGetter = useMapGetter('contacts/getContact');
const metadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const featureEnabled = useMapGetter('accounts/isFeatureEnabledonAccount');
const attachmentsLoaded = useMapGetter('getSelectedChatAttachmentsLoaded');
const loading = ref(false);
const failed = ref(false);
const prepared = new Set();
let generation = 0;
const contextMatches = computed(
  () =>
    currentChat.value?.id === props.conversationId &&
    Number(currentChat.value?.account_id) === props.accountId
);
const contactId = computed(() =>
  contextMatches.value ? currentChat.value.meta?.sender?.id : null
);
const contact = computed(() =>
  contactId.value ? contactGetter.value(contactId.value) || {} : {}
);
const metadata = computed(() =>
  contextMatches.value ? metadataGetter.value(props.conversationId) || {} : {}
);
const definition = computed(() =>
  CONVERSATION_TOOLS.find(item => item.key === props.tool)
);
const allowed = computed(
  () =>
    contextMatches.value &&
    definition.value &&
    (props.tool !== 'macros' ||
      featureEnabled.value(props.accountId, FEATURE_FLAGS.MACROS) === true)
);
const component = computed(
  () =>
    ({
      conversation_actions: ConversationAction,
      macros: MacrosList,
      conversation_info: ConversationInfo,
      contact_attributes: CustomAttributes,
      contact_notes: ContactNotes,
      shared_files: SharedFiles,
      previous_conversation: ContactConversations,
      conversation_participants: ConversationParticipant,
    })[props.tool]
);
const componentProps = computed(() => {
  switch (props.tool) {
    case 'conversation_info':
      return {
        conversationAttributes: metadata.value.additional_attributes || {},
        contactAttributes: contact.value.additional_attributes || {},
      };
    case 'contact_attributes':
      return {
        attributeType: 'contact_attribute',
        attributeFrom: 'conversation_contact_panel',
        contactId: contactId.value,
        emptyStateMessage: t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND'),
      };
    case 'contact_notes':
      return { contactId: contactId.value };
    case 'previous_conversation':
      return {
        contactId: contactId.value,
        conversationId: props.conversationId,
        embedded: true,
      };
    case 'shared_files':
      return {};
    default:
      return {
        conversationId: props.conversationId,
        inboxId: currentChat.value?.inbox_id,
      };
  }
});
const needsContact = computed(() =>
  ['contact_attributes', 'contact_notes', 'previous_conversation'].includes(
    props.tool
  )
);
const prepare = async () => {
  generation += 1;
  const version = generation;
  failed.value = false;
  loading.value = false;
  if (!allowed.value) return;
  const tasks = [];
  if (['conversation_info', 'contact_attributes'].includes(props.tool)) {
    if (contactId.value)
      tasks.push([
        'contact:' + contactId.value,
        'contacts/show',
        { id: contactId.value },
      ]);
    tasks.push(['attributes', 'attributes/get', 0]);
  }
  if (props.tool === 'conversation_actions') tasks.push(['teams', 'teams/get']);
  if (props.tool === 'shared_files' && !attachmentsLoaded.value)
    tasks.push([
      'files:' + props.conversationId,
      'fetchAllAttachments',
      props.conversationId,
    ]);
  loading.value = tasks.some(([key]) => !prepared.has(key));
  try {
    await Promise.all(
      tasks
        .filter(([key]) => !prepared.has(key))
        .map(async ([key, action, payload]) => {
          await store.dispatch(action, payload);
          if (version === generation) prepared.add(key);
        })
    );
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(
  [
    () => props.tool,
    () => props.accountId,
    () => props.conversationId,
    contactId,
    allowed,
  ],
  prepare,
  { immediate: true }
);
</script>

<template>
  <section
    v-if="allowed"
    class="min-h-0 flex-1 overflow-y-auto p-4"
    data-testid="inbox-conversation-tools"
  >
    <h3
      class="mb-4 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
    >
      <span :class="definition.icon" class="size-4 text-n-brand" />
      {{ definition.label(t) }}
    </h3>
    <div v-if="loading" class="flex justify-center p-6"><Spinner /></div>
    <div
      v-else-if="failed"
      role="alert"
      class="rounded-lg bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      <button
        type="button"
        class="ml-2 rounded-md border border-n-weak px-3 py-1"
        @click="prepare"
      >
        {{ t('CHAT_LIST.RETRY') }}
      </button>
    </div>
    <p v-else-if="needsContact && !contactId" class="text-sm text-n-slate-10">
      {{ t('JRC_CONTACT_CENTER.INBOX_360.NO_CUSTOMER') }}
    </p>
    <component
      :is="component"
      v-else
      :key="`${accountId}:${conversationId}:${tool}`"
      v-bind="componentProps"
    />
  </section>
  <template v-else />
</template>
