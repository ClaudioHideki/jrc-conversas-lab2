<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import api from 'dashboard/api/crm/backofficeAuthorities';
import AuthorityCaseView from '../crm/views/backoffice/AuthorityCaseView.vue';
import { useBackofficePresentation } from '../crm/views/backoffice/useBackofficePresentation';

const props = defineProps({ request: { type: Object, required: true } });
const { text } = useBackofficePresentation();
const route = useRoute();
const store = useStore();
const data = ref(null);
const error = ref('');
const loading = ref(false);
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.request.id,
    props.request.resource_id,
    props.request.origin,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser,
  ])
);
const deny = () => {
  generation += 1;
  controller?.abort();
  data.value = null;
  error.value = text('CONTRACT_AUTHORITY.DENIED');
  loading.value = false;
};
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  data.value = null;
  error.value = '';
  loading.value = true;
  try {
    const response = await api.show(
      route.params.accountId,
      props.request.origin.backoffice_request_id,
      props.request.resource_id,
      { signal: controller.signal }
    );
    if (token === generation) data.value = response.data;
  } catch (failure) {
    if (token === generation)
      error.value = text(
        [401, 403, 404].includes(failure.response?.status)
          ? 'CONTRACT_AUTHORITY.DENIED'
          : 'CONTRACT_AUTHORITY.ERROR'
      );
  } finally {
    if (token === generation) loading.value = false;
  }
};
watch(identity, load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  data.value = null;
});
</script>

<template>
  <section
    class="space-y-3"
    :aria-busy="loading"
  >
    <p
      v-if="loading"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ text('CONTRACT_AUTHORITY.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <button
      type="button"
      :disabled="loading"
      class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12 disabled:opacity-50"
      @click="load"
    >
      {{ text('REFRESH') }}
    </button>
    <AuthorityCaseView
      v-if="data"
      :account-id="route.params.accountId"
      :request-id="request.origin.backoffice_request_id"
      :data="data"
      @denied="deny"
    />
  </section>
</template>
