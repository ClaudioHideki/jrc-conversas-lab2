<script setup>
import { computed, ref } from 'vue';
import { validCalendar } from './calendarRules';
import { useI18n } from 'vue-i18n';
const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.calendar.${key}`);
const field = 'w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm';
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
function dayValue(day) {
  return (conditions.value.weekly[String(day)] || [])
    .map(pair => pair.join('-'))
    .join(',');
}
function updateDay(day, value) {
  const intervals = value.trim()
    ? value.split(',').map(pair => pair.trim().split('-'))
    : [];
  set('weekly', { ...conditions.value.weekly, [String(day)]: intervals });
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
function updateException(date, input) {
  const rows = input.trim()
    ? input.split(',').map(pair => pair.trim().split('-'))
    : [];
  set('exceptions', { ...conditions.value.exceptions, [date]: rows });
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
    <label
      v-for="day in [1, 2, 3, 4, 5, 6, 7]"
      :key="day"
      class="grid gap-1 text-sm"
    >
      {{ tr(`day_${day}`) }}
      <input
        :class="field"
        :value="dayValue(day)"
        :placeholder="tr('hours_example')"
        @change="updateDay(day, $event.target.value)"
      />
    </label>
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
        v-for="(rows, date) in conditions.exceptions"
        :key="date"
        class="grid gap-2 sm:grid-cols-[8rem_minmax(0,1fr)_auto]"
      >
        <span class="py-3 text-sm">{{ date }}</span>
        <input
          :class="field"
          :value="rows.map(pair => pair.join('-')).join(',')"
          :aria-label="tr('exception_hours')"
          :placeholder="tr('hours_example')"
          @change="updateException(date, $event.target.value)"
        />
        <button
          type="button"
          class="rounded-lg border px-3 py-2 text-sm"
          :disabled="disabled"
          @click="removeException(date)"
        >
          {{ tr('remove_exception') }}
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
