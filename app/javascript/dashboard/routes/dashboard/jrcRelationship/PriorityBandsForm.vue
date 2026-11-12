<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { inputClass } from './definitions';
import { priorityCodes, validPriorityBands } from './priorityBands';
const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'validity']);
const { t } = useI18n();
const enabled = computed(() => props.modelValue.length > 0);
const valid = computed(() => validPriorityBands(props.modelValue));
watch(valid, value => emit('validity', value), { immediate: true });
const toggle = checked =>
  emit(
    'update:modelValue',
    checked ? priorityCodes.map(code => ({ code, minimum: null })) : []
  );
const update = (index, value) => {
  const rows = props.modelValue.map(row => ({ ...row }));
  rows[index].minimum = value === '' ? null : Number(value);
  emit('update:modelValue', rows);
};
</script>

<template>
  <fieldset
    class="mt-4 min-w-0 rounded-xl border border-blue-200 bg-blue-50 p-4 text-blue-950 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-100"
    :disabled="disabled"
  >
    <legend class="px-2 font-semibold">
      {{ t('RELATIONSHIP.PRIORITY_BANDS.TITLE') }}
    </legend>
    <p class="mb-3 text-sm">{{ t('RELATIONSHIP.PRIORITY_BANDS.NOTE') }}</p>
    <label class="flex items-center gap-2 text-sm font-semibold">
      <input
        type="checkbox"
        :checked="enabled"
        @change="toggle($event.target.checked)"
      />
      {{ t('RELATIONSHIP.PRIORITY_BANDS.ENABLE') }}
    </label>
    <div
      v-if="enabled"
      class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"
    >
      <label
        v-for="(code, index) in priorityCodes"
        :key="code"
        class="min-w-0 text-sm"
      >
        {{ code }} · {{ t(`RELATIONSHIP.PRIORITY_BANDS.${code}`) }}
        <input
          :aria-label="t('RELATIONSHIP.PRIORITY_BANDS.MINIMUM', { code })"
          type="number"
          min="0"
          max="100"
          step="1"
          required
          :value="modelValue[index]?.minimum ?? ''"
          :class="inputClass"
          @input="update(index, $event.target.value)"
        />
      </label>
    </div>
    <p
      v-if="!valid"
      role="alert"
      class="mt-3 text-sm font-semibold"
    >
      {{ t('RELATIONSHIP.PRIORITY_BANDS.INVALID') }}
    </p>
  </fieldset>
</template>
