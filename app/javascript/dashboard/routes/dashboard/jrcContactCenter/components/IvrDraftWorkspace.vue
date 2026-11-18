<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import API from 'dashboard/api/jrcContactCenter';
import IvrDraftEditor from './IvrDraftEditor.vue';
import IvrReferencePicker from './IvrReferencePicker.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
});
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const text = (key, params = {}) =>
  t(`JRC_CONTACT_CENTER.LOCAL_IVR.${key}`, params);
const items = ref([]);
const meta = ref({ total: 0, page: 1, pages: 0 });
const loading = ref(false);
const navigating = ref(false);
const listBusy = computed(() => loading.value || navigating.value);
const loaded = ref(false);
const failed = ref(false);
const filters = ref({ q: '', status: '', unit_id: '' });
const editing = ref(false);
const selectedId = ref(null);
const editorKey = ref(0);
const signature = query =>
  JSON.stringify(
    ['ivr_q', 'ivr_status', 'ivr_unit', 'ivr_page'].map(key => query[key])
  );
const identity = computed(
  () => String(props.accountId) + ':' + signature(route.query)
);
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  loaded.value = false;
  items.value = [];
  filters.value = {
    q: route.query.ivr_q || '',
    status: route.query.ivr_status || '',
    unit_id: route.query.ivr_unit || '',
  };
  try {
    const response = await API.ivrDrafts(props.accountId, {
      ...filters.value,
      page: route.query.ivr_page || 1,
      per_page: 20,
    });
    if (version !== generation) return;
    items.value = response.data.items;
    meta.value = response.data.meta;
    loaded.value = true;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const navigate = async query => {
  if (listBusy.value) return;
  navigating.value = true;
  try {
    await router.replace({ query });
  } finally {
    navigating.value = false;
  }
};
const apply = () => {
  if (listBusy.value) return;
  const query = {
    ...route.query,
    ivr_q: filters.value.q || undefined,
    ivr_status: filters.value.status || undefined,
    ivr_unit: filters.value.unit_id || undefined,
    ivr_page: undefined,
  };
  if (signature(query) === signature(route.query)) load();
  else navigate(query);
};
const clear = () => {
  filters.value = { q: '', status: '', unit_id: '' };
  apply();
};
const page = value => navigate({ ...route.query, ivr_page: String(value) });
const open = id => {
  selectedId.value = id;
  editorKey.value += 1;
  editing.value = true;
};
watch(identity, load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section class="min-w-0 space-y-4 p-4 sm:p-6" data-ivr-workspace>
    <header
      class="flex min-w-0 flex-wrap items-start justify-between gap-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-4"
    >
      <div class="min-w-0">
        <h1 class="flex items-center gap-2 text-xl font-bold text-n-slate-12">
          <Icon
            icon="i-lucide-network"
            class="size-6 shrink-0 text-n-blue-11"
          />{{ text('TITLE') }}
        </h1>
        <p class="mt-2 text-sm text-n-slate-11">{{ text('DESCRIPTION') }}</p>
      </div>
      <button
        type="button"
        :disabled="listBusy || !loaded"
        class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white disabled:opacity-50"
        data-ivr-new
        @click="open(null)"
      >
        {{ text('NEW') }}
      </button>
    </header>
    <form
      class="grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-2"
      @submit.prevent="apply"
    >
      <div class="min-w-0">
        <label
          for="ivr-search"
          class="mb-1 block w-full text-sm text-n-slate-12"
          >{{ text('NAME') }} </label
        ><input
          id="ivr-search"
          v-model="filters.q"
          type="search"
          :disabled="listBusy"
          maxlength="100"
          class="mt-1 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3"
        />
      </div>
      <div class="min-w-0">
        <label
          for="ivr-status"
          class="mb-1 block w-full text-sm text-n-slate-12"
          >{{ t('JRC_CONTACT_CENTER.ADMIN.STATUS') }} </label
        ><select
          id="ivr-status"
          v-model="filters.status"
          :disabled="listBusy"
          class="mt-1 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2"
        >
          <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.ALL') }}</option>
          <option
            v-for="status in ['draft', 'archived']"
            :key="status"
            :value="status"
          >
            {{ text(`STATES.${status}`) }}
          </option>
        </select>
      </div>
      <div class="min-w-0">
        <label
          for="ivr-filter-unit"
          class="mb-1 block text-sm text-n-slate-12"
          >{{ t('JRC_CONTACT_CENTER.ADMIN.UNIT') }}</label
        >
        <IvrReferencePicker
          v-model="filters.unit_id"
          :account-id="accountId"
          resource="units"
          input-id="ivr-filter-unit"
          :disabled="listBusy"
          allow-clear
        />
      </div>
      <div class="flex flex-wrap items-end gap-2">
        <button
          type="submit"
          :disabled="listBusy"
          class="rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
        >
          {{ t('JRC_CONTACT_CENTER.ADMIN.FILTER') }}
        </button>
        <button
          type="button"
          :disabled="listBusy"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
          @click="clear"
        >
          {{ t('JRC_CONTACT_CENTER.ADMIN.CLEAR') }}
        </button>
        <button
          type="button"
          :disabled="listBusy"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
          @click="load"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </div>
    </form>
    <p v-if="listBusy" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p
      v-if="failed"
      role="alert"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <template v-if="loaded">
      <p v-if="!items.length" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
      </p>
      <div class="grid min-w-0 gap-3 lg:grid-cols-2" data-ivr-list>
        <article
          v-for="row in items"
          :key="row.id"
          class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
          :data-ivr-draft="row.id"
        >
          <h2 class="break-words font-semibold text-n-slate-12">
            {{ row.name }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ text(`STATES.${row.status}`) }} ·
            {{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION') }}
            {{ row.revision }} · {{ t('JRC_CONTACT_CENTER.ADMIN.UNIT') }} #{{
              row.unit_id
            }}
          </p>
          <p class="text-xs text-n-amber-11">{{ text('LOCAL_ONLY') }}</p>
          <button
            type="button"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
            @click="open(row.id)"
          >
            {{ text('OPEN') }}
          </button>
        </article>
      </div>
      <nav
        :aria-label="text('TITLE')"
        class="flex flex-wrap items-center gap-2 text-sm text-n-slate-12"
        data-ivr-pagination
      >
        <span
          >{{ t('JRC_CONTACT_CENTER.ADMIN.TOTAL') }} {{ meta.total }} ·
          {{ text('PAGE', { page: meta.page, pages: meta.pages }) }}</span
        >
        <button
          type="button"
          :disabled="listBusy || meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="page(meta.page - 1)"
        >
          {{ text('PREVIOUS') }}
        </button>
        <button
          type="button"
          :disabled="listBusy || meta.page >= meta.pages"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="page(meta.page + 1)"
        >
          {{ text('NEXT') }}
        </button>
      </nav>
    </template>
    <IvrDraftEditor
      v-if="editing"
      :key="editorKey"
      :account-id="accountId"
      :draft-id="selectedId"
      @close="editing = false"
      @saved="load"
    />
  </section>
</template>
