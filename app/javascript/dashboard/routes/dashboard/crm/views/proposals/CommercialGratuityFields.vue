<script setup>
import { useI18n } from 'vue-i18n';
const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const types = [
  'installation',
  'monthly_fee',
  'product',
  'service',
  'benefit',
  'promotion',
  'bonus',
];
const setType = type =>
  emit(
    'update:modelValue',
    type ? { type, reason: props.modelValue.reason || '' } : {}
  );
const setReason = reason =>
  emit('update:modelValue', { ...props.modelValue, reason });
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="space-y-2 rounded-lg border border-n-weak bg-n-alpha-2 p-3"
  >
    <legend class="px-1 text-sm font-medium">
      {{ t('CRM.GRATUITY.TITLE') }}
    </legend>
    <select
      :value="modelValue.type || ''"
      class="w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
      :aria-label="t('CRM.GRATUITY.TYPE')"
      @change="setType($event.target.value)"
    >
      <option value="">{{ t('CRM.GRATUITY.NONE') }}</option>
      <option v-for="type in types" :key="type" :value="type">
        {{ t(`CRM.GRATUITY.TYPES.${type}`) }}
      </option>
    </select>
    <input
      v-if="modelValue.type"
      :value="modelValue.reason"
      required
      minlength="3"
      maxlength="500"
      class="w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
      :aria-label="t('CRM.GRATUITY.REASON')"
      :placeholder="t('CRM.GRATUITY.REASON')"
      @input="setReason($event.target.value)"
    />
    <p class="text-xs text-n-slate-11">{{ t('CRM.GRATUITY.HELP') }}</p>
  </fieldset>
</template>
