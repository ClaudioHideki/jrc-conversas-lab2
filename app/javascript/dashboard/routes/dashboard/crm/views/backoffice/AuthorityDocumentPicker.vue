<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import api from 'dashboard/api/crm/backofficeAuthorities';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  requestId: { type: [String, Number], required: true },
  selected: { type: Array, default: () => [] },
});
const emit = defineEmits(['choose', 'denied']);
const { text } = useBackofficePresentation();
const result = ref(null);
const key = ref('');
const page = ref(1);
const loading = ref(false);
const error = ref('');
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([props.accountId, props.requestId])
);
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  error.value = '';
  loading.value = true;
  try {
    const { data } = await api.documents(
      props.accountId,
      props.requestId,
      { document_key: key.value || undefined, page: page.value },
      { signal: controller.signal }
    );
    if (token !== generation) return;
    result.value = data;
    key.value = data.selected_key || '';
  } catch (failure) {
    if (token !== generation) return;
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
    error.value = text('CONTRACT_AUTHORITY.DOCUMENT_ERROR');
  } finally {
    if (token === generation) loading.value = false;
  }
};
const ready = row =>
  row.current &&
  row.status === 'approved' &&
  row.safety?.state === 'clean' &&
  row.analysis;
const choose = row => {
  if (
    !ready(row) ||
    props.selected.includes(row.id) ||
    props.selected.length >= 10
  )
    return;
  emit('choose', { id: row.id, filename: row.filename });
};
const change = value => {
  page.value = value;
  load();
};
watch(
  identity,
  () => {
    key.value = '';
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
    class="space-y-3 rounded-xl border border-n-blue-6 bg-n-blue-3 p-3"
    :aria-busy="loading"
  >
    <h4 class="text-sm font-semibold text-n-blue-12">
      {{ text('CONTRACT_AUTHORITY.DOCUMENTS') }}
    </h4>
    <p class="text-xs text-n-slate-11">
      {{ text('CONTRACT_AUTHORITY.DOCUMENT_HELP') }}
    </p>
    <p v-if="loading" role="status" class="text-sm">
      {{ text('CONTRACT_AUTHORITY.LOADING') }}
    </p>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <label v-if="result?.requirements?.length" class="block text-sm">
      {{ text('CONTRACT_AUTHORITY.DOCUMENT_TYPE') }}
      <select
        v-model="key"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12"
        :disabled="loading"
        @change="change(1)"
      >
        <option
          v-for="requirement in result.requirements"
          :key="requirement.key"
          :value="requirement.key"
        >
          {{ requirement.label || requirement.key }}
        </option>
      </select>
    </label>
    <p v-if="result && !result.data.length" class="text-sm text-n-slate-11">
      {{ text('CONTRACT_AUTHORITY.DOCUMENT_EMPTY') }}
    </p>
    <div
      v-for="row in result?.data || []"
      :key="row.id"
      class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm"
    >
      <span>{{
        `${row.filename} · ${text('CONTRACT_VERSIONS.VERSION')} ${row.version}`
      }}</span>
      <button
        type="button"
        class="rounded-lg bg-n-blue-9 px-3 py-2 text-white disabled:opacity-50"
        :disabled="
          loading ||
          !ready(row) ||
          selected.includes(row.id) ||
          selected.length >= 10
        "
        @click="choose(row)"
      >
        {{
          text(
            selected.includes(row.id)
              ? 'CONTRACT_SIGNERS.SELECTED'
              : 'CONTRACT_SIGNERS.CHOOSE'
          )
        }}
      </button>
    </div>
    <div v-if="result" class="flex gap-2">
      <button
        type="button"
        :disabled="loading || result.meta.page <= 1"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-12 disabled:opacity-50"
        @click="change(page - 1)"
      >
        {{ text('PREVIOUS') }}
      </button>
      <button
        type="button"
        :disabled="loading || result.meta.page >= result.meta.pages"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-12 disabled:opacity-50"
        @click="change(page + 1)"
      >
        {{ text('NEXT') }}
      </button>
    </div>
    <button
      v-if="error"
      type="button"
      class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-12"
      @click="load"
    >
      {{ text('REFRESH') }}
    </button>
  </section>
</template>
