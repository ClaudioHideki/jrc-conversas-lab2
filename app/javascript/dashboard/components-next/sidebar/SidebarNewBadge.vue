<script setup>
import { useI18n } from 'vue-i18n';
const { t } = useI18n();
</script>

<template>
  <span
    class="inline-flex h-5 shrink-0 items-center rounded-full bg-n-ruby-9 px-2 text-xxs font-semibold text-white"
    data-testid="sidebar-new-badge"
    >{{ t('SIDEBAR.NEW_BADGE') }}</span
  >
</template>
