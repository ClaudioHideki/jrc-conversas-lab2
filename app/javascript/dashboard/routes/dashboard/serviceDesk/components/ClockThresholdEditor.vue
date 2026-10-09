<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LookupSelect from './LookupSelect.vue';
const props = defineProps({
  modelValue: { type: Object, required: true },
  unitId: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const rows = computed(() =>
  Array.isArray(props.modelValue.thresholds) ? props.modelValue.thresholds : []
);
function change(values) {
  if (props.disabled) return;
  emit('update:modelValue', {
    ...props.modelValue,
    ...values,
    automatic: false,
  });
}
function add() {
  if (rows.value.length >= 20) return;
  change({
    enabled: props.modelValue.enabled === true,
    thresholds: [
      ...rows.value,
      { percent: null, queue_id: null, team_id: null },
    ],
  });
}
function patch(index, field, value) {
  change({
    thresholds: rows.value.map((row, i) =>
      i === index
        ? {
            ...row,
            [field]: value,
            ...(field === 'queue_id' ? { team_id: null } : {}),
          }
        : row
    ),
  });
}
function remove(index) {
  const thresholds = rows.value.filter((_, i) => i !== index);
  if (!props.disabled && !thresholds.length) emit('update:modelValue', {});
  else change({ thresholds });
}
function percent(index, value) {
  patch(
    index,
    'percent',
    /^[1-9][0-9]?$|^100$/.test(value) ? Number(value) : null
  );
}
</script>

<template>
  <fieldset
    class="grid gap-3 rounded-xl border border-n-weak p-4"
    :disabled="disabled"
  >
    <legend class="font-semibold text-sm">
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.designer.thresholds') }}
    </legend>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.designer.threshold_notice') }}
    </p>
    <label
      v-if="rows.length"
      class="inline-flex items-center gap-2 text-sm font-medium text-n-slate-12"
      ><input
        type="checkbox"
        :checked="modelValue.enabled === true"
        @change="change({ enabled: $event.target.checked })"
      />
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.designer.monitoring_enabled') }}</label
    >
    <div
      v-for="(row, index) in rows"
      :key="index"
      class="grid gap-3 md:grid-cols-3 border-b border-n-weak pb-3"
    >
      <label class="grid gap-1 text-sm"
        >{{ t('JRC_SERVICE_DESK.EXPERIENCE.designer.percent')
        }}<input
          type="number"
          min="1"
          max="100"
          step="1"
          :value="row.percent"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
          @input="percent(index, $event.target.value)"
      /></label>
      <LookupSelect
        :model-value="String(row.queue_id || '')"
        resource="queues"
        :unit-id="unitId"
        :disabled="disabled"
        :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
        @update:model-value="patch(index, 'queue_id', $event || null)"
      />
      <LookupSelect
        :model-value="String(row.team_id || '')"
        resource="teams"
        :unit-id="unitId"
        :disabled="disabled || !row.queue_id"
        :label="t('JRC_SERVICE_DESK.FIELDS.team')"
        @update:model-value="patch(index, 'team_id', $event || null)"
      />
      <Button
        type="button"
        variant="ghost"
        size="xs"
        :disabled="disabled"
        :label="t('JRC_SERVICE_DESK.EXPERIENCE.remove')"
        @click="remove(index)"
      />
    </div>
    <Button
      type="button"
      variant="outline"
      size="sm"
      :disabled="disabled || rows.length >= 20"
      :label="t('JRC_SERVICE_DESK.EXPERIENCE.designer.add_threshold')"
      @click="add"
    />
  </fieldset>
</template>
