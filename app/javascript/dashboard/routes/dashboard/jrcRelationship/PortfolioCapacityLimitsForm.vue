<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { buttonClass, inputClass } from './definitions';

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  owners: { type: Array, default: () => [] },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'validity']);
const { t } = useI18n();
const valid = computed(() => {
  const ids = props.modelValue.map(row => row.user_id);
  return (
    new Set(ids).size === ids.length &&
    props.modelValue.every(
      row =>
        ['customers', 'points', 'hours'].includes(row.unit || 'customers') &&
        Number.isSafeInteger(row.user_id) &&
        row.user_id > 0 &&
        ((row.unit || 'customers') === 'customers'
          ? Number.isSafeInteger(row.maximum)
          : Number.isFinite(row.maximum)) &&
        row.maximum >= 0 &&
        row.maximum <= Number.MAX_SAFE_INTEGER &&
        ['availability', 'dedication'].every(
          key => Number.isFinite(row[key]) && row[key] >= 0 && row[key] <= 1
        )
    )
  );
});
watch(valid, value => emit('validity', value), { immediate: true });
const change = (index, key, value) => {
  if (props.disabled) return;
  emit(
    'update:modelValue',
    props.modelValue.map((row, position) =>
      position === index ? { ...row, [key]: value } : row
    )
  );
};
const add = () => {
  if (props.disabled) return;
  const owner = props.owners.find(
    row => !props.modelValue.some(limit => limit.user_id === row[0])
  );
  if (owner)
    emit('update:modelValue', [
      ...props.modelValue,
      {
        user_id: owner[0],
        maximum: 0,
        availability: 1,
        dedication: 1,
      },
    ]);
};
const remove = index => {
  if (!props.disabled)
    emit(
      'update:modelValue',
      props.modelValue.filter((_, position) => position !== index)
    );
};
</script>

<template>
  <fieldset
    class="my-5 min-w-0 space-y-3 rounded-xl border border-n-weak p-3"
    :disabled="disabled"
  >
    <legend class="font-semibold">
      {{ t('RELATIONSHIP.CAPACITY.TITLE') }}
    </legend>
    <p class="text-sm">{{ t('RELATIONSHIP.CAPACITY.POLICY_NOTICE') }}</p>
    <div
      v-for="(row, index) in modelValue"
      :key="index"
      class="grid min-w-0 gap-3 rounded-lg bg-n-alpha-2 p-3 sm:grid-cols-2 lg:grid-cols-5"
    >
      <label class="min-w-0 text-sm"
        >{{ t('RELATIONSHIP.CAPACITY.ANALYST') }}
        <select
          :value="row.user_id"
          :class="inputClass"
          @change="change(index, 'user_id', Number($event.target.value))"
        >
          <option
            v-if="!owners.some(owner => owner[0] === row.user_id)"
            :value="row.user_id"
          >
            {{ t('RELATIONSHIP.CAPACITY.PRESERVED_ANALYST') }}
          </option>
          <option
            v-for="owner in owners"
            :key="owner[0]"
            :value="owner[0]"
          >
            {{ owner[1] }}
          </option>
        </select>
      </label>
      <label class="text-sm">
        {{ t('RELATIONSHIP.CAPACITY.UNIT') }}
        <select
          :value="row.unit || 'customers'"
          :class="inputClass"
          @change="change(index, 'unit', $event.target.value)"
        >
          <option
            v-for="unit in ['customers', 'points', 'hours']"
            :key="unit"
            :value="unit"
          >
            {{ t(`RELATIONSHIP.CAPACITY.UNITS.${unit}`) }}
          </option>
        </select>
      </label>
      <label class="text-sm"
        >{{ t('RELATIONSHIP.CAPACITY.MAXIMUM') }}
        <input
          :value="row.maximum"
          type="number"
          min="0"
          :step="(row.unit || 'customers') === 'customers' ? '1' : 'any'"
          required
          :class="inputClass"
          @input="
            change(
              index,
              'maximum',
              $event.target.value === '' ? null : Number($event.target.value)
            )
          "
        />
      </label>
      <label
        v-for="key in ['availability', 'dedication']"
        :key="key"
        class="text-sm"
        >{{ t(`RELATIONSHIP.CAPACITY.${key.toUpperCase()}`) }}
        <input
          :value="row[key] * 100"
          type="number"
          min="0"
          max="100"
          step="0.01"
          required
          :class="inputClass"
          @input="
            change(
              index,
              key,
              $event.target.value === ''
                ? null
                : Number($event.target.value) / 100
            )
          "
        />
      </label>
      <button
        type="button"
        :class="buttonClass"
        @click="remove(index)"
      >
        {{ t('RELATIONSHIP.CAPACITY.REMOVE') }}
      </button>
    </div>
    <p
      v-if="!valid"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('RELATIONSHIP.CAPACITY.INVALID') }}
    </p>
    <button
      type="button"
      :class="buttonClass"
      :disabled="
        !owners.some(owner => !modelValue.some(row => row.user_id === owner[0]))
      "
      @click="add"
    >
      {{ t('RELATIONSHIP.CAPACITY.ADD') }}
    </button>
  </fieldset>
</template>
