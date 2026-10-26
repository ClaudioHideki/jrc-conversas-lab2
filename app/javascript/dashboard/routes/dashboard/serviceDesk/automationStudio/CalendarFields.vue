<script setup>
import { computed, getCurrentInstance, reactive, ref } from 'vue';
import { validCalendar } from './calendarRules';
import {
  calendarIntervalsError,
  formatCalendarIntervals,
  parseCalendarIntervals,
} from './calendarIntervals';
import { useI18n } from 'vue-i18n';
const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.calendar.${key}`);
const field = 'w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm';
const inputId = `sd-calendar-${getCurrentInstance().uid}`;
const inputs = reactive({});
const conditions = computed(
  () =>
    props.modelValue.conditions || {
      format: 'jrc-sd-snapshot-calendar-v1',
      weekly: Object.fromEntries(
        [1, 2, 3, 4, 5, 6, 7].map(day => [String(day), []])
      ),
      holidays: [],
      exceptions: {},
    }
);
function set(key, value) {
  emit('update:modelValue', {
    ...props.modelValue,
    conditions: { ...conditions.value, [key]: value },
  });
}
function intervals(group, key) {
  return conditions.value[group]?.[String(key)] ?? [];
}
function hoursValue(group, key) {
  const rows = intervals(group, key);
  const buffer = inputs[`${group}:${key}`];
  return buffer?.signature === JSON.stringify(rows)
    ? buffer.value
    : formatCalendarIntervals(rows);
}
function hoursError(group, key) {
  const error = calendarIntervalsError(intervals(group, key));
  if (!error) return null;
  return parseCalendarIntervals(hoursValue(group, key)).error || error;
}
function updateHours(group, key, value) {
  const parsed = parseCalendarIntervals(value);
  // Invalid text remains explicit in the private editing model. Publication
  // gates reject it, so a previously valid value cannot be submitted silently.
  const rows = parsed.valid ? parsed.rows : value;
  inputs[`${group}:${key}`] = { value, signature: JSON.stringify(rows) };
  set(group, { ...conditions.value[group], [String(key)]: rows });
}
function canonicalize(group, key) {
  if (!hoursError(group, key)) delete inputs[`${group}:${key}`];
}
function repairable(group, key) {
  return (
    !!hoursError(group, key) &&
    parseCalendarIntervals(hoursValue(group, key)).valid
  );
}
const exceptionDate = ref('');
function addException() {
  if (
    !exceptionDate.value ||
    Object.hasOwn(conditions.value.exceptions, exceptionDate.value)
  )
    return;
  set('exceptions', {
    ...conditions.value.exceptions,
    [exceptionDate.value]: [],
  });
  exceptionDate.value = '';
}
function removeException(date) {
  const rows = { ...conditions.value.exceptions };
  delete rows[date];
  set('exceptions', rows);
}
</script>

<template>
  <fieldset
    class="grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    :disabled="disabled"
  >
    <legend class="text-sm font-semibold">{{ tr('title') }}</legend>
    <p class="text-xs text-n-slate-11">{{ tr('help') }}</p>
    <label class="grid gap-1 text-sm">
      {{ tr('timezone') }}
      <input
        :class="field"
        :value="modelValue.timezone || ''"
        :placeholder="tr('timezone_example')"
        @input="
          emit('update:modelValue', {
            ...modelValue,
            timezone: $event.target.value,
            conditions,
          })
        "
      />
    </label>
    <div
      v-for="day in [1, 2, 3, 4, 5, 6, 7]"
      :key="day"
      class="grid gap-1 text-sm"
    >
      <label :for="`${inputId}-day-${day}`">{{ tr(`day_${day}`) }}</label>
      <input
        :id="`${inputId}-day-${day}`"
        :class="field"
        :value="hoursValue('weekly', day)"
        :placeholder="tr('hours_example')"
        :aria-invalid="!!hoursError('weekly', day)"
        :aria-describedby="
          hoursError('weekly', day) ? `${inputId}-day-error-${day}` : undefined
        "
        @input="updateHours('weekly', day, $event.target.value)"
        @blur="canonicalize('weekly', day)"
      />
      <p
        v-if="hoursError('weekly', day)"
        :id="`${inputId}-day-error-${day}`"
        role="alert"
        class="text-xs text-n-amber-11"
      >
        {{ tr(hoursError('weekly', day)) }}
      </p>
      <button
        v-if="repairable('weekly', day)"
        type="button"
        class="justify-self-start rounded-lg border border-n-blue-5 px-3 py-2 text-xs text-n-blue-11"
        @click="
          updateHours('weekly', day, hoursValue('weekly', day));
          canonicalize('weekly', day);
        "
      >
        {{ tr('repair_hours') }}
      </button>
    </div>
    <label class="grid gap-1 text-sm">
      {{ tr('holidays') }}
      <textarea
        :class="field"
        :value="conditions.holidays.join(',')"
        :placeholder="tr('holidays_example')"
        @change="
          set(
            'holidays',
            $event.target.value
              .split(',')
              .map(v => v.trim())
              .filter(Boolean)
          )
        "
      />
    </label>
    <section class="grid gap-3 rounded-xl border border-n-weak p-3">
      <h4 class="text-sm font-medium">{{ tr('exceptions') }}</h4>
      <p class="text-xs text-n-slate-11">{{ tr('exceptions_help') }}</p>
      <div class="flex flex-wrap gap-2">
        <input
          v-model="exceptionDate"
          type="date"
          :class="field"
          :aria-label="tr('exception_date')"
        />
        <button
          type="button"
          class="rounded-lg border px-3 py-2 text-sm"
          :disabled="
            disabled ||
            !exceptionDate ||
            Object.hasOwn(conditions.exceptions, exceptionDate)
          "
          @click="addException"
        >
          {{ tr('add_exception') }}
        </button>
      </div>
      <div
        v-for="(_, date) in conditions.exceptions"
        :key="date"
        class="grid gap-2 sm:grid-cols-[8rem_minmax(0,1fr)_auto]"
      >
        <span class="py-3 text-sm">{{ date }}</span>
        <input
          :class="field"
          :value="hoursValue('exceptions', date)"
          :aria-label="`${tr('exception_hours')} ${date}`"
          :placeholder="tr('hours_example')"
          :aria-invalid="!!hoursError('exceptions', date)"
          :aria-describedby="
            hoursError('exceptions', date)
              ? `${inputId}-exception-error-${date}`
              : undefined
          "
          @input="updateHours('exceptions', date, $event.target.value)"
          @blur="canonicalize('exceptions', date)"
        />
        <button
          type="button"
          class="rounded-lg border px-3 py-2 text-sm"
          :disabled="disabled"
          @click="removeException(date)"
        >
          {{ tr('remove_exception') }}
        </button>
        <p
          v-if="hoursError('exceptions', date)"
          :id="`${inputId}-exception-error-${date}`"
          role="alert"
          class="text-xs text-n-amber-11 sm:col-span-3"
        >
          {{ tr(hoursError('exceptions', date)) }}
        </p>
        <button
          v-if="repairable('exceptions', date)"
          type="button"
          class="justify-self-start rounded-lg border border-n-blue-5 px-3 py-2 text-xs text-n-blue-11 sm:col-span-3"
          @click="
            updateHours('exceptions', date, hoursValue('exceptions', date));
            canonicalize('exceptions', date);
          "
        >
          {{ tr('repair_hours') }}
        </button>
      </div>
    </section>
    <p
      v-if="!validCalendar(modelValue)"
      class="rounded-lg bg-n-amber-2 p-3 text-xs"
      role="status"
    >
      {{ tr('invalid') }}
    </p>
  </fieldset>
</template>
