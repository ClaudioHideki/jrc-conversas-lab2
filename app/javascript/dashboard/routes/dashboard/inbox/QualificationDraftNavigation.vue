<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  enabled: { type: Boolean, default: true },
  dirty: { type: Boolean, default: false },
  conflict: { type: Boolean, default: false },
  saving: { type: Boolean, default: false },
  authorityKey: { type: String, default: '' },
});
const { t } = useI18n();
const dialog = ref(null);
const needsReview = computed(
  () => props.enabled && (props.dirty || props.conflict)
);
let decision = null;
let pending = null;

const finish = approved => {
  if (!decision) return;
  const resolve = decision;
  decision = null;
  pending = null;
  dialog.value.close();
  resolve(approved);
};
const canLeave = () => {
  if (!props.enabled) return true;
  if (props.saving) return false;
  if (!needsReview.value) return true;
  if (pending) return pending;
  pending = new Promise(resolve => {
    decision = resolve;
  });
  dialog.value.open();
  return pending;
};
const beforeUnload = event => {
  if (!props.enabled || (!needsReview.value && !props.saving)) return;
  event.preventDefault();
  event.returnValue = '';
};
onBeforeRouteLeave(canLeave);
onBeforeRouteUpdate((to, from) =>
  JSON.stringify(to.params) === JSON.stringify(from.params) ? true : canLeave()
);
watch(
  () => props.authorityKey,
  () => finish(false)
);
onMounted(() => window.addEventListener('beforeunload', beforeUnload));
onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', beforeUnload);
  finish(false);
});
</script>

<template>
  <Dialog
    ref="dialog"
    type="alert"
    width="sm"
    contained
    :title="t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_LEAVE_TITLE')"
    :description="t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_LEAVE_DESCRIPTION')"
    :cancel-button-label="
      t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_LEAVE_STAY')
    "
    :confirm-button-label="
      t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_LEAVE_DISCARD')
    "
    :close-on-click-outside="false"
    @confirm="finish(true)"
    @close="finish(false)"
  />
</template>
