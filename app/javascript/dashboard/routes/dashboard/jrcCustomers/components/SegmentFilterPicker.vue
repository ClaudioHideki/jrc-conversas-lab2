<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, inputClass, buttonClass, errorMessage } from '../copy';

const props = defineProps({
  modelValue: { type: [Number, String], default: null },
  moduleKey: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const { accountId, identity } = useCustomerMaster();
const selected = ref(null);
const rows = ref([]);
const query = ref('');
const focused = ref(false);
const page = ref(1);
const meta = ref({ total: 0, per_page: 10 });
const busy = ref(false);
const resolving = ref(false);
const error = ref('');
let generation = 0;
let selectionGeneration = 0;
let controller;
let selectionController;
let timer;
const load = async () => {
  if (!focused.value) return;
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  busy.value = true;
  error.value = '';
  try {
    const result = await API.taxonomies(
      {
        kind: 'segment',
        active: true,
        q: query.value,
        page: page.value,
        per_page: 10,
        ...(props.moduleKey ? { module_key: props.moduleKey } : {}),
      },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (token !== generation) return;
    rows.value = result.data.payload;
    meta.value = result.data.meta;
  } catch (failure) {
    if (token === generation) error.value = errorMessage(failure);
  } finally {
    if (token === generation) busy.value = false;
  }
};
const search = () => {
  focused.value = true;
  if (page.value !== 1) page.value = 1;
  else load();
};
const choose = record => {
  generation += 1;
  selectionGeneration += 1;
  controller?.abort();
  selectionController?.abort();
  clearTimeout(timer);
  focused.value = false;
  rows.value = [];
  query.value = '';
  selected.value = record;
  busy.value = false;
  emit('update:modelValue', record?.id || '');
};
watch(query, () => {
  generation += 1;
  controller?.abort();
  clearTimeout(timer);
  rows.value = [];
  busy.value = focused.value;
  if (focused.value) timer = setTimeout(search, 250);
});
watch(page, load);
watch(
  [identity, () => props.modelValue, () => props.moduleKey],
  async () => {
    generation += 1;
    selectionGeneration += 1;
    const token = selectionGeneration;
    controller?.abort();
    selectionController?.abort();
    selectionController = new AbortController();
    clearTimeout(timer);
    selected.value = null;
    rows.value = [];
    meta.value = { total: 0, per_page: 10 };
    query.value = '';
    focused.value = false;
    busy.value = false;
    error.value = '';
    resolving.value = false;
    if (!props.modelValue) return;
    resolving.value = true;
    try {
      const result = await API.taxonomy(props.modelValue, {
        accountId: accountId.value,
        signal: selectionController.signal,
      });
      if (token !== selectionGeneration) return;
      const record = result.data.payload;
      if (
        props.moduleKey &&
        (!record.active || !record.modules?.includes(props.moduleKey))
      ) {
        error.value = t('CRM.CORPORATE_SEGMENTS.UNAVAILABLE_MODULE_FILTER');
        return;
      }
      selected.value = record;
    } catch (failure) {
      if (token === selectionGeneration) error.value = errorMessage(failure);
    } finally {
      if (token === selectionGeneration) resolving.value = false;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  selectionGeneration += 1;
  clearTimeout(timer);
  controller?.abort();
  selectionController?.abort();
});
</script>

<template>
  <div
    class="min-w-0 space-y-2 rounded-lg border border-n-violet-6 bg-n-solid-1 p-3"
  >
    <div
      v-if="modelValue"
      class="flex flex-wrap items-center justify-between gap-2"
    >
      <span
        v-if="selected"
        class="min-w-0 break-words font-medium"
        >{{ selected.name }}</span
      >
      <span
        v-else-if="resolving"
        role="status"
        >{{ T.loading }}</span
      >
      <button
        type="button"
        :class="buttonClass"
        @click="choose(null)"
      >
        {{ t('CRM.CORPORATE_SEGMENTS.CLEAR_FILTER') }}
      </button>
    </div>
    <input
      v-model.trim="query"
      :class="inputClass"
      :aria-label="t('CRM.CORPORATE_SEGMENTS.SEARCH_FILTER')"
      :placeholder="t('CRM.CORPORATE_SEGMENTS.SEARCH_FILTER')"
      @focus="search"
      @keydown.enter.prevent="search"
    />
    <p
      v-if="error"
      role="alert"
      class="text-xs text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
      class="text-xs"
    >
      {{ T.loading }}
    </p>
    <template v-if="focused">
      <div class="max-h-48 space-y-1 overflow-y-auto">
        <button
          v-for="item in rows"
          :key="item.id"
          type="button"
          class="block w-full rounded-lg border border-n-weak p-2 text-left text-sm"
          @click="choose(item)"
        >
          <strong class="block break-words">{{ item.name }}</strong>
          <span class="text-xs text-n-slate-10">{{
            item.selection_mode === 'dynamic'
              ? t('CRM.CORPORATE_SEGMENTS.DYNAMIC')
              : t('CRM.CORPORATE_SEGMENTS.CLASSIFICATION')
          }}</span>
        </button>
      </div>
      <p
        v-if="!busy && !rows.length"
        class="text-xs text-n-slate-10"
      >
        {{ T.noResults }}
      </p>
      <div class="flex items-center justify-between gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page <= 1"
          @click="page -= 1"
        >
          {{ T.previous }}
        </button>
        <span class="text-xs">{{
          t('CRM.CORPORATE_SEGMENTS.PAGE', {
            page,
            total: Math.max(1, Math.ceil(meta.total / meta.per_page)),
          })
        }}</span>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page * meta.per_page >= meta.total"
          @click="page += 1"
        >
          {{ T.next }}
        </button>
      </div>
    </template>
    <p class="text-xs text-n-slate-10">
      {{ t('CRM.CORPORATE_SEGMENTS.APPLY_FILTER_HELP') }}
    </p>
  </div>
</template>
