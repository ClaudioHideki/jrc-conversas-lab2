<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskStructure';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { structurePage } from '../helpers/structure';
const props = defineProps({ context: { type: Object, required: true }, resource: { type: String, required: true }, disabled: Boolean });
const value = defineModel({ type: String, default: '' });
const { t } = useI18n();
const rows = ref([]), query = ref(''), page = ref(1), total = ref(0), status = ref('idle');
let generation = 0; let controller;
const options = computed(() => rows.value.map(row => ({ value: row.id, label: `${row.name || row.id} (#${row.id})` })));
const load = async () => {
  const epoch = ++generation; controller?.abort(); controller = new AbortController();
  rows.value = []; status.value = 'loading';
  try {
    const response = await API.list(props.context.account_id, props.resource, page.value, query.value, controller.signal);
    if (epoch !== generation) return;
    const result = structurePage(response, props.context, props.resource, page.value);
    rows.value = result.items; total.value = result.meta.total; status.value = rows.value.length ? 'ready' : 'empty';
  } catch { if (epoch === generation) { rows.value = []; total.value = 0; status.value = 'error'; } }
};
const search = () => { page.value = 1; value.value = ''; load(); };
const turn = delta => { page.value += delta; value.value = ''; load(); };
watch([() => props.context, () => props.resource], () => { page.value = 1; value.value = ''; load(); }, { immediate: true });
onBeforeUnmount(() => { generation += 1; controller?.abort(); });
</script>
<template>
  <fieldset class="border border-n-weak rounded-lg p-3 space-y-2" :disabled="disabled">
    <legend>{{ t(`JRC_SERVICE_DESK.STRUCTURE.resources.${resource}`) }}</legend>
    <div class="flex gap-2"><Input v-model="query" :disabled="disabled" :placeholder="t('JRC_SERVICE_DESK.STRUCTURE.search')" /><Button type="button" size="sm" :disabled="disabled" :label="t('JRC_SERVICE_DESK.STRUCTURE.search')" @click="search" /></div>
    <Select v-model="value" :disabled="disabled || status !== 'ready'" :options="options" :placeholder="t('JRC_SERVICE_DESK.STRUCTURE.choose')" />
    <p v-if="status !== 'ready'" role="status">{{ t(`JRC_SERVICE_DESK.STRUCTURE.states.${status}`) }}</p>
    <div class="flex gap-2"><Button type="button" size="sm" :disabled="disabled || page <= 1" :label="t('JRC_SERVICE_DESK.STRUCTURE.previous')" @click="turn(-1)" /><Button type="button" size="sm" :disabled="disabled || page * 25 >= total" :label="t('JRC_SERVICE_DESK.STRUCTURE.next')" @click="turn(1)" /></div>
  </fieldset>
</template>
