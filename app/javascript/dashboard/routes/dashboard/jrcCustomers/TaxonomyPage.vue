<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from './useCustomerMaster';
import { T, errorMessage, inputClass, primaryClass, buttonClass } from './copy';

const route = useRoute();
const store = useStore();
const { accountId, accountScopedRoute } = useCustomerMaster();
const groups = computed(() => route.name === 'jrc_customer_groups');
const metadata = ref({
  segments: [],
  economic_groups: [],
  can_administer: false,
});
const taxonomyRecords = ref([]);
const newSegmentName = ref('');
const error = ref('');
const busy = ref(false);
const saving = ref(false);
const segments = useMapGetter('customViews/getContactCustomViews');
const labels = useMapGetter('labels/getLabels');
const values = computed(() =>
  groups.value
    ? metadata.value.economic_groups || []
    : metadata.value.segments || []
);
const native = computed(() =>
  groups.value ? labels.value || [] : segments.value || []
);
let generation = 0;

const load = async () => {
  generation += 1;
  const version = generation;
  metadata.value = { segments: [], economic_groups: [], can_administer: false };
  taxonomyRecords.value = [];
  error.value = '';
  busy.value = true;
  try {
    const requests = [
      API.metadata(),
      store.dispatch('labels/get'),
      store.dispatch('customViews/get', 'contact'),
    ];
    if (!groups.value) requests.push(API.taxonomies({ kind: 'segment' }));
    const responses = await Promise.all(requests);
    if (version === generation) {
      metadata.value = responses[0].data;
      taxonomyRecords.value = responses[3]?.data?.payload || [];
    }
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};

watch([accountId, groups], load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
});

const addSegment = async () => {
  const name = newSegmentName.value.trim();
  if (!name) return;
  saving.value = true;
  error.value = '';
  try {
    await API.saveTaxonomy({
      kind: 'segment',
      name,
      active: true,
      position: taxonomyRecords.value.length,
    });
    newSegmentName.value = '';
    await load();
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    saving.value = false;
  }
};

const toggleTaxonomy = async item => {
  saving.value = true;
  error.value = '';
  try {
    await API.saveTaxonomy({ active: !item.active }, item.id);
    await load();
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    saving.value = false;
  }
};

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
    <p class="mb-6 text-sm text-n-slate-10">
      {{ groups ? T.taxonomiesHelp : T.taxonomyAdminHelp }}
    </p>
    <p
      v-if="error"
      class="mb-4 text-n-ruby-11"
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

    <form
      v-if="!groups && metadata.can_administer"
      class="mb-5 flex max-w-2xl flex-wrap items-end gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      @submit.prevent="addSegment"
    >
      <label class="min-w-72 flex-1 text-sm">
        {{ T.segmentName }}
        <input
          v-model.trim="newSegmentName"
          :class="inputClass"
          maxlength="120"
        />
      </label>
      <button
        type="submit"
        :class="primaryClass"
        :disabled="saving || !newSegmentName.trim()"
      >
        {{ T.addSegment }}
      </button>
    </form>

    <div class="grid gap-5 md:grid-cols-2">
      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <h2 class="mb-4 font-semibold">
          {{ groups ? T.economicGroups : T.companySegments }}
        </h2>
        <div
          v-if="!groups && taxonomyRecords.length"
          class="mb-5 space-y-2"
        >
          <div
            v-for="item in taxonomyRecords"
            :key="item.id"
            class="flex items-center justify-between gap-3 rounded-lg border border-n-weak p-3"
          >
            <span :class="item.active ? '' : 'line-through text-n-slate-9'">{{
              item.name
            }}</span>
            <button
              v-if="metadata.can_administer"
              type="button"
              :class="buttonClass"
              :disabled="saving"
              @click="toggleTaxonomy(item)"
            >
              {{ item.active ? T.active : T.inactive }}
            </button>
          </div>
        </div>
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
        >
          {{ value }}
        </RouterLink>
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
        >
          {{ item.title || item.name }}
        </RouterLink>
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
