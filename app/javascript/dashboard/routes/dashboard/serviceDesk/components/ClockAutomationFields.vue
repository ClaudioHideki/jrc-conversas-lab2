<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LookupSelect from './LookupSelect.vue';
import { canonicalId } from '../helpers/access';
import { escalationPolicy } from '../helpers/v2Configuration';
const props = defineProps({
  modelValue: { type: Object, required: true },
  unitId: { type: String, default: '' },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const automatic = computed(() => props.modelValue.automatic === true);
const executor = computed(
  () => canonicalId(props.modelValue.execution_account_user_id) || ''
);
const mayEnable = computed(() => {
  try {
    const policy = escalationPolicy(props.modelValue);
    return policy.enabled === true && !!executor.value && !!props.unitId;
  } catch {
    return false;
  }
});
const changeExecutor = value => {
  if (props.disabled) return;
  const id = value ? canonicalId(value) : null;
  if (value && !id) return;
  emit('update:modelValue', {
    ...props.modelValue,
    execution_account_user_id: id,
    automatic: false,
  });
};
const changeAutomatic = value => {
  if (props.disabled || (value && !mayEnable.value)) return;
  emit('update:modelValue', { ...props.modelValue, automatic: value });
};
</script>

<template>
  <fieldset
    class="grid gap-2 border border-n-weak rounded-lg p-3"
    :disabled="disabled"
  >
    <legend>{{ t('JRC_SERVICE_DESK.CLOCK_AUTOMATION.title') }}</legend>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.CLOCK_AUTOMATION.notice') }}
    </p>
    <LookupSelect
      :model-value="executor"
      resource="assignees"
      :unit-id="unitId"
      :disabled="disabled || !modelValue.thresholds?.length"
      :label="t('JRC_SERVICE_DESK.CLOCK_AUTOMATION.executor')"
      @update:model-value="changeExecutor"
    />
    <label class="text-sm">
      <input
        type="checkbox"
        data-clock-automatic
        :checked="automatic"
        :disabled="disabled || (!automatic && !mayEnable)"
        @change="changeAutomatic($event.target.checked)"
      />
      {{ t('JRC_SERVICE_DESK.CLOCK_AUTOMATION.enabled') }}
    </label>
  </fieldset>
</template>
