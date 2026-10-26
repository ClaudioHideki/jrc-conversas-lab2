<script setup>
defineProps({
  filename: { type: String, default: '' },
  state: { type: String, required: true },
});
const emit = defineEmits(['retry']);
</script>

<template>
  <div class="flex flex-col gap-1 px-3 py-2" role="status" aria-live="polite">
    <span class="break-all text-sm font-medium">
      {{ filename || $t('COMPONENTS.PROTECTED_ATTACHMENT.FILE') }}
    </span>
    <span v-if="state === 'loading'" class="text-xs">
      {{ $t('COMPONENTS.PROTECTED_ATTACHMENT.LOADING') }}
    </span>
    <span v-else-if="state === 'scan_pending'" class="text-xs">
      {{ $t('COMPONENTS.PROTECTED_ATTACHMENT.SCAN_PENDING') }}
    </span>
    <span v-else-if="state === 'temporary_error'" class="text-xs">
      {{ $t('COMPONENTS.PROTECTED_ATTACHMENT.TEMPORARY_ERROR') }}
    </span>
    <span v-else class="text-xs">
      {{ $t('COMPONENTS.PROTECTED_ATTACHMENT.UNAVAILABLE') }}
    </span>
    <button
      v-if="['scan_pending', 'temporary_error'].includes(state)"
      type="button"
      class="self-start text-xs font-medium underline"
      @click="emit('retry')"
    >
      {{ $t('COMPONENTS.PROTECTED_ATTACHMENT.RETRY') }}
    </button>
  </div>
</template>
