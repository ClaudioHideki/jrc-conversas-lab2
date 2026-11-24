<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEndingRuleActivation } from '../composables/useEndingRuleActivation';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  rule: { type: Object, required: true },
  revision: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['busy', 'denied', 'reload']);
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.TITLE'),
  HINT: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.HINT'),
  REVIEW: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.REVIEW'),
  CONFIRM: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.CONFIRM'),
  WAIT: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.WAIT'),
  RECORDED: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.RECORDED'),
  HISTORICAL: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.HISTORICAL'),
  LOADING: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.LOADING'),
  LOAD_FAILED: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.LOAD_FAILED'),
  RETRY_STATUS: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.RETRY_STATUS'),
  MANUAL_PENDING: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.MANUAL_PENDING'),
  FAILED: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.FAILED'),
  STALE: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.STALE'),
  RELOAD: t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.RELOAD'),
}));
const text = key => labels.value[key];
const {
  reviewed,
  busy,
  receipt,
  previousReceipt,
  loading,
  loaded,
  error,
  stale,
  canSubmit,
  submit,
  load,
} = useEndingRuleActivation({
  accountId: computed(() => props.accountId),
  rule: computed(() => props.rule),
  revision: computed(() => props.revision),
  disabled: computed(() => props.disabled),
  onDenied: () => emit('denied'),
  onBusy: value => emit('busy', value),
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-3"
    data-ending-rule-activation
  >
    <h4 class="break-words text-sm font-semibold">{{ text('TITLE') }}</h4>
    <p class="break-words text-sm text-n-slate-12">{{ text('HINT') }}</p>
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ text('LOADING') }}
    </p>
    <p
      v-if="receipt"
      role="status"
      class="break-words text-sm text-n-teal-11"
      data-ending-activation-receipt
    >
      {{ text('RECORDED') }}
      {{ receipt.version_id }}
      {{ t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SEPARATOR') }}
      {{ receipt.activated_at }}
    </p>
    <template v-else>
      <p v-if="previousReceipt" class="break-words text-sm text-n-slate-11">
        {{ text('HISTORICAL') }}
        {{ previousReceipt.version_id }}
        {{ t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SEPARATOR') }}
        {{ previousReceipt.activated_at }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ text(error) }}
      </p>
      <label class="flex items-start gap-2 text-sm">
        <input
          v-model="reviewed"
          type="checkbox"
          :disabled="disabled || !loaded || loading || busy || stale"
          class="mt-1 shrink-0"
          data-ending-activation-reviewed
        />
        <span class="min-w-0 break-words">{{ text('REVIEW') }}</span>
      </label>
      <div class="flex flex-wrap gap-3">
        <button
          v-if="error === 'LOAD_FAILED'"
          type="button"
          :disabled="disabled || loading || busy"
          class="max-w-full whitespace-normal rounded-lg border border-n-weak px-3 py-2 text-sm"
          @click="load"
        >
          {{ text('RETRY_STATUS') }}
        </button>
        <button
          type="button"
          :disabled="!canSubmit"
          class="max-w-full whitespace-normal rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
          data-ending-activation-confirm
          @click="submit"
        >
          {{ text(busy ? 'WAIT' : 'CONFIRM') }}
        </button>
        <button
          v-if="stale"
          type="button"
          :disabled="busy || disabled"
          class="max-w-full whitespace-normal rounded-lg border border-n-weak px-3 py-2 text-sm"
          data-ending-activation-reload
          @click="emit('reload')"
        >
          {{ text('RELOAD') }}
        </button>
      </div>
    </template>
  </section>
</template>
