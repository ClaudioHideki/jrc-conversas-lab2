<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
defineProps({ label: { type: String, required: true }, icon: { type: String, default: '' } });
const { t } = useI18n();
</script>
<template>
  <span class="inline-flex flex-col gap-1" :title="t('JRC_SERVICE_DESK.COMMON.pending_cp4')">
    <Button :label="label" :icon="icon" size="sm" variant="outline" color="slate" disabled type="button" />
    <span class="text-[10px] text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.COMMON.pending_cp4') }}
    </span>
  </span>
</template>
