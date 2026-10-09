<script setup>
const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
  serviceId: { type: String, default: '' },
  ticketTypeId: { type: String, default: '' },
  categoryId: { type: String, default: '' },
  subcategoryId: { type: String, default: '' },
  editing: Boolean,
  unitId: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'ready', 'catalogue']);
const requiredMarker = '*';
import { onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/serviceDeskLifecycle';
import State from './ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import {
  catalogueAnswers,
  decodeCatalogueForm,
  retainedCatalogueAnswers,
} from '../helpers/catalogueFields';
const session = useServiceDesk();
const fields = ref([]);
const status = ref('idle');
const hasCatalogue = () =>
  !!(
    props.serviceId ||
    props.ticketTypeId ||
    props.categoryId ||
    props.subcategoryId
  );
let epoch = 0;
let controller;
const validate = () => {
  try {
    catalogueAnswers(fields.value, props.modelValue);
    emit('ready', !hasCatalogue() || status.value === 'ready');
  } catch {
    emit('ready', false);
  }
};
const load = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  fields.value = [];
  emit('ready', !hasCatalogue());
  emit('catalogue', null);
  if (!hasCatalogue() || !props.unitId || session.state.status !== 'ready') {
    status.value = 'idle';
    if (!hasCatalogue() && Object.keys(props.modelValue).length)
      emit('update:modelValue', {});
    return;
  }
  const context = session.state.context;
  status.value = 'loading';
  try {
    const selection = { unit_id: props.unitId };
    [
      ['service_id', props.serviceId],
      ['ticket_type_id', props.ticketTypeId],
      ['category_id', props.categoryId],
      ['subcategory_id', props.subcategoryId],
    ].forEach(([key, value]) => {
      if (value || props.editing) selection[key] = value || null;
    });
    const payload = await API.catalogueForm(
      context.account_id,
      selection,
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context) return;
    const catalogue = decodeCatalogueForm(payload, context, selection);
    fields.value = catalogue.form_fields;
    emit(
      'update:modelValue',
      retainedCatalogueAnswers(fields.value, props.modelValue)
    );
    emit('catalogue', catalogue);
    status.value = 'ready';
    validate();
  } catch {
    if (turn === epoch) status.value = 'error';
  }
};
const update = (field, event) => {
  let value = event.target.value;
  if (field.type === 'boolean') value = event.target.checked;
  if (field.type === 'integer' && value !== '') value = Number(value);
  emit('update:modelValue', { ...props.modelValue, [field.key]: value });
};
watch(
  [
    () => props.serviceId,
    () => props.ticketTypeId,
    () => props.categoryId,
    () => props.subcategoryId,
    () => props.editing,
    () => props.unitId,
    () => session.state.context,
    () => session.state.status,
  ],
  load,
  { immediate: true }
);
watch(() => props.modelValue, validate, { deep: true });
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  fields.value = [];
});
</script>

<template>
  <div class="grid gap-3">
    <State
      v-if="['loading', 'error'].includes(status)"
      :status="status"
      compact
      retry
      @retry="load"
    />
    <label v-for="field in fields" :key="field.key" class="grid gap-1 text-sm">
      <span>{{ field.label }} {{ field.required ? requiredMarker : '' }}</span>
      <input
        v-if="field.type === 'boolean'"
        type="checkbox"
        :checked="modelValue[field.key] === true"
        :disabled="disabled"
        @change="update(field, $event)"
      />
      <select
        v-else-if="field.type === 'select'"
        class="border border-n-weak rounded-lg p-2"
        :value="modelValue[field.key] || ''"
        :disabled="disabled"
        :required="field.required"
        @change="update(field, $event)"
      >
        <option value="" />
        <option v-for="option in field.options" :key="option" :value="option">
          {{ option }}
        </option>
      </select>
      <input
        v-else
        class="border border-n-weak rounded-lg p-2"
        :type="field.type === 'integer' ? 'number' : 'text'"
        :value="modelValue[field.key] ?? ''"
        :disabled="disabled"
        :required="field.required"
        maxlength="4000"
        @input="update(field, $event)"
      />
    </label>
  </div>
</template>
