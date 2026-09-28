<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const downloadUrl = computed(() => {
  // The installed Desktop already has the application. Keep its external
  // navigation policy unchanged; this download action is for the Web header.
  if (window.jrcSoftphoneDesktop) return '';
  try {
    const url = new URL(window.chatwootConfig?.softphoneDownloadUrl);
    return url.protocol === 'https:' && !url.username && !url.password
      ? url.href
      : '';
  } catch {
    return '';
  }
});
</script>

<template>
  <span class="contents">
    <a
      v-if="downloadUrl"
      :href="downloadUrl"
      target="_blank"
      rel="noopener noreferrer"
      class="flex h-10 items-center gap-2 rounded-full px-3 text-sm text-n-slate-11 transition hover:bg-n-alpha-1 hover:text-n-brand"
    >
      <span class="i-lucide-download size-4" aria-hidden="true" />
      <span>{{ t('SIDEBAR.DOWNLOAD_JRC_SOFTPHONE') }}</span>
    </a>
  </span>
</template>
