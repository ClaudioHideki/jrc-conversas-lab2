<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import CustomerAPI from 'dashboard/api/jrcCustomers';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  modelValue: { type: [Number, String], default: '' },
});
const emit = defineEmits(['update:modelValue']);
const route = useRoute();
const store = useStore();
const { text } = useBackofficePresentation();
const query = ref('');
const rows = ref([]);
const selected = ref(null);
const page = ref(1);
const total = ref(0);
const loading = ref(false);
const error = ref('');
let sequence = 0;
let selectionSequence = 0;
let controller;
let selectionController;
let timer;
const load = async (next = 1) => {
  clearTimeout(timer);
  controller?.abort();
  controller = new AbortController();
  const signal = controller.signal;
  const accountId = route.params.accountId;
  sequence += 1;
  const request = sequence;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await CustomerAPI.companies(
      { q: query.value, page: next, per_page: 20 },
      { accountId, signal }
    );
    if (request !== sequence || signal.aborted) return;
    rows.value = data.payload;
    total.value = data.meta.total;
    page.value = next;
  } catch (failure) {
    if (request === sequence && !signal.aborted) {
      error.value = [401, 403].includes(failure.response?.status)
        ? 'CUSTOMER_FORBIDDEN'
        : 'CUSTOMER_QUERY_ERROR';
      rows.value = [];
      total.value = 0;
      if ([401, 403].includes(failure.response?.status)) {
        selected.value = null;
        emit('update:modelValue', '');
      }
    }
  } finally {
    if (request === sequence) loading.value = false;
  }
};
const search = event => {
  query.value = event.target.value;
  clearTimeout(timer);
  controller?.abort();
  sequence += 1;
  rows.value = [];
  total.value = 0;
  page.value = 1;
  error.value = '';
  loading.value = true;
  timer = setTimeout(() => load(1), 350);
};
const choose = event => {
  selected.value =
    rows.value.find(item => String(item.id) === event.target.value) || null;
  emit('update:modelValue', event.target.value);
};
watch(
  [() => route.params.accountId, () => store.getters.getCurrentUserID],
  (_, previous) => {
    clearTimeout(timer);
    selectionSequence += 1;
    selectionController?.abort();
    selected.value = null;
    rows.value = [];
    query.value = '';
    if (previous?.length) emit('update:modelValue', '');
    load();
  },
  { immediate: true }
);
watch(
  () => props.modelValue,
  async value => {
    selectionSequence += 1;
    selectionController?.abort();
    const request = selectionSequence;
    if (!value) {
      selected.value = null;
      return;
    }
    const existing = rows.value.find(item => String(item.id) === String(value));
    if (existing) {
      selected.value = existing;
      return;
    }
    selectionController = new AbortController();
    const signal = selectionController.signal;
    try {
      const { data } = await CustomerAPI.company(value, {
        accountId: route.params.accountId,
        signal,
      });
      if (request === selectionSequence && !signal.aborted)
        selected.value = data.payload;
    } catch (failure) {
      if (request === selectionSequence && !signal.aborted) {
        selected.value = null;
        error.value = [401, 403].includes(failure.response?.status)
          ? 'CUSTOMER_FORBIDDEN'
          : 'CUSTOMER_QUERY_ERROR';
        emit('update:modelValue', '');
      }
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  sequence += 1;
  selectionSequence += 1;
  clearTimeout(timer);
  controller?.abort();
  selectionController?.abort();
});
</script>

<template>
  <div>
    <span class="mb-1 block text-xs font-semibold">
      {{ text('CUSTOMER_DIRECTORY') }}
    </span>
    <div class="flex items-start gap-2">
      <input
        :value="query"
        type="search"
        maxlength="200"
        class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
        :aria-label="text('CUSTOMER_SEARCH')"
        :placeholder="text('CUSTOMER_SEARCH')"
        @input="search"
        @keydown.enter.prevent="load()"
      />
      <button
        type="button"
        class="mt-1 rounded-lg border border-n-weak p-2"
        :aria-label="text('CUSTOMER_SEARCH')"
        :title="text('SEARCH')"
        :disabled="loading"
        @click="load()"
      >
        <span class="i-lucide-search block size-4" />
      </button>
      <select
        :value="props.modelValue"
        name="company_id"
        :aria-label="text('SELECT_CUSTOMER')"
        class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
        :disabled="loading || !!error"
        @change="choose"
      >
        <option value="">{{ text('ALL_CUSTOMERS') }}</option>
        <option
          v-if="selected && !rows.some(item => item.id === selected.id)"
          :value="selected.id"
        >
          {{ selected.name }}
        </option>
        <option
          v-for="item in rows"
          :key="item.id"
          :value="item.id"
        >
          {{ item.customer_code ? `${item.customer_code} · ` : ''
          }}{{ item.name }}
        </option>
      </select>
    </div>
    <p
      v-if="error"
      role="alert"
      class="text-xs text-amber-700"
    >
      {{ text(error) }}
    </p>
    <p
      v-else-if="!loading && !rows.length"
      role="status"
      class="mt-2 text-xs text-n-slate-11"
    >
      {{ text('CUSTOMER_NO_RESULTS') }}
    </p>
    <div
      v-else-if="total > 20"
      class="flex items-center justify-between gap-2 text-xs text-n-slate-11"
    >
      <button
        type="button"
        :disabled="page <= 1 || loading"
        @click="load(page - 1)"
      >
        {{ text('PREVIOUS') }}
      </button>
      <span>
        {{ page }} {{ text('PAGE_SEPARATOR') }} {{ Math.ceil(total / 20) }}
      </span>
      <button
        type="button"
        :disabled="page * 20 >= total || loading"
        @click="load(page + 1)"
      >
        {{ text('NEXT') }}
      </button>
    </div>
  </div>
</template>
