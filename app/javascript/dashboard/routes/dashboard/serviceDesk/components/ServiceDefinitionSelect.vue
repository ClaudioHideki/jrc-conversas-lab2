<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import API from 'dashboard/api/serviceDeskLifecycle';
import State from './ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeConfigurationList } from '../helpers/lifecycle';
const props = defineProps({ modelValue: { type: String, default: '' }, unitId: { type: String, default: '' }, disabled: Boolean });
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n(); const session = useServiceDesk();
const page = ref(1); const items = ref([]); const total = ref(0); const status = ref('idle');
let epoch = 0; let controller;
const selected = computed({ get: () => props.modelValue, set: value => emit('update:modelValue', value) });
const load = async () => {
  const current = ++epoch; controller?.abort(); controller = new AbortController(); items.value = []; total.value = 0;
  if (!props.unitId || session.state.status !== 'ready') { status.value = 'idle'; return; }
  const context = session.state.context; status.value = 'loading';
  try {
    const response = await API.services(context.account_id, props.unitId, page.value, controller.signal);
    if (current !== epoch || context !== session.state.context) return;
    const result = decodeConfigurationList(response, context, props.unitId, 'services');
    items.value = result.items; total.value = result.meta.total; status.value = result.items.length ? 'ready' : 'empty';
  } catch { if (current === epoch) status.value = 'error'; }
};
watch([() => props.unitId, () => session.state.context, () => session.state.status], () => { page.value = 1; load(); }, { immediate: true });
watch(page, load);
onBeforeUnmount(() => { epoch += 1; controller?.abort(); items.value = []; });
</script>
<template>
  <div class="grid gap-2">
    <label class="text-sm">{{ t('JRC_SERVICE_DESK.LIFECYCLE.service') }}</label>
    <Select v-model="selected" :disabled="disabled || !unitId || status === 'loading'" :options="[{ value: '', label: t('JRC_SERVICE_DESK.LIFECYCLE.unit_policy') }, ...items.map(row => ({ value: row.id, label: row.name }))]" />
    <p v-if="modelValue && !items.some(row => row.id === modelValue)" class="text-xs">{{ t('JRC_SERVICE_DESK.COMMON.selected_identifier', { id: modelValue }) }}</p>
    <State v-if="['loading', 'error'].includes(status)" :status="status" compact retry @retry="load" />
    <Pagination v-if="total > 20" :current-page="page" :items-per-page="20" :total-items="total" @update:current-page="page = $event" />
    <Button size="xs" variant="ghost" :disabled="!unitId || disabled" :label="t('JRC_SERVICE_DESK.COMMON.refresh')" @click="load" />
  </div>
</template>
