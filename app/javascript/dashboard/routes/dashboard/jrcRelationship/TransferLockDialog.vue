<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, inputClass } from './definitions';

const props = defineProps({
  record: { type: Object, required: true },
  busy: Boolean,
  error: { type: String, default: '' },
});
const emit = defineEmits(['save', 'close']);
const { t } = useI18n();
const dialog = ref(null);
const locked = ref(props.record.transfer_locked === true);
const existingReason = props.record.settings?.transfer_lock?.reason;
const reason = ref('');
const invalid = ref(false);
const submit = () => {
  if (props.busy) return;
  invalid.value =
    !reason.value.trim() ||
    reason.value.length > 4000 ||
    !props.record.assignment_version;
  if (invalid.value) return;
  emit('save', {
    locked: locked.value,
    reason: reason.value.trim(),
    expected_version: props.record.assignment_version,
  });
};
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    width="2xl"
    :title="t('RELATIONSHIP.TRANSFER_LOCK.TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!busy"
    @close="emit('close')"
  >
    <form
      class="min-w-0 space-y-4"
      @submit.prevent="submit"
    >
      <p class="text-sm">{{ t('RELATIONSHIP.TRANSFER_LOCK.NOTICE') }}</p>
      <p
        v-if="typeof existingReason === 'string' && existingReason"
        class="break-words text-sm"
      >
        {{
          t('RELATIONSHIP.TRANSFER_LOCK.CURRENT_REASON', {
            reason: existingReason,
          })
        }}
      </p>
      <p
        v-if="error || invalid"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ error || t('RELATIONSHIP.TRANSFER_LOCK.REQUIRED') }}
      </p>
      <label class="flex items-center gap-2 text-sm">
        <input
          v-model="locked"
          type="checkbox"
          :disabled="busy"
          data-testid="transfer-locked"
        />
        {{ t('RELATIONSHIP.TRANSFER_LOCK.LOCKED') }}
      </label>
      <label class="block text-sm">
        {{ t('RELATIONSHIP.TRANSFER_LOCK.REASON') }}
        <textarea
          v-model="reason"
          class="resize-y"
          :class="inputClass"
          :disabled="busy"
          required
          maxlength="4000"
          data-testid="transfer-lock-reason"
        />
      </label>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="dialog.close()"
        >
          {{ t('RELATIONSHIP.CLOSE') }}
        </button>
        <button
          type="submit"
          :class="buttonClass"
          :disabled="busy || !record.assignment_version"
        >
          {{ busy ? t('RELATIONSHIP.LOADING') : t('RELATIONSHIP.SAVE') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
