<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EndingAutomationEditor from './EndingAutomationEditor.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const dialog = ref(null);
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.TITLE')"
    width="5xl"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="false"
    :close-on-click-outside="false"
    contained
  >
    <EndingAutomationEditor
      :key="String(props.accountId)"
      :account-id="props.accountId"
      @close="emit('close')"
    />
  </Dialog>
</template>
