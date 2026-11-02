<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { backofficeContractVersionsAPI as api } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  requestId: { type: [Number, String], required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['choose', 'denied']);
const { text } = useBackofficePresentation();
const query = ref('');
const search = ref('');
const page = ref(1);
const result = ref(null);
const loading = ref(false);
const error = ref('');
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  error.value = '';
  loading.value = true;
  try {
    const { data } = await api.templates(
      props.accountId,
      props.requestId,
      { q: search.value, page: page.value },
      { signal: controller.signal }
    );
    if (token === generation) result.value = data;
  } catch (failure) {
    if (token !== generation) return;
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
    else error.value = text('CONTRACT_VERSIONS.TEMPLATES_ERROR');
  } finally {
    if (token === generation) loading.value = false;
  }
};
const applySearch = () => {
  if (props.disabled || loading.value) return;
  search.value = query.value.trim();
  page.value = 1;
  load();
};
const changePage = value => {
  page.value = value;
  load();
};
watch(
  () => [props.accountId, props.requestId],
  () => {
    query.value = '';
    search.value = '';
    page.value = 1;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  result.value = null;
});
</script>

<template>
  <section
    class="space-y-3 rounded-xl border border-n-violet-6 bg-n-violet-3 p-3"
    :aria-label="text('CONTRACT_VERSIONS.SELECT_TEMPLATE')"
    :aria-busy="loading"
  >
    <p class="text-xs text-n-slate-11">
      {{ text('CONTRACT_VERSIONS.TEMPLATES_HELP') }}
    </p>
    <div class="flex gap-2">
      <input
        v-model="query"
        maxlength="120"
        :disabled="disabled || loading"
        :aria-label="text('CONTRACT_VERSIONS.TEMPLATE_SEARCH')"
        :placeholder="text('CONTRACT_VERSIONS.TEMPLATE_SEARCH')"
        class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm text-n-slate-12"
        @keydown.enter.prevent="applySearch"
      />
      <button
        type="button"
        :disabled="disabled || loading"
        class="rounded-lg border border-n-violet-6 bg-n-solid-2 px-3 py-2 text-sm disabled:opacity-50"
        @click="applySearch"
      >
        {{ text('CONTRACT_SIGNERS.SEARCH_ACTION') }}
      </button>
    </div>
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ text('CONTRACT_VERSIONS.LOADING') }}
    </p>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-12">{{ error }}</p>
    <p v-if="result && !result.data.length" class="text-sm text-n-slate-11">
      {{ text('CONTRACT_VERSIONS.TEMPLATES_EMPTY') }}
    </p>
    <ul v-if="result" class="max-h-64 space-y-2 overflow-y-auto">
      <li
        v-for="item in result.data"
        :key="item.id"
        class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm"
      >
        <div class="min-w-0">
          <b class="block break-words">{{ item.name }}</b>
          <span class="text-xs text-n-slate-11">{{ item.category }}</span>
        </div>
        <button
          type="button"
          :disabled="disabled || loading"
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-xs text-n-blue-12 disabled:opacity-50"
          @click="emit('choose', item)"
        >
          {{ text('CONTRACT_SIGNERS.CHOOSE') }}
        </button>
      </li>
    </ul>
    <nav
      v-if="result && result.meta.pages > 1"
      class="flex items-center justify-end gap-3"
      :aria-label="text('CONTRACT_VERSIONS.SELECT_TEMPLATE')"
    >
      <button
        type="button"
        :disabled="disabled || loading || result.meta.page <= 1"
        class="rounded-lg border border-n-weak px-3 py-1 text-sm disabled:opacity-50"
        @click="changePage(result.meta.page - 1)"
      >
        {{ text('CONTRACT_VERSIONS.PREVIOUS') }}
      </button>
      <span class="text-xs">{{
        [
          result.meta.page,
          text('CONTRACT_VERSIONS.OF'),
          result.meta.pages,
        ].join(' ')
      }}</span>
      <button
        type="button"
        :disabled="disabled || loading || result.meta.page >= result.meta.pages"
        class="rounded-lg border border-n-weak px-3 py-1 text-sm disabled:opacity-50"
        @click="changePage(result.meta.page + 1)"
      >
        {{ text('CONTRACT_VERSIONS.NEXT') }}
      </button>
    </nav>
    <button
      v-if="error"
      type="button"
      :disabled="disabled || loading"
      class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
      @click="load"
    >
      {{ text('REFRESH') }}
    </button>
  </section>
</template>
