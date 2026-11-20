<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AcwFormFields from '../jrcContactCenter/components/AcwFormFields.vue';

const props = defineProps({
  disabled: { type: Boolean, default: false },
  conflict: { type: Boolean, default: false },
  canSave: { type: Boolean, default: false },
  saved: { type: Boolean, default: false },
  reasonOptions: { type: Array, default: () => [] },
  reasonRequired: { type: Boolean, default: false },
  reasonRevision: { type: Number, default: null },
  formsPresent: { type: Boolean, default: false },
  formReasonCodes: { type: Array, default: () => [] },
  selectedForm: { type: Object, default: null },
  formValues: { type: Object, default: () => ({}) },
  formLoading: { type: Boolean, default: false },
  formError: { type: Boolean, default: false },
  formReady: { type: Boolean, default: true },
});
const emit = defineEmits([
  'save',
  'complete',
  'updateFormValues',
  'reloadForm',
]);
const reason = defineModel('reason', { type: String, default: '' });
const result = defineModel('result', { type: String, default: '' });
const note = defineModel('note', { type: String, default: '' });
const { t } = useI18n();
const separator = ' · ';
const reasons = computed(() => {
  const choices = new Map();
  if (!props.reasonRequired) {
    Object.entries({
      resolved: t('JRC_CONTACT_CENTER.INBOX_360.REASON_RESOLVED'),
      information: t('JRC_CONTACT_CENTER.INBOX_360.REASON_INFORMATION'),
      order: t('JRC_CONTACT_CENTER.INBOX_360.REASON_ORDER'),
      callback: t('JRC_CONTACT_CENTER.INBOX_360.REASON_CALLBACK'),
      transfer: t('JRC_CONTACT_CENTER.INBOX_360.REASON_TRANSFER'),
    }).forEach(([key, label]) => choices.set(key, label));
    props.formReasonCodes.forEach(code => {
      if (!choices.has(code)) choices.set(code, code);
    });
    if (reason.value && !choices.has(reason.value))
      choices.set(reason.value, reason.value);
  }
  props.reasonOptions.forEach(row => {
    choices.set(row.code, row.name);
  });
  return [...choices].map(([code, label]) => ({ code, label }));
});
</script>

<template>
  <div class="min-w-0" data-pending-qualification-form>
    <p
      v-if="reasonRevision"
      class="mt-3 text-xs text-n-slate-11"
      data-ending-reason-version
    >
      {{
        t('JRC_CONTACT_CENTER.ENDING_REASONS.OPERATIONAL_VERSION', {
          version: reasonRevision,
        })
      }}
    </p>
    <p v-if="reasonRequired" class="mt-2 text-xs text-n-amber-11">
      {{ t('JRC_CONTACT_CENTER.ENDING_REASONS.OPERATIONAL_REQUIRED') }}
    </p>
    <div
      v-if="reasonRevision && !formsPresent && (formLoading || formError)"
      class="mt-3 space-y-2 text-sm"
      data-ending-context-status
    >
      <p v-if="formLoading" role="status" class="text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <template v-else>
        <p role="alert" class="text-n-ruby-11">
          {{ t('JRC_CONTACT_CENTER.ENDING_REASONS.CONTEXT_ERROR') }}
        </p>
        <button
          type="button"
          :disabled="disabled"
          class="rounded-lg border border-n-weak px-3 py-2"
          data-reload-ending-context
          @click="emit('reloadForm')"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </template>
    </div>
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
          <option v-for="{ code, label } in reasons" :key="code" :value="code">
            {{ label }}
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
    <section
      v-if="formsPresent"
      class="mt-4 min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
      data-qualification-form-context
    >
      <h4 class="text-sm font-semibold text-n-slate-12">
        {{ t('JRC_CONTACT_CENTER.ACW_FORMS.OPERATIONAL_TITLE') }}
      </h4>
      <p v-if="formLoading" role="status" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <div v-else-if="formError" class="space-y-2 text-sm text-n-ruby-11">
        <p role="alert">
          {{ t('JRC_CONTACT_CENTER.ACW_FORMS.OPERATIONAL_ERROR') }}
        </p>
        <button
          type="button"
          :disabled="disabled"
          class="rounded-lg border border-n-weak px-3 py-2 text-n-slate-12"
          data-reload-qualification-form
          @click="emit('reloadForm')"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </div>
      <template v-else-if="selectedForm">
        <p class="break-words text-sm text-n-slate-12">
          {{ selectedForm.name }}{{ separator }}
          {{
            t('JRC_CONTACT_CENTER.ACW_FORMS.VERSION_LABEL', {
              version: selectedForm.revision,
            })
          }}
        </p>
        <AcwFormFields
          :model-value="formValues"
          :definition="selectedForm.definition"
          :disabled="disabled || conflict"
          @update:model-value="emit('updateFormValues', $event)"
        />
      </template>
      <p v-else class="text-sm text-n-slate-11">
        {{
          reason
            ? t('JRC_CONTACT_CENTER.ACW_FORMS.NO_FORM_FOR_REASON')
            : t('JRC_CONTACT_CENTER.ACW_FORMS.NO_SELECTED_FORM')
        }}
      </p>
    </section>
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
    <p
      v-if="saved"
      role="status"
      data-qualification-draft-saved
      class="mt-3 text-xs text-n-teal-11"
    >
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_SAVED') }}
    </p>
    <button
      type="button"
      :disabled="disabled || !canSave || conflict || formLoading || formError"
      class="mt-4 w-full rounded-md border border-n-blue-6 bg-n-blue-2 px-4 py-2 text-xs font-semibold text-n-blue-11 disabled:opacity-40"
      data-save-qualification-draft
      @click="emit('save')"
    >
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_SAVE') }}
    </button>
    <button
      type="button"
      :disabled="
        disabled || conflict || !formReady || !reason.trim() || !result.trim()
      "
      class="mt-4 w-full rounded-md bg-n-brand px-4 py-2 text-xs font-semibold text-white disabled:opacity-40"
      data-complete-qualification
      @click="emit('complete')"
    >
      {{ t('JRC_CONTACT_CENTER.INBOX_360.FINISH_TABULATION') }}
    </button>
  </div>
</template>
