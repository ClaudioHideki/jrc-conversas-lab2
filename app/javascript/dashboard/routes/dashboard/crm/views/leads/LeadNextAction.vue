<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  status: { type: String, required: true },
  canOpenDeal: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['qualify', 'convert', 'deal']);
const { t } = useI18n();
</script>

<template>
  <button
    v-if="['new', 'in_contact'].includes(status)"
    type="button"
    class="!p-0 text-left text-xs font-semibold text-n-iris-11 hover:underline disabled:opacity-50"
    :disabled="disabled"
    @click.stop="emit('qualify')"
  >
    {{ t('CRM.LIST_LAYOUT.QUALIFY') }}
  </button>
  <button
    v-else-if="status === 'qualified'"
    type="button"
    class="!p-0 text-left text-xs font-semibold text-n-teal-11 hover:underline"
    @click.stop="emit('convert')"
  >
    {{ t('CRM.LIST_LAYOUT.CONVERT') }}
  </button>
  <button
    v-else-if="status === 'converted' && canOpenDeal"
    type="button"
    class="rounded-md border border-n-blue-6 bg-n-blue-2 !px-2 !py-0.5 text-xs font-semibold text-n-blue-11 hover:bg-n-blue-3"
    @click.stop="emit('deal')"
  >
    {{ t('CRM.LIST_LAYOUT.OPEN_DEAL') }}
  </button>
  <span v-else class="text-xs text-n-slate-11">{{
    t('CRM.LIST_LAYOUT.NO_NEXT_STEP')
  }}</span>
</template>
