<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { moneyCents } from './model';
import { minorAmountText } from './tierPresentation';
import TypedValue from './TypedValue.vue';
const props = defineProps({
  modelValue: { type: [String, Number, Object], default: null },
  type: { type: String, required: true },
  label: { type: String, required: true },
  included: { type: Boolean, default: null },
});
const emit = defineEmits(['change']);
const { t } = useI18n();
const invalidAmount = ref(false);
const errorId = useId();
const amountText = computed(() => minorAmountText(props.modelValue));
const amount = text => {
  try {
    const value = moneyCents(text.replace(',', '.'));
    invalidAmount.value = false;
    emit('change', { value, included: props.included });
  } catch {
    invalidAmount.value = true;
    emit('change', { value: text, included: props.included });
  }
};
const unbounded = checked => {
  invalidAmount.value = false;
  emit('change', {
    value: checked ? null : '',
    included: props.included === null ? null : !checked,
  });
};
</script>

<template>
  <fieldset class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3">
    <legend class="px-1 text-sm font-medium">{{ label }}</legend>
    <label class="flex items-center gap-2 text-sm">
      <input
        type="checkbox"
        :checked="modelValue === null"
        @change="unbounded($event.target.checked)"
      />
      {{ t('JRC_APPROVALS.tiers.unbounded') }}
    </label>
    <label
      v-if="modelValue !== null && type === 'minor_money'"
      class="block min-w-0 text-sm font-medium"
    >
      {{ label }}
      <input
        :value="amountText"
        inputmode="decimal"
        :aria-invalid="invalidAmount"
        :aria-describedby="invalidAmount ? errorId : undefined"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        @change="amount($event.target.value)"
      />
    </label>
    <p
      v-if="invalidAmount"
      :id="errorId"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_APPROVALS.typedError') }}
    </p>
    <TypedValue
      v-if="modelValue !== null && type !== 'minor_money'"
      :model-value="modelValue"
      :type="type"
      :label="label"
      @update:model-value="emit('change', { value: $event, included })"
    />
    <label
      v-if="included !== null && modelValue !== null"
      class="flex items-center gap-2 text-sm"
    >
      <input
        type="checkbox"
        :checked="included"
        @change="
          emit('change', { value: modelValue, included: $event.target.checked })
        "
      />
      {{ t('JRC_APPROVALS.tiers.includeBoundary') }}
    </label>
  </fieldset>
</template>
