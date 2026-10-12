<script setup>
import { ref, computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';

const emit = defineEmits(['create']);

const { t } = useI18n();

const dialogRef = ref(null);
const contactsFormRef = ref(null);
const contact = ref(null);
const submittedDraftKey = ref(null);

const uiFlags = useMapGetter('contacts/getUIFlags');
const isCreatingContact = computed(() => uiFlags.value.isCreating);

const createNewContact = contactItem => {
  contact.value = contactItem;
};

const handleDialogConfirm = async () => {
  if (!contact.value) return;
  submittedDraftKey.value = contactsFormRef.value.draftKey();
  emit('create', contact.value);
};

const onSuccess = () => {
  if (
    contactsFormRef.value &&
    !contactsFormRef.value.resetForm(submittedDraftKey.value)
  )
    return;
  dialogRef.value.close();
};

const closeDialog = () => {
  dialogRef.value.close();
};

const open = () => {
  dialogRef.value.open();
};

defineExpose({ open, dialogRef, contactsFormRef, onSuccess });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    show-close-button
    overflow-y-auto
    @confirm="handleDialogConfirm"
  >
    <header
      class="mb-5 flex items-center gap-4 rounded-2xl border border-n-blue-6 bg-gradient-to-br from-n-blue-2 via-n-solid-2 to-n-teal-2 p-5"
    >
      <span
        class="flex size-12 shrink-0 items-center justify-center rounded-2xl bg-n-blue-3 text-n-blue-11"
      >
        <span class="i-lucide-user-round-plus size-6" aria-hidden="true" />
      </span>
      <h2 class="text-xl font-bold text-n-slate-12">
        {{ t('JRC_HOME.ACTIONS.CONTACT') }}
      </h2>
    </header>
    <ContactsForm
      ref="contactsFormRef"
      is-new-contact
      @update="createNewContact"
    />
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          :label="t('DIALOG.BUTTONS.CANCEL')"
          variant="link"
          type="reset"
          class="h-10 hover:!no-underline hover:text-n-brand"
          @click="closeDialog"
        />
        <Button
          type="submit"
          :label="
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.SAVE_CONTACT')
          "
          color="blue"
          :disabled="contactsFormRef?.isFormInvalid"
          :is-loading="isCreatingContact"
        />
      </div>
    </template>
  </Dialog>
</template>
