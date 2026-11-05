<script setup>
import { useI18n } from 'vue-i18n';
import { inputClass } from './definitions';
const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const factors = [
  'base',
  'complexity_factor',
  'risk_factor',
  'journey_factor',
  'activity_effort',
];
const toggle = (unit, enabled) => {
  if (props.disabled) return;
  const next = { ...props.modelValue };
  if (enabled)
    next[unit] =
      unit === 'points'
        ? Object.fromEntries(factors.map(key => [key, null]))
        : null;
  else delete next[unit];
  emit('update:modelValue', next);
};
const change = (unit, key, raw) => {
  if (props.disabled) return;
  const value = raw === '' ? null : Number(raw);
  emit('update:modelValue', {
    ...props.modelValue,
    [unit]: key ? { ...props.modelValue[unit], [key]: value } : value,
  });
};
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="min-w-0 space-y-3 rounded-lg border border-n-violet-6 bg-n-violet-2 p-3"
  >
    <legend class="font-semibold">
      {{ t('RELATIONSHIP.CAPACITY.WORKLOAD.TITLE') }}
    </legend>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.CAPACITY.WORKLOAD.NOTE') }}
    </p>
    <div
      v-for="unit in ['points', 'hours']"
      :key="unit"
      class="space-y-2"
    >
      <label class="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          :checked="Object.hasOwn(modelValue, unit)"
          :data-testid="`enable-${unit}`"
          @change="toggle(unit, $event.target.checked)"
        />
        {{ t(`RELATIONSHIP.CAPACITY.UNITS.${unit}`) }}
      </label>
      <div
        v-if="Object.hasOwn(modelValue, unit)"
        class="grid min-w-0 gap-3 sm:grid-cols-2"
      >
        <label
          v-for="key in unit === 'points' ? factors : ['hours']"
          :key="key"
          class="min-w-0 text-sm"
        >
          {{ t(`RELATIONSHIP.CAPACITY.WORKLOAD.${key}`) }}
          <input
            type="number"
            min="0"
            max="9007199254740991"
            step="any"
            required
            :class="inputClass"
            :value="
              unit === 'points' ? modelValue.points[key] : modelValue.hours
            "
            :data-testid="`workload-${key}`"
            @input="
              change(unit, unit === 'points' ? key : null, $event.target.value)
            "
          />
        </label>
      </div>
    </div>
  </fieldset>
</template>
