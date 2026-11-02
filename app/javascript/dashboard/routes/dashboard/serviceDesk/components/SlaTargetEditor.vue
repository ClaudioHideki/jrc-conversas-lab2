<script setup>
import { computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { jsonObject } from '../helpers/operationalRules.mjs';
import { durationSeconds, durationUnits } from '../helpers/slaTargets';
const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const units = reactive({
  first_response: 'minutes',
  resolution: 'minutes',
  attendance: 'minutes',
});
const read = field => {
  try {
    return jsonObject(props.modelValue[field] || '{}');
  } catch {
    return null;
  }
};
const policy = computed(() => read('policy_conditions'));
const calendar = computed(() => read('calendar_conditions'));
const kinds = computed(() => [
  'first_response',
  'resolution',
  ...(Object.hasOwn(policy.value?.clock_budgets_seconds || {}, 'attendance')
    ? ['attendance']
    : []),
]);
const set = (field, object) => {
  if (!props.disabled)
    emit('update:modelValue', {
      ...props.modelValue,
      [field]: JSON.stringify(object, null, 2),
    });
};
const amount = kind => {
  const seconds = policy.value?.clock_budgets_seconds?.[kind];
  return Number.isSafeInteger(seconds)
    ? String(seconds / durationUnits[units[kind]])
    : seconds || '';
};
const target = (kind, value) => {
  if (!policy.value) return;
  let seconds;
  try {
    seconds = durationSeconds(value, units[kind]);
  } catch {
    seconds = value;
  }
  set('policy_conditions', {
    ...policy.value,
    clock_budgets_seconds: {
      ...policy.value.clock_budgets_seconds,
      [kind]: seconds,
    },
  });
};
const validTarget = kind =>
  Number.isSafeInteger(policy.value?.clock_budgets_seconds?.[kind]) &&
  policy.value.clock_budgets_seconds[kind] > 0;
const intervals = day =>
  (calendar.value?.weekly?.[day] || []).map(pair => pair.join('-')).join(';');
const day = (key, value) => {
  if (!calendar.value) return;
  const weekly = {
    ...Object.fromEntries(
      Array.from({ length: 7 }, (_, i) => [String(i + 1), []])
    ),
    ...calendar.value.weekly,
  };
  weekly[key] = value.trim()
    ? value.split(';').map(pair =>
        pair
          .trim()
          .split('-')
          .map(time => time.trim())
      )
    : [];
  set('calendar_conditions', {
    ...calendar.value,
    format: calendar.value.format || 'jrc-sd-snapshot-calendar-v1',
    weekly,
    holidays: calendar.value.holidays || [],
    exceptions: calendar.value.exceptions || {},
  });
};
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="grid gap-4 rounded-lg border border-n-blue-5 bg-n-blue-2 p-4"
    data-testid="sla-target-editor"
  >
    <legend class="font-semibold">
      {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.targets_title') }}
    </legend>
    <p class="text-sm">{{ t('JRC_SERVICE_DESK.SIMPLE_SLA.targets_help') }}</p>
    <p v-if="!policy || !calendar" role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.invalid_json') }}
    </p>
    <div v-for="kind in kinds" :key="kind" class="grid gap-2 sm:grid-cols-2">
      <label class="grid gap-1 text-sm"
        >{{ t(`JRC_SERVICE_DESK.SIMPLE_SLA.targets.${kind}`) }}
        <input
          :value="amount(kind)"
          type="number"
          min="0"
          step="any"
          :disabled="disabled || !policy"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
          @input="target(kind, $event.target.value)"
        />
      </label>
      <label class="grid gap-1 text-sm"
        >{{ t('JRC_SERVICE_DESK.SIMPLE_SLA.duration_unit') }}
        <select
          v-model="units[kind]"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
        >
          <option
            v-for="unit in Object.keys(durationUnits)"
            :key="unit"
            :value="unit"
          >
            {{ t(`JRC_SERVICE_DESK.SIMPLE_SLA.units.${unit}`) }}
          </option>
        </select>
      </label>
      <p
        v-if="!validTarget(kind)"
        role="alert"
        class="text-xs text-n-amber-11 sm:col-span-2"
      >
        {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.invalid_target') }}
      </p>
    </div>
    <p class="text-sm">{{ t('JRC_SERVICE_DESK.SIMPLE_SLA.calendar_help') }}</p>
    <label
      v-for="key in ['1', '2', '3', '4', '5', '6', '7']"
      :key="key"
      class="grid gap-1 text-sm sm:grid-cols-2"
      >{{ t(`JRC_SERVICE_DESK.SIMPLE_SLA.weekdays.${key}`) }}
      <input
        :value="intervals(key)"
        :disabled="disabled || !calendar"
        class="rounded border border-n-weak bg-n-solid-1 p-2"
        @input="day(key, $event.target.value)"
      />
    </label>
  </fieldset>
</template>
