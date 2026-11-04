<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({ record: { type: Object, required: true } });
const route = useRoute();
const { text } = useBackofficePresentation();
const busy = ref(false);
const error = ref('');
const identity = computed(
  () => `${route.params.accountId}:${props.record.id}:${props.record.status}`
);
let generation = 0;
watch(identity, () => {
  generation += 1;
  busy.value = false;
  error.value = '';
});
onBeforeUnmount(() => {
  generation += 1;
});
const download = async () => {
  if (busy.value || props.record.status !== 'completed') return;
  const token = generation;
  const context = identity.value;
  const accountId = route.params.accountId;
  const requestId = props.record.id;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await backofficeAPI.completionReport(accountId, requestId);
    if (
      token !== generation ||
      context !== identity.value ||
      props.record.status !== 'completed'
    )
      return;
    const url = URL.createObjectURL(data);
    try {
      const link = document.createElement('a');
      link.href = url;
      link.download = `backoffice-${requestId}-completion.csv`;
      link.click();
    } finally {
      URL.revokeObjectURL(url);
    }
  } catch {
    if (token === generation) error.value = text('COMPLETION_REPORT_ERROR');
  } finally {
    if (token === generation) busy.value = false;
  }
};
</script>

<template>
  <div
    v-if="record.status === 'completed'"
    class="min-w-0 space-y-2"
  >
    <button
      type="button"
      class="rounded-lg border border-emerald-300 bg-n-solid-2 px-4 py-2 text-sm font-semibold text-n-slate-12 disabled:opacity-50"
      :disabled="busy"
      @click="download"
    >
      {{ text(busy ? 'COMPLETION_REPORT_LOADING' : 'COMPLETION_REPORT') }}
    </button>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
  </div>
</template>
