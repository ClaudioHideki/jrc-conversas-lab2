<script setup>
import { useI18n } from 'vue-i18n';
defineProps({ state: { type: Object, required: true } });
const emit = defineEmits(['confirm']);
const { t } = useI18n();
</script>

<template>
  <section
    data-queue-withdrawal-review
    class="min-w-0 space-y-3 rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-slate-12 sm:col-span-2"
  >
    <p v-if="state.error" role="alert" class="text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.INVALID') }}
    </p>
    <template v-else-if="state.review">
      <h3 class="font-semibold">
        {{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.TITLE') }}
      </h3>
      <p role="alert" class="break-words">
        {{
          t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.IMPACT', {
            queue: state.review.queue_name,
            before: state.review.previous_count,
            after: state.review.remaining_count,
          })
        }}
      </p>
      <p class="text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.LOCAL_ONLY') }}
      </p>
      <label class="flex items-start gap-2">
        <input
          type="checkbox"
          :checked="state.confirmed"
          data-manager-withdrawal-confirm
          @change="emit('confirm', $event.target.checked)"
        />
        <span>{{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.CONFIRM') }}</span>
      </label>
    </template>
  </section>
</template>
