<script setup>
import { nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  scope: { type: String, required: true },
  reason: { type: String, required: true },
  label: { type: String, required: true },
  confirmation: { type: Object, default: null },
  canConfirm: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm']);
const { t } = useI18n();
const dialog = ref(null);
const reviewOpen = ref(false);
const submitted = ref(false);
const open = async () => {
  if (!props.canConfirm || props.disabled || props.busy || props.confirmation)
    return;
  submitted.value = false;
  reviewOpen.value = true;
  await nextTick();
  if (reviewOpen.value) dialog.value?.open();
};
const confirm = () => {
  if (
    !props.canConfirm ||
    props.disabled ||
    props.busy ||
    props.confirmation ||
    submitted.value
  )
    return;
  submitted.value = true;
  emit('confirm');
};
watch([() => props.scope, () => props.reason, () => props.confirmation], () => {
  dialog.value?.close();
  reviewOpen.value = false;
  submitted.value = false;
});
watch(
  () => props.busy,
  (busy, previous) => {
    if (!busy && previous) submitted.value = false;
  }
);
</script>

<template>
  <section
    class="mt-3 min-w-0 space-y-2 text-sm text-n-slate-12"
    data-ending-confirmation-controls
  >
    <p
      v-if="confirmation?.state === 'confirmed'"
      role="status"
      data-ending-reason-confirmed
    >
      {{
        t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.CONFIRMED', {
          reason: confirmation.reason_label,
        })
      }}
    </p>
    <template v-else>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.HELP') }}
      </p>
      <button
        type="button"
        :disabled="disabled || busy || !canConfirm"
        class="w-full rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-xs font-semibold text-n-blue-11 disabled:opacity-40"
        data-confirm-ending-reason
        @click="open"
      >
        {{ t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.OPEN') }}
      </button>
    </template>
    <Dialog
      v-if="reviewOpen"
      ref="dialog"
      width="lg"
      :title="t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.TITLE')"
      :confirm-button-label="
        t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.CONFIRM')
      "
      :cancel-button-label="t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.CANCEL')"
      :disable-confirm-button="
        disabled || busy || !canConfirm || submitted || Boolean(confirmation)
      "
      :is-loading="busy || submitted"
      :dismissible="!busy && !submitted"
      @confirm="confirm"
      @close="reviewOpen = false"
    >
      <section
        class="min-w-0 space-y-4 text-sm text-n-slate-12"
        data-ending-confirmation-review
      >
        <p class="break-words font-semibold">{{ label }}</p>
        <p>{{ t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.NOTICE') }}</p>
        <p
          class="rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-n-amber-11"
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.FIXED_REASON') }}
        </p>
        <p v-if="error" role="alert" class="text-n-ruby-11">
          {{ t('JRC_CONTACT_CENTER.ENDING_CONFIRMATION.ERROR') }}
        </p>
      </section>
    </Dialog>
  </section>
</template>
