<script setup>
import {
  reactive,
  ref,
  computed,
  onMounted,
  watch,
  nextTick,
  onBeforeUnmount,
} from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useRoute } from 'vue-router';
import { useEventBus } from '@vueuse/core';
import { quickActionCommand } from 'dashboard/components-next/layout/useQuickActionTarget';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { ExceptionWithMessage } from 'shared/helpers/CustomErrors';
import { debounce } from '@chatwoot/utils';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  createContactSearcher,
  createNewContact,
  fetchContactableInboxes,
  processContactableInboxes,
  mergeInboxDetails,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import ComposeNewConversationForm from 'dashboard/components-next/NewConversation/components/ComposeNewConversationForm.vue';

const props = defineProps({
  initialMessage: { type: String, default: '' },
  submitHandler: { type: Function, default: null },
  inboxFilter: { type: Function, default: null },
  isSubmitting: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  contactId: {
    type: String,
    default: null,
  },
  align: {
    type: String,
    default: 'end',
  },
});

const emit = defineEmits(['close', 'submitted']);

const searchContacts = createContactSearcher();
const store = useStore();
const route = useRoute();
const { t } = useI18n();

const { fetchSignatureFlagFromUISettings } = useUISettings();

const popoverRef = ref(null);
const contacts = ref([]);
const selectedContact = ref(null);
const targetInbox = ref(null);
const isCreatingContact = ref(false);
const isFetchingInboxes = ref(false);
const isSearching = ref(false);
let selectionVersion = 0;

const formState = reactive({
  message: props.initialMessage,
  subject: '',
  ccEmails: '',
  bccEmails: '',
  attachedFiles: [],
});

const clearFormState = () => {
  Object.assign(formState, {
    subject: '',
    ccEmails: '',
    bccEmails: '',
    attachedFiles: [],
  });
};

const contactById = useMapGetter('contacts/getContactById');
const contactsUiFlags = useMapGetter('contacts/getUIFlags');
const currentUser = useMapGetter('getCurrentUser');
const globalConfig = useMapGetter('globalConfig/get');
const uiFlags = useMapGetter('contactConversations/getUIFlags');
const messageSignature = useMapGetter('getMessageSignature');
const inboxesList = useMapGetter('inboxes/getInboxes');

const sendWithSignature = computed(() =>
  fetchSignatureFlagFromUISettings(targetInbox.value?.channelType)
);

const directUploadsEnabled = computed(
  () => globalConfig.value.directUploadsEnabled
);

const activeContact = computed(() => contactById.value(props.contactId));

const onContactSearch = debounce(
  async query => {
    const accountId = route.params.accountId;
    const userId = store.getters.getCurrentUserID;
    isSearching.value = true;
    contacts.value = [];
    try {
      const results = await searchContacts(query);
      if (
        accountId !== route.params.accountId ||
        userId !== store.getters.getCurrentUserID
      )
        return;
      // null means the request was aborted (a newer search is in-flight),
      if (results === null) return;
      contacts.value = results;
      isSearching.value = false;
    } catch (error) {
      isSearching.value = false;
      useAlert(t('COMPOSE_NEW_CONVERSATION.CONTACT_SEARCH.ERROR_MESSAGE'));
    }
  },
  400,
  false
);

const resetContacts = () => {
  contacts.value = [];
};

const filterInboxes = inboxes =>
  props.inboxFilter ? inboxes.filter(props.inboxFilter) : inboxes;

const handleSelectedContact = async ({ value, action, ...rest }) => {
  selectionVersion += 1;
  const version = selectionVersion;
  let contact;
  if (action === 'create') {
    isCreatingContact.value = true;
    try {
      contact = await createNewContact(value);
      isCreatingContact.value = false;
    } catch (error) {
      isCreatingContact.value = false;
      return;
    }
  } else {
    contact = rest;
  }
  if (version !== selectionVersion) return;
  selectedContact.value = contact;
  targetInbox.value = null;
  contacts.value = [];
  if (contact?.id) {
    isFetchingInboxes.value = true;
    try {
      const contactableInboxes = await fetchContactableInboxes(contact.id);
      if (version !== selectionVersion) return;
      // Merge the processed contactableInboxes with the inboxesList
      selectedContact.value.contactInboxes = filterInboxes(
        mergeInboxDetails(contactableInboxes, inboxesList.value)
      );

      isFetchingInboxes.value = false;
    } catch (error) {
      if (version === selectionVersion) isFetchingInboxes.value = false;
    }
  }
};

const selectContact = contact =>
  handleSelectedContact({
    action: 'select',
    ...camelcaseKeys(contact, { deep: true }),
  });

defineExpose({ selectContact });

const handleTargetInbox = inbox => {
  targetInbox.value = inbox;
  if (!inbox) clearFormState();
  resetContacts();
};

