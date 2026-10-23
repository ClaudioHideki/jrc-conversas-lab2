<script setup>
import { useI18n } from 'vue-i18n';
const props = defineProps({
  steps: { type: Array, required: true },
  modelValue: { type: String, required: true },
  labelRoot: { type: String, required: true },
  label: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const choose = step => {
  if (!props.disabled && props.steps.includes(step))
    emit('update:modelValue', step);
};
</script>

<template>
  <nav
    :aria-label="label"
    class="flex flex-wrap gap-2 border-b border-n-weak pb-4"
  >
    <button
      v-for="(step, index) in steps"
      :key="step"
      type="button"
      :disabled="disabled"
      :aria-current="modelValue === step ? 'step' : undefined"
      :class="
        modelValue === step ? 'bg-n-blue-3 text-n-blue-11 font-semibold' : ''
      "
      class="flex min-h-11 flex-[1_1_7rem] items-center gap-2 rounded-lg p-2 text-left text-xs focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-60"
      @click="choose(step)"
    >
      <span
        class="grid size-6 shrink-0 place-items-center rounded-full border border-current"
        aria-hidden="true"
        >{{ index + 1 }}</span
      >
      <span>{{ t(`${labelRoot}.${step}`) }}</span>
    </button>
  </nav>
</template>
