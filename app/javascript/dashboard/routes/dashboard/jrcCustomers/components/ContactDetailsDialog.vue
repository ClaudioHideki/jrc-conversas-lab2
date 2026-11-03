<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Contact360Panel from './Contact360Panel.vue';
import { useCustomerMaster } from '../useCustomerMaster';

defineProps({ contactId: { type: [Number, String], required: true } });
const emit = defineEmits(['close', 'updated']);
const { t } = useI18n();
const { accountScopedRoute } = useCustomerMaster();
const dialog = ref(null);
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('CRM.CONTACT_MASTER_360.TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    show-close-button
    overflow-y-auto
    contained
    width="5xl"
    @close="emit('close')"
  >
    <RouterLink
      :to="accountScopedRoute('contacts_edit', { contactId })"
      class="inline-block rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12"
    >
      {{ t('CRM.CUSTOMER_MASTER_360.OPEN_FULL_PAGE') }}
    </RouterLink>
    <Contact360Panel
      :contact-id="contactId"
      @updated="emit('updated')"
      @denied="emit('close')"
    />
  </Dialog>
</template>
