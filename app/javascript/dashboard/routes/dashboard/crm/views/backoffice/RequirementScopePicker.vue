<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { backofficeRequirementsAPI } from 'dashboard/api/crm/backofficeRequirements';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  modelValue: { type: Number, default: null },
  label: { type: String, required: true },
  kind: { type: String, required: true },
  disabled: { type: Boolean, default: false },
  initialLabel: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
const store = useStore();
const { text } = useBackofficePresentation();
const copy = key => text(`REQUIREMENTS.${key}`);
const query = ref('');
const rows = ref([]);
const page = ref(1);
const total = ref(0);
const loading = ref(false);
const error = ref('');
const context = computed(
  () => `${authorityScope(store.getters)}:${props.kind}`
);
let sequence = 0;
let aborter;
const load = async target => {
  sequence += 1;
  const current = sequence;
  const scope = context.value;
  const account = store.getters.getCurrentAccountId;
  aborter?.abort();
  aborter = new AbortController();
  loading.value = true;
  error.value = '';
  rows.value = [];
  total.value = 0;
  try {
    const { data } = await backofficeRequirementsAPI.scopeOptions(
      account,
      { kind: props.kind, q: query.value, page: target },
      { signal: aborter.signal }
    );
    if (current !== sequence || context.value !== scope) return;
    rows.value = data.data;
    total.value = data.meta.total;
    page.value = data.meta.page;
  } catch (failure) {
    if (current !== sequence || context.value !== scope) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? 'DENIED'
      : 'LOAD_ERROR';
  } finally {
    if (current === sequence && context.value === scope) loading.value = false;
  }
};
watch(
  context,
  () => {
    query.value = '';
    load(1);
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  sequence += 1;
  aborter?.abort();
});
</script>

<template>
  <fieldset class="space-y-2 rounded border p-3" :disabled="disabled">
    <legend class="px-1 text-sm">{{ label }}</legend>
    <div class="flex gap-2">
      <input
        v-model="query"
        type="search"
        maxlength="200"
        :aria-label="copy('SEARCH')"
        class="min-w-0 flex-1 rounded border p-2"
        @keydown.enter.prevent="load(1)"
      />
      <button
        type="button"
        :disabled="loading"
        class="rounded border px-3"
        @click="load(1)"
      >
        {{ copy('SEARCH') }}
      </button>
    </div>
    <p v-if="error" role="alert">{{ copy(error) }}</p>
    <select
      :value="modelValue ?? ''"
      class="w-full rounded border p-2"
      :aria-label="label"
      :disabled="disabled || loading || !!error"
      @change="
        emit(
          'update:modelValue',
          $event.target.value === '' ? null : Number($event.target.value)
        )
      "
    >
      <option value="">{{ copy('ALL') }}</option>
      <option
        v-if="modelValue && !rows.some(row => row.id === modelValue)"
        :value="modelValue"
      >
        {{ initialLabel || copy('SCOPE_SELECTED') }}
      </option>
      <option v-for="row in rows" :key="row.id" :value="row.id">
        {{ row.name }}
      </option>
    </select>
    <div class="flex gap-2 text-xs">
      <button
        type="button"
        :disabled="loading || page <= 1"
        @click="load(page - 1)"
      >
        {{ copy('PREVIOUS') }}
      </button>
      <span>{{ page }}</span
      ><button
        type="button"
        :disabled="loading || page * 25 >= total"
        @click="load(page + 1)"
      >
        {{ copy('NEXT') }}
      </button>
    </div>
  </fieldset>
</template>
