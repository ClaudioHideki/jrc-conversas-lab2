<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { inputClass } from './definitions';
const props = defineProps({
  modelValue: { type: String, default: '' },
  entries: { type: Array, default: () => [] },
  category: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const eligible = computed(() =>
  props.entries.filter(row => row.category === props.category)
);
const previous = computed(
  () =>
    props.modelValue &&
    !eligible.value.some(row => row.code === props.modelValue)
);
</script>

<template>
  <label class="grid min-w-0 gap-1 text-sm">
    {{ t('RELATIONSHIP.V2.DOCS.REQUIREMENT_LINK') }}
    <select
      :value="modelValue"
      :disabled="disabled"
      :class="inputClass"
      @change="emit('update:modelValue', $event.target.value)"
    >
      <option value="">
        {{ t('RELATIONSHIP.V2.DOCS.NO_REQUIREMENT_LINK') }}
      </option>
      <option
        v-if="previous"
        :value="modelValue"
      >
        {{ modelValue }} · {{ t('RELATIONSHIP.V2.DOCS.PREVIOUS_REQUIREMENT') }}
      </option>
      <option
        v-for="entry in eligible"
        :key="entry.code"
        :value="entry.code"
      >
        {{ entry.title }}
      </option>
    </select>
  </label>
</template>
