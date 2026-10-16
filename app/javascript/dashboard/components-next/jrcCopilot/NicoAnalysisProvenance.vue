<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ report: { type: Object, required: true } });
const { t, locale } = useI18n();
const formatTime = value =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    timeZoneName: 'short',
  }).format(new Date(value));
</script>

<template>
  <div class="space-y-2 text-xs" data-testid="nico-analysis-provenance">
    <p class="rounded-lg bg-n-amber-3 p-2 text-n-amber-12">
      {{ t('JRC_NICO.UX.ANALYSIS_INFERRED') }}
    </p>
    <dl
      v-if="report.analysis_version === 1 && report.source_window"
      class="grid grid-cols-2 gap-2 text-n-slate-11"
    >
      <dt>{{ t('JRC_NICO.UX.ANALYSIS_MESSAGES') }}</dt>
      <dd>{{ report.message_count }}</dd>
      <dt>{{ t('JRC_NICO.UX.ANALYSIS_MODEL') }}</dt>
      <dd class="break-words">{{ report.model }}</dd>
      <dt>{{ t('JRC_NICO.UX.ANALYSIS_FROM') }}</dt>
      <dd>
        <time :datetime="report.source_window.first_message_at">
          {{ formatTime(report.source_window.first_message_at) }}
        </time>
      </dd>
      <dt>{{ t('JRC_NICO.UX.ANALYSIS_TO') }}</dt>
      <dd>
        <time :datetime="report.source_window.last_message_at">
          {{ formatTime(report.source_window.last_message_at) }}
        </time>
      </dd>
      <dt>{{ t('JRC_NICO.UX.ANALYSIS_TRUNCATED') }}</dt>
      <dd>{{ report.source_window.truncated_message_count }}</dd>
    </dl>
  </div>
</template>
