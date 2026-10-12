<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TypedValue from './TypedValue.vue';
import { copy, OPERATORS } from './model';
const props = defineProps({
  modelValue: { type: Object, required: true },
  fields: { type: Object, required: true },
  depth: { type: Number, default: 0 },
  budget: { type: Number, default: 1 },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const invalid = ref(false);
const kind = computed(() => {
  if (props.modelValue.all) return 'all';
  if (props.modelValue.any) return 'any';
  return Object.hasOwn(props.modelValue, 'const') ? 'const' : 'simple';
});
const children = computed(() => props.modelValue[kind.value] || []);
const type = computed(() => props.fields[props.modelValue.field] || 'string');
const changeKind = key => {
  if (key === 'simple')
    emit('update:modelValue', { field: '', op: 'eq', value: '' });
  else
    emit(
      'update:modelValue',
      key === 'const' ? { const: false } : { [key]: [{ const: false }] }
    );
};
const patch = values =>
  emit('update:modelValue', { ...copy(props.modelValue), ...values });
const child = (index, value) => {
  const rows = copy(children.value);
  rows[index] = value;
  emit('update:modelValue', { [kind.value]: rows });
};
const add = () => {
  if (children.value.length < 8 && props.budget < 32 && props.depth < 4)
    emit('update:modelValue', {
      [kind.value]: [...copy(children.value), { const: false }],
    });
};
const remove = index =>
  emit('update:modelValue', {
    [kind.value]: children.value.filter((_, i) => i !== index),
  });
const values = computed(() =>
  ['in', 'between'].includes(props.modelValue.op)
    ? props.modelValue.value
    : [props.modelValue.value]
);
const operator = op =>
  patch({ op, value: ['in', 'between'].includes(op) ? ['', ''] : '' });
const setValue = (index, value) => {
  if (!['in', 'between'].includes(props.modelValue.op)) {
    patch({ value });
    return;
  }
  const rows = copy(values.value);
  rows[index] = value;
  patch({ value: rows });
};
</script>

<template>
  <fieldset
    class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3"
  >
    <legend class="px-1 text-xs text-n-slate-11">
      {{ t('JRC_APPROVALS.condition') }} · {{ depth }}/{{ 4 }}
    </legend>
    <label class="block text-sm"
      >{{ t('JRC_APPROVALS.kind')
      }}<select
        :value="kind"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        @change="changeKind($event.target.value)"
      >
        <option value="simple">{{ t('JRC_APPROVALS.simple') }}</option>
        <option value="const">{{ t('JRC_APPROVALS.constant') }}</option>
        <option
          v-if="depth < 4"
          value="all"
        >
          {{ t('JRC_APPROVALS.enum_ALL') }}
        </option>
        <option
          v-if="depth < 4"
          value="any"
        >
          {{ t('JRC_APPROVALS.enum_ANY') }}
        </option>
      </select></label
    >
    <label
      v-if="kind === 'const'"
      class="block text-sm"
      >{{ t('JRC_APPROVALS.value')
      }}<select
        :value="String(modelValue.const)"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        @change="patch({ const: $event.target.value === 'true' })"
      >
        <option value="false">{{ t('JRC_APPROVALS.enum_false') }}</option>
        <option value="true">{{ t('JRC_APPROVALS.enum_true') }}</option>
      </select></label
    >
    <template v-else-if="kind === 'simple'">
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="text-sm"
          >{{ t('JRC_APPROVALS.field')
          }}<select
            :value="modelValue.field"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            @change="patch({ field: $event.target.value, op: 'eq', value: '' })"
          >
            <option value="">{{ t('JRC_APPROVALS.select') }}</option>
            <option
              v-for="(fieldType, name) in fields"
              :key="name"
              :value="name"
            >
              {{ name }} ({{ fieldType }})
            </option>
          </select></label
        ><label class="text-sm"
          >{{ t('JRC_APPROVALS.operator')
          }}<select
            :value="modelValue.op"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            @change="operator($event.target.value)"
          >
            <option
              v-for="op in OPERATORS[type]"
              :key="op"
            >
              {{ op }}
            </option>
          </select></label
        >
      </div>
      <TypedValue
        v-for="(value, index) in values"
        :key="index"
        :model-value="value"
        :type="type"
        :label="`${t('JRC_APPROVALS.value')} ${index + 1}`"
        @update:model-value="setValue(index, $event)"
        @error="invalid = $event"
      />
      <p
        v-if="invalid"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('JRC_APPROVALS.typedError') }}
      </p>
      <button
        v-if="modelValue.op === 'in' && values.length < 32"
        type="button"
        class="text-sm text-n-blue-11"
        @click="patch({ value: [...values, ''] })"
      >
        {{ t('JRC_APPROVALS.addValue') }}
      </button>
    </template>
    <template v-else>
      <div
        v-for="(node, index) in children"
        :key="index"
        class="space-y-2"
      >
        <ConditionEditor
          :model-value="node"
          :fields="fields"
          :depth="depth + 1"
          :budget="budget"
          @update:model-value="child(index, $event)"
        /><button
          v-if="children.length > 1"
          type="button"
          class="text-sm text-n-ruby-11"
          @click="remove(index)"
        >
          {{ t('JRC_APPROVALS.remove') }}
        </button>
      </div>
      <button
        type="button"
        :disabled="children.length >= 8 || budget >= 32 || depth >= 4"
        class="text-sm text-n-blue-11 disabled:opacity-50"
        @click="add"
      >
        {{ t('JRC_APPROVALS.addCondition') }}
      </button>
    </template>
  </fieldset>
</template>
