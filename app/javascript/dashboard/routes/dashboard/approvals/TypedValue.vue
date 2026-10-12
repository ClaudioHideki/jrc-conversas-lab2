<script setup>
import { computed, ref, watch, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { parseValue } from './model';
const props = defineProps({
  modelValue: { default: '', type: [String, Number, Boolean, Object] },
  type: { type: String, required: true },
  label: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue', 'error']);
const { t } = useI18n();

const invalid = ref(false);
const errorId = useId();
const moneyCurrency = ref(
  typeof props.modelValue === 'object' ? props.modelValue?.currency || '' : ''
);
watch(
  () => props.modelValue,
  value => {
    if (value && typeof value === 'object')
      moneyCurrency.value = value.currency || '';
  }
);
const display = computed(() => {
  if (props.type !== 'money') return String(props.modelValue ?? '');
  if (typeof props.modelValue === 'string') return props.modelValue;
  const cents = props.modelValue?.amount_cents;
  if (!Number.isSafeInteger(cents)) return '';
  return `${cents < 0 ? '-' : ''}${Math.floor(Math.abs(cents) / 100)}.${String(Math.abs(cents) % 100).padStart(2, '0')}`;
});
const update = (text, currency = moneyCurrency.value) => {
  try {
    emit('update:modelValue', parseValue(props.type, text, currency));
    invalid.value = false;
    emit('error', false);
  } catch {
    invalid.value = true;
    emit('update:modelValue', text);
    emit('error', true);
  }
};
const updateCurrency = currency => {
  moneyCurrency.value = currency;
  update(display.value, currency);
};
</script>

<template>
  <label class="block min-w-0 text-sm font-medium text-n-slate-12">
    {{ label }}
    <select
      v-if="type === 'boolean'"
      class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
      :value="display"
      :aria-invalid="invalid"
      :aria-describedby="invalid ? errorId : undefined"
      @change="update($event.target.value)"
    >
      <option value="">{{ t('JRC_APPROVALS.select') }}</option>
      <option value="true">{{ t('JRC_APPROVALS.enum_true') }}</option>
      <option value="false">{{ t('JRC_APPROVALS.enum_false') }}</option>
    </select>
    <input
      v-else
      class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 focus-visible:outline-blue-500"
      :value="display"
      :aria-invalid="invalid"
      :aria-describedby="invalid ? errorId : undefined"
      :placeholder="type === 'datetime' ? '2026-10-12T08:00:00-03:00' : ''"
      @change="update($event.target.value)"
    />
  </label>
  <label
    v-if="type === 'money'"
    class="block text-sm"
    >{{ t('JRC_APPROVALS.currency')
    }}<input
      class="w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
      :value="moneyCurrency"
      :aria-invalid="invalid"
      :aria-describedby="invalid ? errorId : undefined"
      maxlength="3"
      @change="updateCurrency($event.target.value)"
  /></label>
  <p
    v-if="invalid"
    :id="errorId"
    role="alert"
    class="text-sm text-n-ruby-11"
  >
    {{ t('JRC_APPROVALS.typedError') }}
  </p>
</template>