const clearSelectedContact = () => {
  selectionVersion += 1;
  isFetchingInboxes.value = false;
  isSearching.value = false;
  selectedContact.value = null;
  targetInbox.value = null;
  clearFormState();
};

const closeCompose = () => {
  selectionVersion += 1;
  isFetchingInboxes.value = false;
  popoverRef.value?.hide();
  if (!props.contactId) {
    // If contactId is passed as prop
    // Then don't allow to remove the selected contact
    selectedContact.value = null;
  }
  targetInbox.value = null;
  resetContacts();
};

const discardCompose = () => {
  clearFormState();
  formState.message = props.initialMessage;
  closeCompose();
};

const createConversation = async ({ payload, isFromWhatsApp }) => {
  try {
    if (props.submitHandler) {
      const result = await props.submitHandler({ payload, isFromWhatsApp });
      if (!result) return false;
      discardCompose();
      emit('submitted', result);
      return true;
    }
    const data = await store.dispatch('contactConversations/create', {
      params: payload,
      isFromWhatsApp,
    });
    const action = {
      type: 'link',
      to: `/app/accounts/${data.account_id}/conversations/${data.id}`,
      message: t('COMPOSE_NEW_CONVERSATION.FORM.GO_TO_CONVERSATION'),
    };
    discardCompose();
    useAlert(t('COMPOSE_NEW_CONVERSATION.FORM.SUCCESS_MESSAGE'), action);
    return true; // Return success
  } catch (error) {
    useAlert(
      error instanceof ExceptionWithMessage
        ? error.data
        : t('COMPOSE_NEW_CONVERSATION.FORM.ERROR_MESSAGE')
    );
    return false; // Return failure
  }
};

const onPopoverShow = () => {
  if (props.disabled) {
    popoverRef.value?.hide();
    return;
  }
  if (props.initialMessage) formState.message = props.initialMessage;
  // Flag to prevent triggering drag n drop,
  // When compose modal is active
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
};

const onPopoverHide = () => {
  emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false);
  emit('close');
};

const activateQuickAction = async key => {
  closeCompose();
  await nextTick();
  useEventBus(quickActionCommand).emit({
    key,
    accountId: Number(route.params.accountId),
    userId: store.getters.getCurrentUserID,
  });
};
watch(() => route.params.accountId, discardCompose);
watch(() => store.getters.getCurrentUserID, discardCompose);
onBeforeUnmount(() => emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false));

watch(
  activeContact,
  (currentContact, previousContact) => {
    if (currentContact && props.contactId) {
      // Reset on contact change
      if (currentContact?.id !== previousContact?.id) {
        clearSelectedContact();
        clearFormState();
        formState.message = '';
      }

      // First process the contactable inboxes to get the right structure
      const processedInboxes = processContactableInboxes(
        currentContact.contactInboxes || []
      );
      // Then Merge processedInboxes with the inboxes list
      selectedContact.value = {
        ...currentContact,
        contactInboxes: filterInboxes(
          mergeInboxDetails(processedInboxes, inboxesList.value)
        ),
      };
    }
  },
  { immediate: true, deep: true }
);

onMounted(() => resetContacts());
</script>

<template>
  <Popover
    ref="popoverRef"
    :align="align"
    :show-content-border="false"
    :close-on-scroll="false"
    modal
    modal-class="max-w-7xl"
    :modal-label="t('JRC_HOME.COMPOSE.TITLE')"
    @show="onPopoverShow"
    @hide="onPopoverHide"
  >
    <template #default="{ isOpen }">
      <slot name="trigger" :is-open="isOpen" />
    </template>
    <template #content>
      <ComposeNewConversationForm
        :form-state="formState"
        :contacts="contacts"
        :contact-id="contactId"
        :is-loading="isSearching"
        :current-user="currentUser"
        :selected-contact="selectedContact"
        :target-inbox="targetInbox"
        :is-creating-contact="isCreatingContact"
        :is-fetching-inboxes="isFetchingInboxes"
        :is-direct-uploads-enabled="directUploadsEnabled"
        :contact-conversations-ui-flags="{
          ...uiFlags,
          isCreating: uiFlags?.isCreating || isSubmitting,
        }"
        :contacts-ui-flags="contactsUiFlags"
        :message-signature="messageSignature"
        :send-with-signature="sendWithSignature"
        workspace
        @search-contacts="onContactSearch"
        @reset-contact-search="resetContacts"
        @update-selected-contact="handleSelectedContact"
        @update-target-inbox="handleTargetInbox"
        @clear-selected-contact="clearSelectedContact"
        @create-conversation="createConversation"
        @discard="discardCompose"
        @action="activateQuickAction"
      >
        <template #recipient-actions>
          <slot name="recipient-actions" />
        </template>
      </ComposeNewConversationForm>
    </template>
  </Popover>
</template>
