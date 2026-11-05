<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import DistributionComparison from '../jrcRelationship/DistributionComparison.vue';
import DistributionCapacitySummary from '../jrcRelationship/DistributionCapacitySummary.vue';
import ResponsibilityComparison from '../jrcRelationship/ResponsibilityComparison.vue';
const props = defineProps({ request: { type: Object, required: true } });
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const data = ref(null);
const error = ref(false);
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.request.id,
    props.request.origin,
    store.getters.getCurrentUserID,
    store.getters.getCurrentUser?.accounts,
    store.getters.getCurrentRole,
  ])
);
watch(
  identity,
  async () => {
    generation += 1;
    const token = generation;
    controller?.abort();
    controller = new AbortController();
    data.value = null;
    error.value = false;
    try {
      const response = await API.distributionApprovalOrigin(
        route.params.accountId,
        props.request.origin.review_id,
        { signal: controller.signal }
      );
      if (token === generation) data.value = response.data;
    } catch (failure) {
      if (token === generation && failure.code !== 'ERR_CANCELED')
        error.value = true;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="min-w-0 space-y-3">
    <p
      v-if="error"
      role="alert"
    >
      {{ t('JRC_APPROVALS.loadError') }}
    </p>
    <template v-if="data">
      <p class="whitespace-pre-wrap break-words text-sm">
        {{ data.justification }}
      </p>
      <DistributionComparison :rows="data.distribution" />
      <DistributionCapacitySummary :rows="data.capacity || []" />
      <ResponsibilityComparison :rows="data.responsibilities || []" />
    </template>
  </section>
</template>
