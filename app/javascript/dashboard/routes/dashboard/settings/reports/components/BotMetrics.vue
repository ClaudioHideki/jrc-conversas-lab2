<script setup>
import { ref, watch, onMounted } from 'vue';
import ReportMetricCard from './ReportMetricCard.vue';
import ReportsAPI from 'dashboard/api/reports';

const props = defineProps({
  filters: {
    type: Object,
    required: true,
  },
});

const conversationCount = ref('0');
const messageCount = ref('0');
const resolutionRate = ref('0');
const handoffRate = ref('0');

const formatToPercent = value => {
  return value ? `${value}%` : '--';
};

const fetchMetrics = () => {
  if (!props.filters.to || !props.filters.from) {
    return;
  }
  ReportsAPI.getBotMetrics(props.filters).then(response => {
    conversationCount.value = response.data.conversation_count.toLocaleString();
    messageCount.value = response.data.message_count.toLocaleString();
    resolutionRate.value = response.data.resolution_rate.toString();
    handoffRate.value = response.data.handoff_rate.toString();
  });
};

watch(() => props.filters, fetchMetrics, { deep: true });

onMounted(fetchMetrics);
</script>

<template>
  <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.TOOLTIP')"
      :value="conversationCount"
      class="bg-gradient-to-br from-n-violet-3 to-n-solid-1"
    />
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP')"
      :value="messageCount"
      class="bg-gradient-to-br from-n-blue-3 to-n-solid-1"
    />
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.TOOLTIP')"
      :value="formatToPercent(resolutionRate)"
      class="bg-gradient-to-br from-n-teal-3 to-n-solid-1"
    />
    <ReportMetricCard
      :label="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.LABEL')"
      :info-text="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.TOOLTIP')"
      :value="formatToPercent(handoffRate)"
      class="bg-gradient-to-br from-n-amber-3 to-n-solid-1"
    />
  </div>
</template>
