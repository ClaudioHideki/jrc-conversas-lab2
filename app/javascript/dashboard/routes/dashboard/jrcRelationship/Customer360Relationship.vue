<script setup>
import { ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import API from 'dashboard/api/jrcRelationship';
import CustomerPanel from './CustomerPanel.vue';
import { message } from './definitions';
const props = defineProps({
  assignmentId: { type: [String, Number], required: true },
});
const route = useRoute();
const store = useStore();
const metadata = ref(null);
const error = ref('');
watch(
  [() => route.params.accountId, () => store.getters.getCurrentUserID],
  async (_, __, cleanup) => {
    const controller = new AbortController();
    cleanup(() => controller.abort());
    metadata.value = null;
    error.value = '';
    try {
      const { data } = await API.metadata(route.params.accountId, {
        signal: controller.signal,
      });
      if (!controller.signal.aborted) metadata.value = data;
    } catch (err) {
      if (!controller.signal.aborted) error.value = message(err);
    }
  },
  { immediate: true }
);
</script>

<template>
  <p
    v-if="error"
    role="alert"
    class="text-n-ruby-11"
  >
    {{ error }}
  </p>
  <CustomerPanel
    v-if="metadata"
    :assignment-id="props.assignmentId"
    :metadata="metadata"
  />
</template>
