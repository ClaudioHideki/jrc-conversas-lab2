<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskAutomationInsights';
import MetricCards from './MetricCards.vue';
const props = defineProps({
  context: { type: Object, required: true },
  unitId: { type: String, required: true },
  revision: { type: Number, default: 0 },
});
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.${key}`);
const data = ref(null);
const error = ref(false);
let turn = 0;
let controller;
const items = computed(() => {
  const completed = data.value?.counts?.completed || 0;
  return [
    { label: tr('ola.queues'), value: data.value?.queues_total },
    {
      label: tr('ola.compliance'),
      value: completed
        ? `${Math.round((100 * (data.value.counts.completed_met || 0)) / completed)}%`
        : null,
    },
    {
      label: tr('ola.near_due'),
      value: data.value ? data.value.counts.near_due || 0 : null,
    },
    {
      label: tr('ola.overdue'),
      value: data.value ? data.value.counts.overdue || 0 : null,
    },
  ];
});
async function load() {
  turn += 1;
  const request = turn;
  controller?.abort();
  data.value = null;
  error.value = false;
  if (!props.unitId) return;
  controller = new AbortController();
  try {
    const value = await API.read(
      props.context.account_id,
      props.unitId,
      'ola',
      { days: 30 },
      controller.signal
    );
    if (turn === request) data.value = value;
  } catch {
    if (turn === request) error.value = true;
  }
}
watch([() => props.context, () => props.unitId, () => props.revision], load, {
  immediate: true,
});
onBeforeUnmount(() => {
  turn += 1;
  controller?.abort();
});
</script>

<template>
  <section
    class="min-w-0"
    :aria-label="tr('ola.title')"
  >
    <MetricCards :items="items" />
    <p class="text-xs text-n-slate-11">{{ tr('ola.overview_scope') }}</p>
    <p
      v-if="error"
      role="status"
      class="mt-2 text-xs text-n-amber-11"
    >
      {{ tr('unavailable') }}
    </p>
    <button
      v-if="unitId"
      type="button"
      class="my-2 text-xs text-n-blue-11 underline"
      @click="load"
    >
      {{ tr('refresh') }}
    </button>
  </section>
</template>
