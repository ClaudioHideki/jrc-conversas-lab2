<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { acwFormDefinition } from '../helpers/acwForms';
const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'ready']);
const { t } = useI18n();
const labels = computed(() => ({
  SCHEMA_HINT: t('JRC_CONTACT_CENTER.ACW_FORMS.SCHEMA_HINT'),
  EMPTY_FIELDS: t('JRC_CONTACT_CENTER.ACW_FORMS.EMPTY_FIELDS'),
  FIELD_LABEL: t('JRC_CONTACT_CENTER.ACW_FORMS.FIELD_LABEL'),
  FIELD_TYPE: t('JRC_CONTACT_CENTER.ACW_FORMS.FIELD_TYPE'),
  CHOICES: t('JRC_CONTACT_CENTER.ACW_FORMS.CHOICES'),
  FIELD_ERROR: t('JRC_CONTACT_CENTER.ACW_FORMS.FIELD_ERROR'),
  REQUIRED_FIELD: t('JRC_CONTACT_CENTER.ACW_FORMS.REQUIRED_FIELD'),
  MOVE_UP: t('JRC_CONTACT_CENTER.ACW_FORMS.MOVE_UP'),
  MOVE_DOWN: t('JRC_CONTACT_CENTER.ACW_FORMS.MOVE_DOWN'),
  REMOVE_FIELD: t('JRC_CONTACT_CENTER.ACW_FORMS.REMOVE_FIELD'),
  ADD_FIELD: t('JRC_CONTACT_CENTER.ACW_FORMS.ADD_FIELD'),
}));
const typeLabels = computed(() => ({
  text: t('JRC_CONTACT_CENTER.ACW_FORMS.TYPES.text'),
  integer: t('JRC_CONTACT_CENTER.ACW_FORMS.TYPES.integer'),
  boolean: t('JRC_CONTACT_CENTER.ACW_FORMS.TYPES.boolean'),
  select: t('JRC_CONTACT_CENTER.ACW_FORMS.TYPES.select'),
}));
const fields = computed(() =>
  Array.isArray(props.modelValue.fields) ? props.modelValue.fields : []
);
const types = ['text', 'integer', 'boolean', 'select'];
const valid = () => {
  try {
    acwFormDefinition(props.modelValue);
    return true;
  } catch {
    return false;
  }
};
const rowValid = field => {
  try {
    acwFormDefinition({ fields: [field] });
    return true;
  } catch {
    return false;
  }
};
const update = (index, attributes) => {
  if (props.disabled) return;
  emit('update:modelValue', {
    ...props.modelValue,
    fields: fields.value.map((field, i) =>
      i === index ? { ...field, ...attributes } : field
    ),
  });
};
const add = () => {
  if (props.disabled || fields.value.length >= 50) return;
  emit('update:modelValue', {
    ...props.modelValue,
    fields: [
      ...fields.value,
      { key: crypto.randomUUID(), label: '', type: 'text', required: false },
    ],
  });
};
const remove = index => {
  if (props.disabled) return;
  emit('update:modelValue', {
    ...props.modelValue,
    fields: fields.value.filter((_, i) => i !== index),
  });
};
const changeType = (index, type) => {
  if (props.disabled || !types.includes(type)) return;
  const rows = fields.value.map((field, i) => {
    if (i !== index) return field;
    const result = { ...field, type };
    if (type === 'select')
      result.options = field.type === 'select' ? [...field.options] : [];
    else delete result.options;
    return result;
  });
  emit('update:modelValue', { ...props.modelValue, fields: rows });
};
const move = (index, direction) => {
  const next = index + direction;
  if (props.disabled || next < 0 || next >= fields.value.length) return;
  const rows = [...fields.value];
  [rows[index], rows[next]] = [rows[next], rows[index]];
  emit('update:modelValue', { ...props.modelValue, fields: rows });
};
watch(
  () => props.modelValue,
  () => emit('ready', valid()),
  { immediate: true, deep: true }
);
</script>

<template>
  <fieldset class="min-w-0 space-y-3" :disabled="disabled" data-acw-form-schema>
    <p class="text-sm text-n-slate-11">{{ labels.SCHEMA_HINT }}</p>
    <p v-if="!fields.length" class="text-sm text-n-slate-11">
      {{ labels.EMPTY_FIELDS }}
    </p>
    <section
      v-for="(field, index) in fields"
      :key="field.key"
      class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
      data-acw-schema-row
    >
      <div class="grid min-w-0 gap-3 sm:grid-cols-2">
        <label class="block min-w-0 text-sm">
          <span class="block">{{ labels.FIELD_LABEL }}</span>
          <input
            :value="field.label"
            required
            maxlength="255"
            class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-acw-schema-label
            @input="update(index, { label: $event.target.value })"
          />
        </label>
        <label class="block min-w-0 text-sm">
          <span class="block">{{ labels.FIELD_TYPE }}</span>
          <select
            :value="field.type"
            class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-acw-schema-type
            @change="changeType(index, $event.target.value)"
          >
            <option v-for="type in types" :key="type" :value="type">
              {{ typeLabels[type] }}
            </option>
          </select>
        </label>
        <label
          v-if="field.type === 'select'"
          class="block min-w-0 text-sm sm:col-span-2"
        >
          <span class="block">{{ labels.CHOICES }}</span>
          <textarea
            required
            :value="(field.options || []).join('\n')"
            rows="4"
            maxlength="25600"
            class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-acw-schema-options
            @input="
              update(index, { options: $event.target.value.split(/\r?\n/) })
            "
          />
        </label>
      </div>
      <p
        v-if="!rowValid(field)"
        class="text-sm text-n-ruby-11"
        role="alert"
        data-acw-field-error
      >
        {{ labels.FIELD_ERROR }}
      </p>
      <div class="flex min-w-0 flex-wrap items-center gap-3">
        <label class="flex items-center gap-2 text-sm">
          <input
            :checked="field.required"
            type="checkbox"
            data-acw-schema-required
            @change="update(index, { required: $event.target.checked })"
          />
          <span>{{ labels.REQUIRED_FIELD }}</span>
        </label>
        <Button
          type="button"
          :label="labels.MOVE_UP"
          size="sm"
          faded
          slate
          :disabled="disabled || index === 0"
          data-acw-schema-up
          @click="move(index, -1)"
        />
        <Button
          type="button"
          :label="labels.MOVE_DOWN"
          size="sm"
          faded
          slate
          :disabled="disabled || index === fields.length - 1"
          data-acw-schema-down
          @click="move(index, 1)"
        />
        <Button
          type="button"
          :label="labels.REMOVE_FIELD"
          size="sm"
          faded
          ruby
          :disabled="disabled"
          data-acw-schema-remove
          @click="remove(index)"
        />
      </div>
    </section>
    <Button
      type="button"
      :label="labels.ADD_FIELD"
      size="sm"
      :disabled="disabled || fields.length >= 50"
      data-add-acw-form-field
      @click="add"
    />
  </fieldset>
</template>
