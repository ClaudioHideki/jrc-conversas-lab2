<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
const props = defineProps({ unitId: { type: String, default: '' }, operatorId: { type: String, default: '' }, required: { type: Boolean, default: false }, disabled: { type: Boolean, default: false } });
const emit = defineEmits(['update:unitId', 'update:operatorId']);
const { t } = useI18n();
const { state } = useServiceDesk();
const units = computed(() => state.context?.units || []);
const operators = computed(() => [...new Map(units.value.map(unit => [unit.operator_company.id, unit.operator_company])).values()]);
const operatorOptions = computed(() => [{ value: '', label: t('JRC_SERVICE_DESK.COMMON.all') }, ...operators.value.map(item => ({ value: item.id, label: item.name }))]);
const unitOptions = computed(() => [
  { value: '', label: t(props.required ? 'JRC_SERVICE_DESK.SCOPE.unselected' : 'JRC_SERVICE_DESK.COMMON.all') },
  ...units.value.filter(unit => !props.operatorId || unit.operator_company.id === props.operatorId).map(unit => ({ value: unit.id, label: unit.name })),
]);
const updateOperator = value => { if (props.disabled) return; emit('update:operatorId', value); emit('update:unitId', ''); };
const updateUnit = value => {
  if (props.disabled) return;
  emit('update:unitId', value);
  if (props.required && value)
    emit('update:operatorId', units.value.find(unit => unit.id === value)?.operator_company.id || '');
};
</script>
<template>
  <div class="sd-scope-bar">
    <label class="sd-label">
      <span>
        {{ t('JRC_SERVICE_DESK.SCOPE.operator') }}
      </span>
      <Select
        :model-value="operatorId"
        :options="operatorOptions"
        :disabled="disabled || state.status !== 'ready'"
        @update:model-value="updateOperator"
      />
    </label>
    <label class="sd-label">
      <span>
        {{ t('JRC_SERVICE_DESK.SCOPE.unit') }}
      </span>
      <Select
        :model-value="unitId"
        :options="unitOptions"
        :disabled="disabled || state.status !== 'ready'"
        @update:model-value="updateUnit"
      />
    </label>
    <p class="m-0 text-xs text-n-slate-11 self-end pb-2">
      {{ t(state.status === 'ready' ? 'JRC_SERVICE_DESK.SCOPE.hint' : 'JRC_SERVICE_DESK.SCOPE.unknown') }}
    </p>
  </div>
</template>
