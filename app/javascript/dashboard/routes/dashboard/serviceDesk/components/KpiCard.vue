<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
defineProps({ label: { type: String, required: true }, icon: { type: String, default: 'i-lucide-chart-no-axes-combined' }, value: { type: Number, default: null, validator: value => value === null || (Number.isSafeInteger(value) && value >= 0) } });
const { t } = useI18n();
</script>
<template>
  <section
    class="sd-kpi"
    :title="t('JRC_SERVICE_DESK.OVERVIEW.kpi_help')"
    :aria-label="`${label}: ${value === null ? t('JRC_SERVICE_DESK.OVERVIEW.kpi_label') : value}`"
  >
    <div class="flex items-center justify-between gap-2">
      <span class="text-xs font-medium text-n-slate-11">
        {{ label }}
      </span>
      <Icon :icon="icon" class="size-5 text-n-blue-11" />
    </div>
    <strong class="text-3xl leading-none text-n-slate-10 font-semibold">
      {{ value === null ? t('JRC_SERVICE_DESK.COMMON.no_value') : value }}
    </strong>
    <span class="text-xs text-n-slate-11">
      {{ t(value === null ? 'JRC_SERVICE_DESK.COMMON.not_available' : 'JRC_SERVICE_DESK.OPS.real_count') }}
    </span>
  </section>
</template>
