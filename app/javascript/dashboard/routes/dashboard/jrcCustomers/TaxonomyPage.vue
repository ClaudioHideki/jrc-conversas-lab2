<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from './useCustomerMaster';
import { T, errorMessage } from './copy';
const route = useRoute();
const store = useStore();
const { accountId, accountScopedRoute } = useCustomerMaster();
const groups = computed(() => route.name === 'jrc_customer_groups');
const metadata = ref({ segments: [], economic_groups: [] });
const error = ref('');
const busy = ref(false);
const segments = useMapGetter('customViews/getContactCustomViews');
const labels = useMapGetter('labels/getLabels');
const values = computed(() =>
  groups.value ? metadata.value.economic_groups : metadata.value.segments
);
const native = computed(() =>
  groups.value ? labels.value || [] : segments.value || []
);
let generation = 0;
watch(
  accountId,
  async () => {
    generation += 1;
    const version = generation;
    metadata.value = { segments: [], economic_groups: [] };
    error.value = '';
    busy.value = true;
    try {
      const [response] = await Promise.all([
        API.metadata(),
        store.dispatch('labels/get'),
        store.dispatch('customViews/get', 'contact'),
      ]);
      if (version === generation) metadata.value = response.data;
    } catch (err) {
      if (version === generation) error.value = errorMessage(err);
    } finally {
      if (version === generation) busy.value = false;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});

const nativeRoute = item =>
  groups.value
    ? accountScopedRoute(
        'contacts_dashboard_labels_index',
        { label: item.title },
        { page: 1 }
      )
    : accountScopedRoute(
        'contacts_dashboard_segments_index',
        { segmentId: item.id },
        { page: 1 }
      );
</script>

<template>
  <main class="h-full w-full overflow-auto bg-n-solid-1 p-6 text-n-slate-12">
    <p class="text-sm text-n-brand">{{ T.customers }}</p>
    <h1 class="my-3 text-2xl font-bold">
      {{ groups ? T.groups : T.segments }}
    </h1>
    <p class="mb-6 text-sm text-n-slate-10">{{ T.taxonomiesHelp }}</p>
    <p
      v-if="error"
      class="text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <div class="grid gap-5 md:grid-cols-2">
      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h2 class="mb-4 font-semibold">
          {{ groups ? T.economicGroups : T.companySegments }}
        </h2>
        <RouterLink
          v-for="value in values"
          :key="value"
          :to="
            accountScopedRoute(
              'jrc_customer_companies',
              {},
              { [groups ? 'economic_group' : 'segment']: value }
            )
          "
          class="block border-b border-n-weak py-3 text-n-brand"
          >{{ value }}</RouterLink
        >
        <p
          v-if="!values.length"
          class="text-n-slate-10"
        >
          {{ T.noResults }}
        </p>
      </section>
      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h2 class="mb-4 font-semibold">
          {{ groups ? T.nativeGroups : T.nativeSegments }}
        </h2>
        <RouterLink
          v-for="item in native"
          :key="item.id"
          :to="nativeRoute(item)"
          class="block border-b border-n-weak py-3 text-n-brand"
          >{{ item.title || item.name }}</RouterLink
        >
        <p
          v-if="!native.length"
          class="text-n-slate-10"
        >
          {{ T.noResults }}
        </p>
      </section>
    </div>
  </main>
</template>
