<script setup>
import { useI18n } from 'vue-i18n';
defineProps({ screen: { type: String, required: true } });
const { t, te } = useI18n();
</script>

<template>
  <details
    v-if="te(`JRC_SERVICE_DESK.EXPERIENCE.help.${screen}`)"
    class="mb-4 rounded-xl border border-n-weak bg-n-solid-1 p-3"
  >
    <summary class="text-xs text-n-slate-11 cursor-pointer">
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.screen_guide') }}
    </summary>
    <p class="text-sm text-n-slate-11 mt-2">
      {{ t(`JRC_SERVICE_DESK.EXPERIENCE.help.${screen}`) }}
    </p>
  </details>
</template>
