<script setup>
// Unit-test boundary only; no lookup policy or HTTP success is simulated here.
defineProps({
  modelValue: { type: String, default: '' },
  resource: { type: String, required: true },
  unitId: { type: String, required: true },
  currentName: { type: String, default: '' },
  teamId: { type: String, default: '' },
  queueId: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'selected']);
const change = event => {
  emit('update:modelValue', event.target.value);
  emit('selected', null);
};
</script>

<template>
  <div
    :data-value="modelValue"
    :data-resource="resource"
    :data-unit-id="unitId"
    :data-current-name="currentName"
    :data-team="teamId"
    :data-queue="queueId"
    :aria-disabled="disabled"
    @change="change"
  />
</template>
