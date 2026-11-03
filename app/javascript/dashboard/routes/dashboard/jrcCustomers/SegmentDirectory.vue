<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import CustomViewsAPI from 'dashboard/api/customViews';
import SegmentDialog from './components/SegmentDialog.vue';
import { useCustomerMaster } from './useCustomerMaster';
import { T, primaryClass, buttonClass, errorMessage } from './copy';

const { t } = useI18n();
const { accountId, identity, canAdmin, accountScopedRoute } =
  useCustomerMaster();
const native = ref([]);
const rows = ref([]);
const page = ref(1);
const meta = ref({ total: 0, per_page: 25 });
const error = ref('');
const busy = ref(false);
const selection = ref(null);
const creating = ref(false);
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  native.value = [];
  meta.value = { total: 0, per_page: 25 };
  error.value = '';
  busy.value = true;
  try {
    const options = { accountId: accountId.value, signal: controller.signal };
    const [result, personal] = await Promise.all([
      API.taxonomies({ kind: 'segment', page: page.value }, options),
      CustomViewsAPI.getCustomViewsByFilterType('contact', options),
    ]);
    if (token !== generation) return;
    rows.value = result.data.payload;
    meta.value = result.data.meta;
    native.value = personal.data;
  } catch (failure) {
    if (token === generation) error.value = errorMessage(failure);
  } finally {
    if (token === generation) busy.value = false;
  }
};
const saved = () => {
  creating.value = false;
  selection.value = null;
  load();
};
watch(
  identity,
  () => {
    creating.value = false;
    selection.value = null;
    page.value = 1;
    load();
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <main class="h-full overflow-auto bg-n-solid-1 p-5 text-n-slate-12 md:p-8">
    <header class="mb-5 flex flex-wrap items-center justify-between gap-3">
      <div>
        <p class="text-sm text-n-brand">{{ T.customers }}</p>
        <h1 class="mt-2 text-2xl font-bold">{{ T.segments }}</h1>
      </div>
      <button
        v-if="canAdmin"
        type="button"
        :class="primaryClass"
        @click="creating = true"
      >
        {{ t('CRM.CORPORATE_SEGMENTS.NEW') }}
      </button>
    </header>
    <p class="mb-5 text-sm text-n-slate-10">
      {{ t('CRM.CORPORATE_SEGMENTS.HELP') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="mb-4 text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <section
      class="space-y-3 rounded-xl border border-n-teal-6 bg-n-solid-2 p-4"
    >
      <h2 class="font-semibold">{{ T.companySegments }}</h2>
      <article
        v-for="row in rows"
        :key="row.id"
        class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak p-3"
      >
        <div class="min-w-0">
          <strong class="break-words">{{ row.name }}</strong>
          <p class="text-sm text-n-slate-10">
            {{ row.active ? T.active : T.inactive }} ·
            {{
              row.selection_mode === 'dynamic'
                ? t('CRM.CORPORATE_SEGMENTS.DYNAMIC')
                : t('CRM.CORPORATE_SEGMENTS.CLASSIFICATION')
            }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            :class="buttonClass"
            @click="selection = row.id"
          >
            {{ t('CRM.CORPORATE_SEGMENTS.DETAILS') }}
          </button>
          <RouterLink
            v-if="row.active"
            :to="
              accountScopedRoute(
                'jrc_customer_companies',
                {},
                { taxonomy_id: row.id }
              )
            "
            :class="buttonClass"
          >
            {{ t('CRM.CORPORATE_SEGMENTS.OPEN_COMPANIES') }}
          </RouterLink>
        </div>
      </article>
      <p v-if="!busy && !rows.length">{{ T.noResults }}</p>
      <div class="flex gap-3">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page <= 1"
          @click="page -= 1"
        >
          {{ T.previous }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page * meta.per_page >= meta.total"
          @click="page += 1"
        >
          {{ T.next }}
        </button>
      </div>
    </section>
    <section class="mt-5 rounded-xl border border-n-violet-6 bg-n-solid-2 p-4">
      <h2 class="mb-3 font-semibold">{{ T.nativeSegments }}</h2>
      <RouterLink
        v-for="item in native || []"
        :key="item.id"
        :to="
          accountScopedRoute(
            'contacts_dashboard_segments_index',
            { segmentId: item.id },
            { page: 1 }
          )
        "
        class="block border-b border-n-weak py-3 text-n-brand"
      >
        {{ item.name }}
      </RouterLink>
      <p v-if="!native?.length">{{ T.noResults }}</p>
    </section>
    <SegmentDialog
      v-if="creating || selection"
      :key="`${identity}:${selection || 'new'}`"
      :taxonomy-id="selection"
      @close="
        creating = false;
        selection = null;
      "
      @saved="saved"
    />
  </main>
</template>
