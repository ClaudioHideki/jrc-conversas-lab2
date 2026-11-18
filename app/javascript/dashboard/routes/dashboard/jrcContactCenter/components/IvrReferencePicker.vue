<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  resource: {
    type: String,
    required: true,
    validator: value => ['units', 'queues'].includes(value),
  },
  unitId: { type: [String, Number], default: '' },
  modelValue: { type: [String, Number], default: '' },
  inputId: { type: String, required: true },
  disabled: { type: Boolean, default: false },
  allowClear: { type: Boolean, default: false },
  voiceOnly: { type: Boolean, default: true },
  emptyLabel: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const items = ref([]);
const q = ref('');
const page = ref(1);
const pages = ref(0);
const loading = ref(false);
const failed = ref(false);
const selected = ref(null);
const selectionFailed = ref(false);
let selectedGeneration = 0;
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  items.value = [];
  pages.value = 0;
  try {
    const params = {
      page: page.value,
      per_page: 20,
      q: q.value,
      status: 'active',
    };
    if (props.resource === 'queues') params.unit_id = props.unitId;
    const readers = { units: API.units, queues: API.queues };
    const response = await readers[props.resource](props.accountId, params);
    if (version !== generation) return;
    items.value = response.data.items;
    pages.value = response.data.meta.pages;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const loadSelected = async () => {
  selectedGeneration += 1;
  const version = selectedGeneration;
  selected.value = null;
  selectionFailed.value = false;
  if (!props.modelValue || (props.resource === 'queues' && !props.unitId))
    return;
  try {
    const response = await API.ivrReference(
      props.accountId,
      props.resource,
      props.modelValue
    );
    if (version !== selectedGeneration) return;
    const row = response.data.item;
    if (
      String(row.id) !== String(props.modelValue) ||
      (props.resource === 'queues' &&
        String(row.unit_id) !== String(props.unitId))
    )
      throw new Error('Invalid reference response');
    selected.value = {
      id: row.id,
      name: row.name,
      code: row.code,
      status: row.status,
    };
  } catch {
    if (version === selectedGeneration) selectionFailed.value = true;
  }
};
watch(
  () => [props.modelValue, props.accountId, props.resource, props.unitId],
  loadSelected,
  { immediate: true }
);
const search = () => {
  page.value = 1;
  load();
};
const move = delta => {
  page.value += delta;
  load();
};
watch(
  () => [props.accountId, props.resource, props.unitId],
  () => {
    generation += 1;
    page.value = 1;
    q.value = '';
    if (props.resource === 'queues' && !props.unitId) {
      items.value = [];
      pages.value = 0;
      loading.value = false;
      failed.value = false;
      return;
    }
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  selectedGeneration += 1;
});
</script>

<template>
  <div class="min-w-0 space-y-2">
    <div v-if="!disabled" class="flex min-w-0 flex-wrap gap-2">
      <input
        v-model="q"
        :aria-label="t('JRC_CONTACT_CENTER.LOCAL_IVR.SEARCH_REFERENCE')"
        type="search"
        class="h-9 min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
        :disabled="loading"
        @keydown.enter.prevent="search"
      />
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 text-sm text-n-blue-11"
        :disabled="loading"
        @click="search"
      >
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.SEARCH') }}
      </button>
    </div>
    <select
      :id="inputId"
      :value="String(modelValue || '')"
      :disabled="
        disabled || loading || failed || (resource === 'queues' && !unitId)
      "
      class="h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
      @change="emit('update:modelValue', $event.target.value)"
    >
      <option value="" :disabled="!allowClear">
        {{
          emptyLabel ||
          (allowClear
            ? t('JRC_CONTACT_CENTER.ADMIN.ALL')
            : t('JRC_CONTACT_CENTER.LOCAL_IVR.CHOOSE_REFERENCE'))
        }}
      </option>
      <option
        v-if="
          modelValue &&
          !items.some(row => String(row.id) === String(modelValue))
        "
        :value="String(modelValue)"
        disabled
      >
        {{
          selected
            ? selected.name + ' · ' + selected.code
            : t('JRC_CONTACT_CENTER.LOCAL_IVR.REFERENCE_ID', {
                id: modelValue,
              })
        }}{{
          selected?.status === 'inactive'
            ? ' · ' + t('JRC_CONTACT_CENTER.COMMON.INACTIVE')
            : ''
        }}
      </option>
      <option
        v-for="row in items"
        :key="row.id"
        :value="String(row.id)"
        :disabled="
          voiceOnly && resource === 'queues' && row.service_kind !== 'voice'
        "
      >
        {{ row.name }} · {{ row.code
        }}{{
          voiceOnly && resource === 'queues' && row.service_kind !== 'voice'
            ? ' · ' + t('JRC_CONTACT_CENTER.LOCAL_IVR.NOT_VOICE')
            : ''
        }}
      </option>
    </select>
    <p v-if="loading" role="status" class="text-xs text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p v-if="selectionFailed" role="alert" class="text-xs text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.REFERENCE_UNAVAILABLE') }}
    </p>
    <p v-if="failed" role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <div
      v-if="!disabled"
      class="flex flex-wrap items-center gap-2 text-xs text-n-slate-11"
    >
      <button
        type="button"
        class="rounded-lg border border-n-weak px-2 py-1"
        :disabled="loading || pages < 1 || page <= 1"
        @click="move(-1)"
      >
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.PREVIOUS') }}
      </button>
      <span v-if="pages > 0" data-ivr-reference-page-count>
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.PAGE', { page, pages }) }}
      </span>
      <span
        v-else-if="!loading && !failed && (resource !== 'queues' || unitId)"
        data-ivr-reference-empty
      >
        {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
      </span>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-2 py-1"
        :disabled="loading || page >= pages"
        @click="move(1)"
      >
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.NEXT') }}
      </button>
      <button v-if="failed" type="button" class="text-n-blue-11" @click="load">
        {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
      </button>
    </div>
  </div>
</template>
