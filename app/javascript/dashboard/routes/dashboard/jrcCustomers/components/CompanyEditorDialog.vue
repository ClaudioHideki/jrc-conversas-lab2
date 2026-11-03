<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CompanyEditor from './CompanyEditor.vue';
import { T } from '../copy';

defineProps({ company: { type: Object, default: null } });
const emit = defineEmits(['saved', 'close']);
const dialog = ref(null);
let active = true;
const saved = company => {
  if (active) emit('saved', company);
};
onMounted(() => dialog.value.open());
onBeforeUnmount(() => {
  active = false;
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="company ? T.editCompany : T.newCompany"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    show-close-button
    overflow-y-auto
    contained
    width="5xl"
    @close="emit('close')"
  >
    <CompanyEditor
      :company="company"
      @saved="saved"
      @cancel="emit('close')"
    />
  </Dialog>
</template>
