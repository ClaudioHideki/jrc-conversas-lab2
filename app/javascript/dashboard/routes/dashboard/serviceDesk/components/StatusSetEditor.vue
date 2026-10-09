<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import LookupSelect from './LookupSelect.vue';
import { explicitInteger } from '../helpers/lifecycleDesigner.js';
const props = defineProps({
  modelValue: { type: Array, required: true },
  unitId: { type: String, required: true },
  disabled: Boolean,
  label: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const selected = ref('');
const names = ref({});
watch(
  () => props.unitId,
  () => {
    selected.value = '';
    names.value = {};
  }
);
function choose(row) {
  if (props.disabled || !row || row.unit_id !== props.unitId) return;
  const id = explicitInteger(row.id);
  names.value = { ...names.value, [id]: row.name };
  if (!props.modelValue.includes(id))
    emit('update:modelValue', [...props.modelValue, id]);
  selected.value = '';
}
function remove(id) {
  if (!props.disabled)
    emit(
      'update:modelValue',
      props.modelValue.filter(value => value !== id)
    );
}
</script>

<template>
  <div class="grid gap-2">
    <LookupSelect
      v-model="selected"
      resource="statuses"
      :label="label"
      :unit-id="unitId"
      :disabled="disabled"
      @selected="choose"
    />
    <ul class="flex flex-wrap gap-2" :aria-label="label">
      <li
        v-for="id in modelValue"
        :key="id"
        class="rounded-full border border-n-weak px-3 py-1 text-xs"
      >
        {{ names[id] || t('JRC_SERVICE_DESK.EXPERIENCE.reference', { id }) }}
        <button
          type="button"
          class="ms-2 underline"
          :disabled="disabled"
          :aria-label="
            t('JRC_SERVICE_DESK.EXPERIENCE.remove_item', {
              name: names[id] || id,
            })
          "
          @click="remove(id)"
        >
          {{ t('JRC_SERVICE_DESK.EXPERIENCE.remove') }}
        </button>
      </li>
    </ul>
  </div>
</template>
