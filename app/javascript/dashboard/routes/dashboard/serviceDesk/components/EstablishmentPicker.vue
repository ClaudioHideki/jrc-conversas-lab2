<script setup>
/* global axios */
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { request as portalRequest } from '../../../../../portal/requester/client';

const props = defineProps({
  modelValue: { type: [String, Number], default: null },
  accountId: { type: String, default: '' },
  unitId: { type: [String, Number], default: '' },
  serviceId: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const query = ref('');
const rows = ref([]);
const enabled = ref(false);
const busy = ref(false);
const error = ref(false);
const selected = computed(() =>
  rows.value.find(row => row.id === String(props.modelValue))
);
let generation = 0;
async function load() {
  generation += 1;
  const current = generation;
  if (!props.unitId && !props.serviceId) return;
  busy.value = true;
  error.value = false;
  try {
    const result = props.serviceId
      ? await portalRequest(
          `/portal/api/catalogo/${props.serviceId}/lojas?q=${encodeURIComponent(query.value)}`
        )
      : (
          await axios.get(
            `/api/v1/accounts/${props.accountId}/jrc_service_desk/establishments`,
            { params: { unit_id: props.unitId, q: query.value } }
          )
        ).data;
    if (current !== generation) return;
    const retained = selected.value;
    rows.value = result.establishments;
    if (retained && !rows.value.some(row => row.id === retained.id))
      rows.value.unshift(retained);
    enabled.value = props.serviceId ? true : result.enabled;
  } catch {
    if (current !== generation) return;
    rows.value = [];
    emit('update:modelValue', null);
    error.value = true;
  } finally {
    if (current === generation) busy.value = false;
  }
}
watch(
  () => [props.accountId, props.unitId, props.serviceId],
  () => {
    generation += 1;
    rows.value = [];
    busy.value = false;
    error.value = false;
    enabled.value = false;
    query.value = '';
    emit('update:modelValue', null);
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <fieldset
    v-if="enabled || serviceId || error"
    class="space-y-3 rounded-xl border border-n-weak p-4"
    :disabled="disabled"
  >
    <legend class="px-1 text-sm font-semibold">{{ t('PORTAL.STORE') }}</legend>
    <div class="flex flex-wrap gap-2">
      <input
        v-model="query"
        class="min-w-0 flex-1 rounded border border-n-weak bg-n-background p-2"
        :aria-label="t('PORTAL.STORE_SEARCH')"
        :placeholder="t('PORTAL.STORE_SEARCH')"
        @keydown.enter.prevent="load"
      />
      <button
        type="button"
        class="rounded border border-n-weak px-3 py-2"
        :disabled="busy || disabled"
        @click="load"
      >
        {{ t('PORTAL.SEARCH') }}
      </button>
    </div>
    <label class="block text-sm">
      {{ t('PORTAL.STORE') }}
      <select
        class="mt-1 w-full rounded border border-n-weak bg-n-background p-2"
        :value="modelValue || ''"
        :required="!!serviceId"
        :disabled="busy || disabled"
        @change="emit('update:modelValue', $event.target.value || null)"
      >
        <option value="">{{ t('PORTAL.SELECT') }}</option>
        <option v-for="row in rows" :key="row.id" :value="row.id">
          {{ row.store_code }} — {{ row.name }} — {{ row.cnpj }}
        </option>
      </select>
    </label>
    <p v-if="busy" role="status" class="text-sm">
      {{ t('PORTAL.LOADING_STORES') }}
    </p>
    <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ t('PORTAL.ERROR') }}
    </p>
    <p v-else-if="!rows.length" class="text-sm text-n-slate-11">
      {{ t('PORTAL.NO_STORES') }}
    </p>
    <dl v-if="selected" class="grid gap-2 text-sm sm:grid-cols-2">
      <div>
        <dt>{{ t('PORTAL.ORGANIZATION') }}</dt>
        <dd>{{ selected.legal_name }}</dd>
      </div>
      <div>
        <dt>{{ t('PORTAL.CLUSTER') }}</dt>
        <dd>{{ selected.cluster }}</dd>
      </div>
    </dl>
  </fieldset>
</template>
