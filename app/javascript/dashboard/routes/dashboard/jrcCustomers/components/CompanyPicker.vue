<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, inputClass, buttonClass, errorMessage } from '../copy';
const props = defineProps({
  disabled: { type: Boolean, default: false },
  modelValue: { type: [Number, String], default: null },
  excludeId: { type: [Number, String], default: null },
});
const emit = defineEmits(['update:modelValue', 'selected']);
const store = useStore();
const { accountId, canAccess } = useCustomerMaster();
const query = ref('');
const selected = ref(null);
const results = ref([]);
const error = ref('');
const busy = ref(false);
const page = ref(1);
const total = ref(0);
let timer;
let generation = 0;
let selectedGeneration = 0;
const load = async () => {
  if (props.disabled || !canAccess.value) return;
  generation += 1;
  const version = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.companies({
      q: query.value,
      per_page: 15,
      page: page.value,
    });
    if (version === generation) {
      results.value = data.payload.filter(
        row => String(row.id) !== String(props.excludeId)
      );
      total.value = data.meta.total;
    }
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const search = () => {
  if (page.value !== 1) page.value = 1;
  else load();
};
watch(page, load);
const choose = company => {
  if (props.disabled || !canAccess.value) return;
  selected.value = company;
  generation += 1;
  busy.value = false;
  total.value = 0;
  results.value = [];
  query.value = '';
  emit('update:modelValue', company?.id || null);
  emit('selected', company);
};
watch(query, () => {
  clearTimeout(timer);
  generation += 1;
  results.value = [];
  total.value = 0;
  busy.value = false;
  if (query.value.trim().length >= 2) timer = setTimeout(search, 300);
  else results.value = [];
});
watch(
  [
    accountId,
    canAccess,
    () => store.getters.getCurrentUser?.id,
    () => props.modelValue,
  ],
  async () => {
    selectedGeneration += 1;
    const version = selectedGeneration;
    selected.value = null;
    results.value = [];
    total.value = 0;
    error.value = '';
    query.value = '';
    clearTimeout(timer);
    generation += 1;
    if (!props.modelValue || !canAccess.value) return;
    try {
      const { data } = await API.company(props.modelValue);
      if (version === selectedGeneration) selected.value = data.payload;
    } catch (err) {
      if (version === selectedGeneration) error.value = errorMessage(err);
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  clearTimeout(timer);
  generation += 1;
  selectedGeneration += 1;
});
</script>

<template>
  <div
    v-if="canAccess"
    class="min-w-0"
  >
    <div
      v-if="selected"
      class="mb-2 flex items-center justify-between gap-2 rounded-lg bg-n-alpha-2 p-2 text-sm"
    >
      <span class="truncate">{{ selected.name }} #{{ selected.id }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled"
        @click="choose(null)"
      >
        {{ T.clear }}
      </button>
    </div>
    <div class="flex items-end gap-2">
      <input
        v-model="query"
        :disabled="disabled"
        :aria-label="T.searchPicker"
        :placeholder="T.searchPicker"
        :class="inputClass"
        @keydown.enter.prevent="search"
      />
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || disabled"
        @click="search"
      >
        {{ T.search }}
      </button>
    </div>
    <p
      v-if="busy"
      class="mt-1 text-xs text-n-slate-10"
      role="status"
    >
      {{ T.loading }}
    </p>
    <p
      v-if="error"
      class="mt-1 text-xs text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <div
      v-if="results.length"
      class="mt-2 max-h-48 overflow-auto rounded-lg border border-n-weak"
    >
      <button
        v-for="company in results"
        :key="company.id"
        type="button"
        class="block w-full border-b border-n-weak p-2 text-left text-sm hover:bg-n-alpha-2"
        :disabled="disabled"
        @click="choose(company)"
      >
        {{ company.name }}
        <span class="text-n-slate-10"
          >#{{ company.id }} {{ company.tax_id }}</span
        >
      </button>
    </div>
    <div
      v-if="total > 15"
      class="mt-2 flex items-center justify-between gap-2 text-xs"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || disabled || page <= 1"
        @click="page--"
      >
        {{ T.previous }}
      </button>
      <span>{{ page }} / {{ Math.ceil(total / 15) }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || disabled || page * 15 >= total"
        @click="page++"
      >
        {{ T.next }}
      </button>
    </div>
  </div>
</template>
