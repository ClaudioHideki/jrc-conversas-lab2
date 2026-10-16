<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useContactCreation } from 'dashboard/composables/useContactCreation';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { proposalsAPI } from 'dashboard/api/crm';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import CreateNewContactDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue';

const props = defineProps({
  proposalId: { type: Number, required: true },
  publicUrl: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['submitted']);
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { checkPermissions } = usePolicy();
const composer = ref(null);
const contactDialog = ref(null);
const working = ref(false);
let attempt = null;
const identity = () =>
  `${route.params.accountId}:${store.getters.getCurrentUserID}:${props.proposalId}`;
const canCreateContact = computed(() =>
  checkPermissions(['administrator', 'agent', 'contact_manage'])
);
const canSend = computed(
  () =>
    canCreateContact.value &&
    checkPermissions(['jrc_crm']) &&
    checkPermissions([
      'administrator',
      'agent',
      'conversation_manage',
      'conversation_unassigned_manage',
      'conversation_participating_manage',
    ])
);
const initialMessage = computed(() =>
  t('CRM.PROPOSAL_RECIPIENT.MESSAGE', { url: props.publicUrl })
);
const publicPdfUrl = computed(() => `${props.publicUrl}/pdf`);
const whatsappInbox = inbox =>
  inbox.channelType === INBOX_TYPES.WHATSAPP ||
  (inbox.channelType === INBOX_TYPES.TWILIO && inbox.medium === 'whatsapp') ||
  (inbox.channelType === INBOX_TYPES.API && /whatsapp/i.test(inbox.name));

const createContact = useContactCreation(contactDialog, {
  allowed: () => canCreateContact.value && !props.disabled && !working.value,
  getIdentity: identity,
  onCreated: contact => composer.value?.selectContact(contact),
});

const submitDelivery = async ({ payload }) => {
  if (working.value || props.disabled || !canSend.value) return false;
  const startedFor = identity();
  const proposalId = props.proposalId;
  const delivery = {
    contact_id: payload.contactId,
    inbox_id: payload.inboxId,
    content: payload.message?.content,
    template_params: payload.message?.template_params,
  };
  const fingerprint = JSON.stringify([startedFor, delivery]);
  if (attempt?.fingerprint !== fingerprint)
    attempt = { fingerprint, key: crypto.randomUUID() };
  working.value = true;
  try {
    const { data } = await proposalsAPI.sendToRecipient(
      proposalId,
      delivery,
      attempt.key
    );
    if (startedFor !== identity()) return false;
    attempt = null;
    useAlert(t('CRM.PROPOSAL_RECIPIENT.SUCCESS'));
    return data;
  } catch (error) {
    if (startedFor === identity())
      useAlert(
        error.response?.data?.errors?.join(', ') ||
          t('CRM.PROPOSAL_RECIPIENT.ERROR')
      );
    return false;
  } finally {
    working.value = false;
  }
};
</script>

<template>
  <ComposeConversation
    ref="composer"
    :initial-message="initialMessage"
    :inbox-filter="whatsappInbox"
    :submit-handler="submitDelivery"
    :is-submitting="working"
    :disabled="disabled || !canSend"
    @submitted="emit('submitted', $event)"
  >
    <template #trigger>
      <button
        type="button"
        data-proposal-recipient-trigger
        class="rounded-xl border border-n-teal-7 bg-n-teal-2 px-3 py-2 text-sm font-semibold text-n-teal-11 shadow-sm hover:bg-n-teal-3 disabled:opacity-50"
        :disabled="disabled || working || !canSend"
      >
        <span class="i-lucide-user-round-plus mr-1" aria-hidden="true" />
        {{ t('CRM.PROPOSAL_RECIPIENT.BUTTON') }}
      </button>
    </template>
    <template #recipient-actions>
      <div class="space-y-3 border-b border-n-weak px-4 py-3">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CRM.PROPOSAL_RECIPIENT.DESCRIPTION') }}
          </p>
          <button
            v-if="canCreateContact"
            type="button"
            data-proposal-create-contact
            :disabled="working || disabled"
            class="rounded-xl bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
            @click="contactDialog.open()"
          >
            {{ t('JRC_HOME.ACTIONS.CONTACT') }}
          </button>
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('CRM.PROPOSAL_RECIPIENT.TEMPLATE_HINT') }}
        </p>
        <label class="block text-xs font-medium text-n-slate-11">
          {{ t('CRM.PROPOSAL_RECIPIENT.LINK') }}
          <input
            :value="publicUrl"
            readonly
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12"
            @focus="$event.target.select()"
          />
        </label>
        <label class="block text-xs font-medium text-n-slate-11">
          {{ t('CRM.PROPOSAL_RECIPIENT.PDF_LINK') }}
          <input
            :value="publicPdfUrl"
            readonly
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12"
            @focus="$event.target.select()"
          />
        </label>
      </div>
      <CreateNewContactDialog
        ref="contactDialog"
        nested-popover
        @create="createContact"
      />
    </template>
  </ComposeConversation>
</template>
