<script setup>
import { computed } from 'vue';
import { useCompositionCopy, fieldClass } from './compositionCopy';
const props = defineProps({
  fields: { type: Array, default: () => [] },
  disabled: Boolean,
});
const model = defineModel({ type: Object, required: true });
const tr = useCompositionCopy();
const selected = computed(() =>
  props.fields.find(field => field.key === model.value.key)
);
function choose(key) {
  model.value = { key, value: null };
}
function text(value) {
  model.value.value =
    selected.value?.type === 'integer' && value ? Number(value) : value;
}
</script>

<template>
  <fieldset
    :disabled="disabled || !fields.length"
    class="grid gap-2 rounded-lg border border-n-weak p-3"
  >
    <label class="grid gap-1 text-xs">
      {{ tr('form_field') }}
      <select
        :value="model.key"
        :class="fieldClass"
        @change="choose($event.target.value)"
      >
        <option value="">{{ tr('choose') }}</option>
        <option
          v-for="field in fields"
          :key="field.key"
          :value="field.key"
        >
          {{ field.label }}
        </option>
      </select>
    </label>
    <label
      v-if="selected?.type === 'select'"
      class="grid gap-1 text-xs"
    >
      {{ tr('value') }}
      <select
        v-model="model.value"
        :class="fieldClass"
      >
        <option :value="null">{{ tr('choose') }}</option>
        <option
          v-for="choice in selected.options"
          :key="choice"
          :value="choice"
        >
          {{ choice }}
        </option>
      </select>
    </label>
    <label
      v-else-if="selected?.type === 'boolean'"
      class="grid gap-1 text-xs"
    >
      {{ tr('value') }}
      <select
        v-model="model.value"
        :class="fieldClass"
      >
        <option :value="null">{{ tr('choose') }}</option>
        <option :value="true">{{ tr('yes') }}</option>
        <option :value="false">{{ tr('no') }}</option>
      </select>
    </label>
    <label
      v-else-if="selected"
      class="grid gap-1 text-xs"
    >
      {{ tr('value') }}
      <input
        :value="model.value"
        :type="selected.type === 'integer' ? 'number' : 'text'"
        :class="fieldClass"
        maxlength="255"
        @input="text($event.target.value)"
      />
    </label>
    <p
      v-if="!fields.length"
      class="text-xs text-n-amber-11"
    >
      {{ tr('form_field_missing') }}
    </p>
  </fieldset>
</template>
