<script setup>
import { computed, getCurrentInstance, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  calendarIntervalsError,
  formatCalendarIntervals,
  parseCalendarIntervals,
} from 'dashboard/routes/dashboard/serviceDesk/automationStudio/calendarIntervals';
const props = defineProps({
  modelValue: { type: [Array, String], required: true },
  label: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const errorLabels = computed(() => ({
  interval_format: t(
    'JRC_CONTACT_CENTER.CALENDAR.INTERVAL_ERRORS.interval_format'
  ),
  interval_time: t('JRC_CONTACT_CENTER.CALENDAR.INTERVAL_ERRORS.interval_time'),
  interval_order: t(
    'JRC_CONTACT_CENTER.CALENDAR.INTERVAL_ERRORS.interval_order'
  ),
  interval_overlap: t(
    'JRC_CONTACT_CENTER.CALENDAR.INTERVAL_ERRORS.interval_overlap'
  ),
}));
const id = `cc-calendar-hours-${getCurrentInstance().uid}`;
const buffer = ref(null);
const value = computed(() =>
  buffer.value?.signature === JSON.stringify(props.modelValue)
    ? buffer.value.value
    : formatCalendarIntervals(props.modelValue)
);
const error = computed(() => {
  const invalid = calendarIntervalsError(props.modelValue);
  return invalid ? parseCalendarIntervals(value.value).error || invalid : null;
});
const update = input => {
  const result = parseCalendarIntervals(input);
  const next = result.valid ? result.rows : input;
  buffer.value = { value: input, signature: JSON.stringify(next) };
  emit('update:modelValue', next);
};
const canonicalize = () => {
  if (!error.value) buffer.value = null;
};
</script>

<template>
  <label class="grid min-w-0 gap-1 text-sm" :for="id">
    <span>{{ label }}</span>
    <input
      :id="id"
      :value="value"
      :disabled="disabled"
      :aria-invalid="Boolean(error)"
      :aria-describedby="error ? `${id}-error` : undefined"
      data-calendar-hours
      :placeholder="t('JRC_CONTACT_CENTER.CALENDAR.HOURS_EXAMPLE')"
      class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
      @input="update($event.target.value)"
      @blur="canonicalize"
    />
    <span
      v-if="error"
      :id="`${id}-error`"
      role="alert"
      class="break-words text-n-amber-11"
    >
      {{ errorLabels[error] }}
    </span>
  </label>
</template>
