<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import CustomerAPI from 'dashboard/api/jrcCustomers';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  modelValue: { type: [Number, String], default: '' },
});
const emit = defineEmits(['update:modelValue']);
const route = useRoute();
const { text } = useBackofficePresentation();
const query = ref('');
const rows = ref([]);
const selected = ref(null);
const page = ref(1);
const total = ref(0);
const loading = ref(false);
const error = ref(false);
let sequence = 0;
const load = async (next = 1) => {
  sequence += 1;
  const request = sequence;
  loading.value = true;
  error.value = false;
  try {
    const { data } = await CustomerAPI.companies({
      q: query.value,
      page: next,
      per_page: 20,
    });
    if (request !== sequence) return;
    rows.value = data.payload;
    total.value = data.meta.total;
    page.value = next;
  } catch {
    if (request === sequence) {
      error.value = true;
      rows.value = [];
    }
  } finally {
    if (request === sequence) loading.value = false;
  }
};
const choose = event => {
  selected.value =
    rows.value.find(item => String(item.id) === event.target.value) || null;
  emit('update:modelValue', event.target.value);
};
watch(
  () => route.params.accountId,
  () => {
    selected.value = null;
    rows.value = [];
    query.value = '';
    load();
  },
  { immediate: true }
);
let selectionSequence = 0;
watch(
  () => props.modelValue,
  async value => {
    selectionSequence += 1;
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
    try {
      const { data } = await CustomerAPI.company(value);
      if (request === selectionSequence) selected.value = data.payload;
    } catch {
      if (request === selectionSequence) error.value = true;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  sequence += 1;
  selectionSequence += 1;
});
</script>

<template>
  <div>
    <span class="mb-1 block text-xs font-semibold">
      {{ text('CUSTOMER_DIRECTORY') }}
    </span>
    <div class="flex items-start gap-2">
      <input
        v-model="query"
        type="search"
        maxlength="200"
        class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
        :aria-label="text('CUSTOMER_SEARCH')"
        :placeholder="text('CUSTOMER_SEARCH')"
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
        :disabled="loading || error"
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
      {{ text('CUSTOMER_ACCESS_ERROR') }}
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
