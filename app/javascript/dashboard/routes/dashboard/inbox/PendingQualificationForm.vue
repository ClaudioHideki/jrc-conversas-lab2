<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  disabled: { type: Boolean, default: false },
  conflict: { type: Boolean, default: false },
  canSave: { type: Boolean, default: false },
  saved: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'complete']);
const reason = defineModel('reason', { type: String, default: '' });
const result = defineModel('result', { type: String, default: '' });
const note = defineModel('note', { type: String, default: '' });
const { t } = useI18n();
</script>

<template>
  <div class="min-w-0" data-pending-qualification-form>
    <div class="mt-4 grid min-w-0 grid-cols-1 gap-3">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.REASON_REQUIRED') }}
        <select
          v-model="reason"
          data-qualification-field="reason"
          :disabled="disabled"
          class="mt-1 h-9 w-full rounded-md border border-n-weak bg-n-solid-1 px-2 text-xs"
        >
          <option value="">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_REASON_PLACEHOLDER') }}
          </option>
          <option
            v-if="
              reason &&
              ![
                'resolved',
                'information',
                'order',
                'callback',
                'transfer',
              ].includes(reason)
            "
            :value="reason"
          >
            {{ reason }}
          </option>
          <option value="resolved">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_RESOLVED') }}
          </option>
          <option value="information">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_INFORMATION') }}
          </option>
          <option value="order">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_ORDER') }}
          </option>
          <option value="callback">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_CALLBACK') }}
          </option>
          <option value="transfer">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.REASON_TRANSFER') }}
          </option>
        </select>
      </label>
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.RESULT_REQUIRED') }}
        <select
          v-model="result"
          data-qualification-field="result"
          :disabled="disabled"
          class="mt-1 h-9 w-full rounded-md border border-n-weak bg-n-solid-1 px-2 text-xs"
        >
          <option value="">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_RESULT_PLACEHOLDER') }}
          </option>
          <option
            v-if="
              result &&
              !['completed', 'pending', 'callback', 'forwarded'].includes(
                result
              )
            "
            :value="result"
          >
            {{ result }}
          </option>
          <option value="completed">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_COMPLETED') }}
          </option>
          <option value="pending">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_PENDING') }}
          </option>
          <option value="callback">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_CALLBACK') }}
          </option>
          <option value="forwarded">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.RESULT_FORWARDED') }}
          </option>
        </select>
      </label>
    </div>
    <label class="mt-3 block text-xs font-medium text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_NOTE') }}
      <textarea
        v-model="note"
        data-qualification-field="note"
        :disabled="disabled"
        maxlength="4000"
        rows="5"
        class="mt-1 w-full resize-none rounded-md border border-n-weak bg-n-solid-1 p-3 text-xs"
        :placeholder="
          t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_NOTE_PLACEHOLDER')
        "
      />
    </label>
    <p v-if="saved" role="status" class="mt-3 text-xs text-n-teal-11">
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_SAVED') }}
    </p>
    <button
      type="button"
      :disabled="disabled || !canSave || conflict"
      class="mt-4 w-full rounded-md border border-n-blue-6 bg-n-blue-2 px-4 py-2 text-xs font-semibold text-n-blue-11 disabled:opacity-40"
      data-save-qualification-draft
      @click="emit('save')"
    >
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_SAVE') }}
    </button>
    <button
      type="button"
      :disabled="disabled || conflict || !reason.trim() || !result.trim()"
      class="mt-4 w-full rounded-md bg-n-brand px-4 py-2 text-xs font-semibold text-white disabled:opacity-40"
      data-complete-qualification
      @click="emit('complete')"
    >
      {{ t('JRC_CONTACT_CENTER.INBOX_360.FINISH_TABULATION') }}
    </button>
  </div>
</template>
