<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

defineProps({
  operation: { type: Object, required: true },
  reviewed: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
  canSubmit: { type: Boolean, default: false },
  message: { type: String, default: '' },
});
const emit = defineEmits(['update:reviewed', 'confirm', 'close']);
const { t } = useI18n();
const dialog = ref(null);
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('JRC_CONTACT_CENTER.ENDING_PENDING.TITLE')"
    :description="t('JRC_CONTACT_CENTER.ENDING_PENDING.HINT')"
    width="md"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="!busy"
    :close-on-click-outside="false"
    contained
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-4" data-ending-pending-review>
      <p v-if="message" role="alert" class="break-words text-sm text-n-ruby-11">
        {{ message }}
      </p>
      <p class="break-words text-sm font-semibold">{{ operation.rule_code }}</p>
      <dl class="grid min-w-0 gap-2 text-sm">
        <div>
          <dt class="text-n-slate-11">
            {{ t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.VERSION') }}
          </dt>
          <dd class="break-all">{{ operation.version_id }}</dd>
        </div>
        <div>
          <dt class="text-n-slate-11">
            {{ t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.REQUEST') }}
          </dt>
          <dd class="break-all">{{ operation.request_id }}</dd>
        </div>
      </dl>
      <label class="flex items-start gap-2 text-sm">
        <input
          type="checkbox"
          :checked="reviewed"
          :disabled="busy"
          class="mt-1 shrink-0"
          data-ending-pending-confirmed
          @change="emit('update:reviewed', $event.target.checked)"
        />
        <span class="min-w-0 break-words">{{
          t('JRC_CONTACT_CENTER.ENDING_PENDING.REVIEW')
        }}</span>
      </label>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          :disabled="!canSubmit"
          class="max-w-full whitespace-normal rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
          data-run-selected-ending-pending
          @click="emit('confirm')"
        >
          {{
            busy
              ? t('JRC_CONTACT_CENTER.ENDING_PENDING.RUNNING')
              : t('JRC_CONTACT_CENTER.ENDING_PENDING.CONFIRM')
          }}
        </button>
        <button
          type="button"
          :disabled="busy"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-40"
          @click="emit('close')"
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_PENDING.CANCEL') }}
        </button>
      </div>
    </div>
  </Dialog>
</template>
