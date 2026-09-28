<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useServiceDesk } from '../composables/useServiceDesk';
import KpiCard from './KpiCard.vue';
import State from './ServiceDeskState.vue';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({ query: { type: Object, default: () => ({}) }, breakdown: { type: Boolean, default: false } });
const emit = defineEmits(['status-filter']);
const { t } = useI18n();
const session = useServiceDesk();
const key = `kpis:${getCurrentInstance().uid}`;
const result = computed(() => session.operations?.resource(key) || { status: 'idle', data: null });
const metrics = computed(() => ['total', 'active', 'open', 'waiting', 'resolved', 'closed', 'cancelled'].map(name => ({ name,
  value: result.value.status === 'ready' ? (Object.hasOwn(result.value.data.phases, name) ? result.value.data.phases[name] : result.value.data[name]) : null })));
const load = () => {
  if (session.state.status === 'ready' && session.state.context?.capabilities?.dashboard?.index === true) return session.operations?.read(key, 'dashboard', { query: props.query });
  return undefined;
};
watch([() => props.query, () => session.state.status, () => session.operations?.state.revision], load, { immediate: true, deep: true });
onBeforeUnmount(() => session.operations?.cancel(key));
</script>
<template>
  <div v-if="session.state.context?.capabilities?.dashboard?.index === true" class="mb-4">
    <div class="sd-kpi-grid">
      <KpiCard v-for="metric in metrics" :key="metric.name" :label="t(`JRC_SERVICE_DESK.OPS.KPI.${metric.name}`)" :value="metric.value" />
    </div>
    <State v-if="!['ready', 'idle'].includes(result.status)" :status="result.status" compact retry @retry="load" />
    <p v-if="result.status === 'ready'" class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.OPS.kpi_rule') }}
    </p>
    <div v-if="breakdown && result.status === 'ready'" class="grid gap-2 my-4">
      <h3 class="text-sm font-semibold">{{ t('JRC_SERVICE_DESK.OVERVIEW.distribution') }}</h3>
      <p v-if="result.data.by_status.length === 0" class="text-sm">{{ t('JRC_SERVICE_DESK.COMMON.no_records') }}</p>
      <div v-for="row in result.data.by_status" :key="row.id" class="flex gap-3 items-center">
        <Button size="xs" variant="ghost" color="slate" :label="row.name" @click="emit('status-filter', row.id)" />
        <progress class="flex-1" :value="row.count" :max="Math.max(result.data.total, 1)" :aria-label="row.name" />
        <span class="text-sm tabular-nums">{{ row.count }}</span>
      </div>
    </div>
  </div>
</template>
