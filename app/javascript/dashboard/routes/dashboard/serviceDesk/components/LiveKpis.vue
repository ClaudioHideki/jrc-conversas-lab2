<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useServiceDesk } from '../composables/useServiceDesk';
import KpiCard from './KpiCard.vue';
import { metricTones, metricIcons } from '../helpers/visualTheme';
import State from './ServiceDeskState.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { finiteDuration } from '../helpers/dashboardPresentation';
const props = defineProps({
  query: { type: Object, default: () => ({}) },
  referenceLayout: Boolean,
  supervision: { type: Object, default: null },
  breakdown: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['status-filter', 'metric-filter']);
const { t } = useI18n();
const session = useServiceDesk();
const key = `kpis:${getCurrentInstance().uid}`;
const result = computed(
  () => session.operations?.resource(key) || { status: 'idle', data: null }
);
const metrics = computed(() => {
  let names = ['total', 'active', 'open', 'waiting', 'resolved'];
  if (props.referenceLayout) names = ['active', 'open', 'waiting', 'resolved'];
  if (props.compact) names = ['total', 'active', 'waiting', 'resolved'];
  return names.map(name => {
    let value = null;
    if (result.value.status === 'ready') {
      value = Object.hasOwn(result.value.data.phases, name)
        ? result.value.data.phases[name]
        : result.value.data[name];
    }
    return { name, value };
  });
});
const resolutionSeconds = computed(() =>
  finiteDuration(props.supervision?.sla?.resolution_average_seconds)
);
const resolutionLabel = computed(() => {
  if (resolutionSeconds.value === null) return '';
  const minutes = Math.round(resolutionSeconds.value / 60);
  return minutes < 60
    ? t('JRC_SERVICE_DESK.REDESIGN_LIST.minutes', { count: minutes })
    : t('JRC_SERVICE_DESK.REDESIGN_LIST.hours_minutes', {
        hours: Math.floor(minutes / 60),
        minutes: minutes % 60,
      });
});
const load = () => {
  if (
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.dashboard?.index === true
  )
    return session.operations?.read(key, 'dashboard', { query: props.query });
  return undefined;
};
watch(
  [
    () => props.query,
    () => session.state.status,
    () => session.operations?.state.revision,
  ],
  load,
  { immediate: true, deep: true }
);
onBeforeUnmount(() => session.operations?.cancel(key));
</script>

<template>
  <div
    v-if="session.state.context?.capabilities?.dashboard?.index === true"
    class="mb-4"
  >
    <div
      class="mb-3 grid grid-cols-2 gap-3"
      :class="
        compact
          ? 'lg:grid-cols-4'
          : referenceLayout
            ? 'lg:grid-cols-3 xl:grid-cols-6'
            : 'xl:grid-cols-5'
      "
    >
      <KpiCard
        v-for="metric in metrics"
        :key="metric.name"
        :compact="compact"
        :label="t(`JRC_SERVICE_DESK.OPS.KPI.${metric.name}`)"
        :value="metric.value"
        :tone="metricTones[metric.name]"
        :icon="metricIcons[metric.name]"
        :interactive="result.status === 'ready'"
        @activate="emit('metric-filter', metric.name)"
      />
      <KpiCard
        v-if="referenceLayout"
        :label="t('JRC_SERVICE_DESK.REFINEMENT.overview.resolution')"
        :value="resolutionSeconds"
        :display-value="resolutionLabel"
        tone="iris"
        icon="i-lucide-timer"
        :hint="
          t(
            resolutionSeconds === null
              ? 'JRC_SERVICE_DESK.REFINEMENT.overview.unmeasured'
              : 'JRC_SERVICE_DESK.REFINEMENT.overview.measured_resolution'
          )
        "
      />
      <KpiCard
        v-if="referenceLayout"
        :label="t('JRC_SERVICE_DESK.REFINEMENT.overview.csat')"
        :value="null"
        tone="teal"
        icon="i-lucide-smile"
        :hint="t('JRC_SERVICE_DESK.REFINEMENT.overview.csat_unavailable')"
      />
    </div>
    <State
      v-if="!['ready', 'idle'].includes(result.status)"
      :status="result.status"
      compact
      retry
      @retry="load"
    />
    <p
      v-if="result.status === 'ready' && !compact"
      class="text-xs text-n-slate-11"
    >
      {{ t('JRC_SERVICE_DESK.OPS.kpi_rule') }}
    </p>
    <div
      v-if="breakdown && result.status === 'ready'"
      class="mb-4 grid gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3"
    >
      <h3 class="text-sm font-semibold">
        {{ t('JRC_SERVICE_DESK.OVERVIEW.distribution') }}
      </h3>
      <p v-if="result.data.by_status.length === 0" class="text-sm">
        {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
      </p>
      <div
        v-for="row in result.data.by_status"
        :key="row.id"
        class="flex gap-3 items-center"
      >
        <Button
          size="xs"
          variant="ghost"
          color="slate"
          :label="row.name"
          @click="emit('status-filter', row.id)"
        />
        <progress
          class="flex-1 accent-blue-700"
          :value="row.count"
          :max="Math.max(result.data.total, 1)"
          :aria-label="row.name"
        />
        <span class="text-sm tabular-nums">{{ row.count }}</span>
      </div>
    </div>
  </div>
</template>
