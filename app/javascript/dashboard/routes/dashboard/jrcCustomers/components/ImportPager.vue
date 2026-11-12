<script setup>
import { useI18n } from 'vue-i18n';
import { buttonClass } from '../copy';
defineProps({
  page: { type: Number, required: true },
  size: { type: Number, required: true },
  total: { type: Number, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['page']);
const { t } = useI18n();
</script>

<template>
  <nav
    class="mt-4 flex flex-wrap items-center justify-between gap-3"
    :aria-label="t('CRM.CUSTOMER_IMPORTS.PAGINATION')"
  >
    <p class="text-sm text-n-slate-11">
      {{ t('CRM.CUSTOMER_IMPORTS.PAGE', { page, total }) }}
    </p>
    <div class="flex gap-2">
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled || page <= 1"
        @click="emit('page', page - 1)"
      >
        {{ t('CRM.CUSTOMER_IMPORTS.PREVIOUS') }}
      </button>
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled || page * size >= total"
        @click="emit('page', page + 1)"
      >
        {{ t('CRM.CUSTOMER_IMPORTS.NEXT') }}
      </button>
    </div>
  </nav>
</template>
