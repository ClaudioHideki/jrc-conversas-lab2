<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';

defineProps({ contact: { type: Object, required: true } });
const { t } = useI18n();
const { checkPermissions } = usePolicy();
const composer = ref(null);
const canConverse = computed(() =>
  checkPermissions([
    'administrator',
    'conversation_manage',
    'conversation_unassigned_manage',
    'conversation_participating_manage',
  ])
);
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <ComposeConversation
      v-if="canConverse"
      ref="composer"
      :contact-id="String(contact.id)"
      native-dialog
    >
      <template #trigger>
        <Button
          :label="t('CRM.CONTACT_MASTER_360.NEW_CONVERSATION')"
          size="sm"
          @click="composer.selectContact(contact)"
        />
      </template>
    </ComposeConversation>
    <VoiceCallButton
      :contact-id="contact.id"
      :phone="contact.phone_number || ''"
      :label="t('CONTACT_PANEL.CALL')"
    />
    <a
      v-if="contact.email"
      :href="`mailto:${encodeURIComponent(contact.email)}`"
      class="rounded-lg border border-n-amber-6 bg-n-amber-3 px-3 py-2 text-sm font-semibold text-n-amber-12"
    >
      {{ t('CRM.OPERATIONAL_CONTACTS.EMAIL') }}
    </a>
  </div>
</template>
