<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({ record: { type: Object, required: true } });
const route = useRoute();
const { text } = useBackofficePresentation();
const result = ref(null);
const busy = ref(false);
const error = ref(false);
const identity = computed(
  () => `${route.params.accountId}:${props.record.id}:${props.record.status}`
);
let generation = 0;
watch(identity, () => {
  generation += 1;
  result.value = null;
  busy.value = false;
  error.value = false;
});
onBeforeUnmount(() => {
  generation += 1;
});
const destination = computed(() =>
  result.value?.available
    ? {
        name: 'jrc_relationship_handoffs',
        params: { accountId: route.params.accountId },
        query: {
          assignment_id: result.value.assignment_id,
          source_type: result.value.source_type,
          source_id: result.value.source_id,
          handoff_id: result.value.handoff_id || undefined,
          customer_segment_id: route.query.customer_segment_id,
        },
      }
    : null
);
const load = async () => {
  if (busy.value || props.record.status !== 'completed') return;
  const token = generation;
  const context = identity.value;
  result.value = null;
  busy.value = true;
  error.value = false;
  try {
    const { data } = await backofficeAPI.completionHandoff(
      route.params.accountId,
      props.record.id
    );
    if (generation === token && identity.value === context) result.value = data;
  } catch {
    if (generation === token) error.value = true;
  } finally {
    if (generation === token) busy.value = false;
  }
};
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-xl border border-n-strong bg-n-solid-2 p-4"
  >
    <h3 class="font-semibold text-n-slate-12">
      {{ text('COMPLETION_HANDOFF_TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11">{{ text('COMPLETION_HANDOFF_NOTE') }}</p>
    <button
      v-if="record.status === 'completed'"
      type="button"
      class="rounded-lg border border-teal-400 px-4 py-2 text-sm font-semibold text-n-slate-12 disabled:opacity-50"
      :disabled="busy"
      @click="load"
    >
      {{ text('COMPLETION_HANDOFF_CHECK') }}
    </button>
    <p
      v-if="busy"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ text('COMPLETION_REPORT_LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ text('COMPLETION_HANDOFF_ERROR') }}
    </p>
    <p
      v-if="result && !result.available"
      role="status"
      class="text-sm text-n-amber-11"
    >
      {{ text('COMPLETION_HANDOFF_UNAVAILABLE') }}
    </p>
    <RouterLink
      v-if="destination"
      :to="destination"
      class="inline-block rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white"
    >
      {{
        text(
          result.handoff_id
            ? 'COMPLETION_HANDOFF_OPEN'
            : 'COMPLETION_HANDOFF_PREPARE'
        )
      }}
    </RouterLink>
  </section>
</template>
