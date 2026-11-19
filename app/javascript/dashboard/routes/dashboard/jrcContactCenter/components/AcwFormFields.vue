<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { acwFormAnswers, acwFormDefinition } from '../helpers/acwForms';

const props = defineProps({
  definition: { type: Object, required: true },
  modelValue: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'ready']);
const { t } = useI18n();
const labelFor = field => `${field.label}${field.required ? ' *' : ''}`;
const schema = computed(() => {
  try {
    return { fields: acwFormDefinition(props.definition).fields, valid: true };
  } catch {
    return { fields: [], valid: false };
  }
});
const ownValue = field =>
  Object.hasOwn(props.modelValue, field.key)
    ? props.modelValue[field.key]
    : null;
const booleanValue = field => {
  const value = ownValue(field);
  return typeof value === 'boolean' ? String(value) : '';
};
const update = (field, event) => {
  if (props.disabled || !schema.value.valid) return;
  let value = event.target.value;
  if (field.type === 'boolean') value = value === '' ? null : value === 'true';
  if (field.type === 'integer') value = value === '' ? null : Number(value);
  if (field.type === 'select' && value === '') value = null;
  emit('update:modelValue', { ...props.modelValue, [field.key]: value });
};
const validate = () => {
  try {
    acwFormAnswers(props.definition, props.modelValue, { complete: true });
    emit('ready', true);
  } catch {
    emit('ready', false);
  }
};
watch([() => props.definition, () => props.modelValue], validate, {
  deep: true,
  immediate: true,
});
</script>

<template>
  <fieldset class="min-w-0 space-y-3" :disabled="disabled" data-acw-form-fields>
    <p v-if="!schema.valid" class="text-sm text-n-ruby-11" role="alert">
      {{ t('JRC_CONTACT_CENTER.ACW_FORMS.INVALID_DEFINITION') }}
    </p>
    <label
      v-for="field in schema.fields"
      :key="field.key"
      class="block min-w-0 text-sm text-n-slate-12"
    >
      <span class="block break-words">{{ labelFor(field) }}</span>
      <select
        v-if="field.type === 'boolean'"
        :value="booleanValue(field)"
        :required="field.required"
        class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        :data-acw-answer="field.key"
        @change="update(field, $event)"
      >
        <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.SELECT') }}</option>
        <option value="true">
          {{ t('JRC_CONTACT_CENTER.ACW_FORMS.YES') }}
        </option>
        <option value="false">
          {{ t('JRC_CONTACT_CENTER.ACW_FORMS.NO') }}
        </option>
      </select>
      <select
        v-else-if="field.type === 'select'"
        :value="ownValue(field) ?? ''"
        :required="field.required"
        class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        :data-acw-answer="field.key"
        @change="update(field, $event)"
      >
        <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.SELECT') }}</option>
        <option v-for="option in field.options" :key="option" :value="option">
          {{ option }}
        </option>
      </select>
      <input
        v-else-if="field.type === 'integer'"
        :value="ownValue(field) ?? ''"
        type="number"
        step="1"
        :required="field.required"
        class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        :data-acw-answer="field.key"
        @input="update(field, $event)"
      />
      <textarea
        v-else
        :value="ownValue(field) ?? ''"
        rows="3"
        maxlength="4000"
        :required="field.required"
        class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        :data-acw-answer="field.key"
        @input="update(field, $event)"
      />
    </label>
  </fieldset>
</template>
