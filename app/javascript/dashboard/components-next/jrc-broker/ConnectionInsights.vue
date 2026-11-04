<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  inboxId: { type: Number, required: true },
});
const { t } = useI18n();
const summary = ref(null);
const error = ref(false);
let controller;
let generation = 0;
const stop = () => {
  generation += 1;
  controller?.abort();
  summary.value = null;
};
const load = async () => {
  stop();
  error.value = false;
  const current = generation;
  controller = new AbortController();
  try {
    const result = await createJrcBrokerApi(props.accountId).connectionSummary(
      props.inboxId,
      controller.signal
    );
    if (current === generation) summary.value = result;
  } catch {
    if (current === generation) error.value = true;
  }
};
const formatMetric = (value, duration = false) => {
  if (!Number.isFinite(value)) return t('JRC_BROKER.WORKSPACE.NO_DATA');
  if (!duration) return new Intl.NumberFormat().format(value);
  const seconds = Math.round(value);
  return seconds >= 3600
    ? `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`
    : `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
};
const metrics = computed(() => [
  {
    label: 'CONVERSATIONS',
    value: summary.value?.metrics?.conversations_count,
  },
  {
    label: 'FIRST_RESPONSE',
    value: summary.value?.metrics?.avg_first_response_time,
    duration: true,
  },
  {
    label: 'RESOLUTION',
    value: summary.value?.metrics?.avg_resolution_time,
    duration: true,
  },
  { label: 'ELIGIBLE_AGENTS', value: summary.value?.metrics?.eligible_agents },
]);
watch(() => [props.accountId, props.inboxId], load, { immediate: true });
onBeforeUnmount(stop);
</script>

<template>
  <section
    data-testid="connection-insights"
    class="mb-5 rounded-xl border border-n-weak bg-n-solid-1 p-5"
  >
    <h3 class="mb-4 text-sm font-semibold">
      {{ t('JRC_BROKER.WORKSPACE.METRICS_TITLE') }}
    </h3>
    <p v-if="error" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.ERROR.UNAVAILABLE') }}
    </p>
    <p v-else-if="summary && !summary.metrics" class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.WORKSPACE.METRICS_RESTRICTED') }}
    </p>
    <template v-else>
      <dl class="grid grid-cols-2 gap-5 lg:grid-cols-4">
        <div
          v-for="metric in metrics"
          :key="metric.label"
          class="min-w-0 border-l-2 border-n-weak pl-4"
        >
          <dt class="text-xs text-n-slate-11">
            {{ t(`JRC_BROKER.WORKSPACE.${metric.label}`) }}
          </dt>
          <dd class="mt-2 text-xl font-semibold">
            {{ formatMetric(metric.value, metric.duration) }}
          </dd>
        </div>
      </dl>
      <p class="mt-5 text-xs leading-5 text-n-slate-11">
        {{ t('JRC_BROKER.WORKSPACE.METRICS_HELP') }}
      </p>
    </template>
  </section>
</template>
