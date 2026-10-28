<script setup>
import { ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['goToContactsList']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const dialogRef = ref(null);
const isDeleting = ref(false);

const handleDialogConfirm = async () => {
  const id = route.params.contactId || props.selectedContact?.id;
  if (!id || isDeleting.value) return;

  isDeleting.value = true;
  try {
    await store.dispatch('contacts/delete', id);
    useAlert(t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.API.SUCCESS_MESSAGE'));
    dialogRef.value?.close();
    emit('goToContactsList');
  } catch (error) {
    useAlert(
      error.message ||
        t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.API.ERROR_MESSAGE')
    );
  } finally {
    isDeleting.value = false;
  }
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.TITLE')"
    :description="t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('CONTACTS_LAYOUT.DETAILS.DELETE_DIALOG.CONFIRM')"
    :is-loading="isDeleting"
    :disable-confirm-button="isDeleting"
    @confirm="handleDialogConfirm"
  />
</template>
