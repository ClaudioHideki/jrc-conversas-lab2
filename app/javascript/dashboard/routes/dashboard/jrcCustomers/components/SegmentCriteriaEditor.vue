<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  T,
  RELATIONSHIPS,
  PERSON_KINDS,
  SIZE_OPTIONS,
  SOURCE_OPTIONS,
  inputClass,
  buttonClass,
} from '../copy';
import { segmentFields } from './segmentCopy';

const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
  metadata: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const fields = computed(() => segmentFields(t));
const valueOptions = field =>
  ({
    relationship_type: RELATIONSHIPS,
    person_kind: PERSON_KINDS,
    size: SIZE_OPTIONS,
    source: SOURCE_OPTIONS,
    active: { true: T.active, false: T.inactive },
    owner_id: Object.fromEntries(
      (props.metadata.owners || []).map(owner => [String(owner.id), owner.name])
    ),
    segment: Object.fromEntries(
      (props.metadata.segments || []).map(name => [name, name])
    ),
    economic_group: Object.fromEntries(
      (props.metadata.economic_groups || []).map(name => [name, name])
    ),
  })[field];
const change = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const setRule = (index, key, value) =>
  change(
    'rules',
    props.modelValue.rules.map((rule, i) =>
      i === index ? { ...rule, [key]: value } : rule
    )
  );
const setField = (index, field) =>
  change(
    'rules',
    props.modelValue.rules.map((rule, i) =>
      i === index
        ? {
            ...rule,
            field,
            value: Object.keys(valueOptions(field) || {})[0] || '',
          }
        : rule
    )
  );
const add = () =>
  change('rules', [
    ...props.modelValue.rules,
    { field: 'relationship_type', operator: 'equal_to', value: 'customer' },
  ]);
const remove = index =>
  change(
    'rules',
    props.modelValue.rules.filter((_, i) => i !== index)
  );
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="space-y-3"
  >
    <label class="block text-sm">
      {{ t('CRM.CORPORATE_SEGMENTS.MATCH') }}
      <select
        :value="modelValue.match"
        :class="inputClass"
        @change="change('match', $event.target.value)"
      >
        <option value="all">{{ t('CRM.CORPORATE_SEGMENTS.ALL') }}</option>
        <option value="any">{{ t('CRM.CORPORATE_SEGMENTS.ANY') }}</option>
      </select>
    </label>
    <div
      v-for="(rule, index) in modelValue.rules"
      :key="index"
      class="grid gap-2 rounded-lg border border-n-weak p-3 sm:grid-cols-4"
    >
      <label class="text-xs">
        {{ t('CRM.CORPORATE_SEGMENTS.FIELD') }}
        <select
          :value="rule.field"
          :class="inputClass"
          @change="setField(index, $event.target.value)"
        >
          <option
            v-for="(label, key) in fields"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
      </label>
      <label class="text-xs">
        {{ t('CRM.CORPORATE_SEGMENTS.OPERATOR') }}
        <select
          :value="rule.operator"
          :class="inputClass"
          @change="setRule(index, 'operator', $event.target.value)"
        >
          <option value="equal_to">
            {{ t('CRM.CORPORATE_SEGMENTS.EQUAL') }}
          </option>
          <option value="not_equal_to">
            {{ t('CRM.CORPORATE_SEGMENTS.NOT_EQUAL') }}
          </option>
        </select>
      </label>
      <label class="text-xs">
        {{ t('CRM.CORPORATE_SEGMENTS.VALUE') }}
        <select
          v-if="valueOptions(rule.field)"
          :value="rule.value"
          :class="inputClass"
          required
          @change="setRule(index, 'value', $event.target.value)"
        >
          <option
            v-if="
              rule.value && !Object.hasOwn(valueOptions(rule.field), rule.value)
            "
            :value="rule.value"
          >
            {{ rule.value }}
          </option>
          <option
            v-for="(label, key) in valueOptions(rule.field)"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
        <input
          v-else
          :value="rule.value"
          :class="inputClass"
          maxlength="200"
          required
          @input="setRule(index, 'value', $event.target.value)"
        />
      </label>
      <button
        type="button"
        :class="buttonClass"
        @click="remove(index)"
      >
        {{ t('CRM.CORPORATE_SEGMENTS.REMOVE_RULE') }}
      </button>
    </div>
    <button
      type="button"
      :class="buttonClass"
      :disabled="modelValue.rules.length >= 20"
      @click="add"
    >
      {{ t('CRM.CORPORATE_SEGMENTS.ADD_RULE') }}
    </button>
    <p class="text-xs text-n-slate-10">
      {{ t('CRM.CORPORATE_SEGMENTS.CRITERIA_HELP') }}
    </p>
  </fieldset>
</template>
