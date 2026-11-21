<script setup>
import { computed, getCurrentInstance, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CalendarHoursInput from './CalendarHoursInput.vue';
import {
  calendarSchedule,
  updateCalendarSchedule,
} from '../helpers/calendarForm';
const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const { uid } = getCurrentInstance();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.CALENDAR.TITLE'),
  DETAILS: t('JRC_CONTACT_CENTER.CALENDAR.DETAILS'),
  'TABS.general': t('JRC_CONTACT_CENTER.CALENDAR.TABS.general'),
  'TABS.weekly': t('JRC_CONTACT_CENTER.CALENDAR.TABS.weekly'),
  'TABS.holidays': t('JRC_CONTACT_CENTER.CALENDAR.TABS.holidays'),
  'TABS.exceptions': t('JRC_CONTACT_CENTER.CALENDAR.TABS.exceptions'),
  NAME: t('JRC_CONTACT_CENTER.CALENDAR.NAME'),
  DESCRIPTION: t('JRC_CONTACT_CENTER.CALENDAR.DESCRIPTION'),
  TIMEZONE: t('JRC_CONTACT_CENTER.CALENDAR.TIMEZONE'),
  PRECEDENCE: t('JRC_CONTACT_CENTER.CALENDAR.PRECEDENCE'),
  LOCAL_ONLY: t('JRC_CONTACT_CENTER.CALENDAR.LOCAL_ONLY'),
  HOURS_HELP: t('JRC_CONTACT_CENTER.CALENDAR.HOURS_HELP'),
  HOURS_EXAMPLE: t('JRC_CONTACT_CENTER.CALENDAR.HOURS_EXAMPLE'),
  'DAYS.1': t('JRC_CONTACT_CENTER.CALENDAR.DAYS.1'),
  'DAYS.2': t('JRC_CONTACT_CENTER.CALENDAR.DAYS.2'),
  'DAYS.3': t('JRC_CONTACT_CENTER.CALENDAR.DAYS.3'),
  'DAYS.4': t('JRC_CONTACT_CENTER.CALENDAR.DAYS.4'),
  'DAYS.5': t('JRC_CONTACT_CENTER.CALENDAR.DAYS.5'),
  'DAYS.6': t('JRC_CONTACT_CENTER.CALENDAR.DAYS.6'),
  'DAYS.7': t('JRC_CONTACT_CENTER.CALENDAR.DAYS.7'),
  EXPLICIT_DATES: t('JRC_CONTACT_CENTER.CALENDAR.EXPLICIT_DATES'),
  HOLIDAY_DATE: t('JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_DATE'),
  ADD_HOLIDAY: t('JRC_CONTACT_CENTER.CALENDAR.ADD_HOLIDAY'),
  DATE_NAME: t('JRC_CONTACT_CENTER.CALENDAR.DATE_NAME'),
  HOLIDAY_KIND: t('JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_KIND'),
  HOLIDAY_TYPE: t('JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_TYPE'),
  SELECT: t('JRC_CONTACT_CENTER.CALENDAR.SELECT'),
  'HOLIDAY_KINDS.national': t(
    'JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_KINDS.national'
  ),
  'HOLIDAY_KINDS.state': t('JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_KINDS.state'),
  'HOLIDAY_KINDS.municipal': t(
    'JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_KINDS.municipal'
  ),
  'HOLIDAY_KINDS.internal': t(
    'JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_KINDS.internal'
  ),
  'HOLIDAY_TYPES.fixed': t('JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_TYPES.fixed'),
  'HOLIDAY_TYPES.movable': t(
    'JRC_CONTACT_CENTER.CALENDAR.HOLIDAY_TYPES.movable'
  ),
  REMOVE_DATE: t('JRC_CONTACT_CENTER.CALENDAR.REMOVE_DATE'),
  EXCEPTION_HELP: t('JRC_CONTACT_CENTER.CALENDAR.EXCEPTION_HELP'),
  EXCEPTION_DATE: t('JRC_CONTACT_CENTER.CALENDAR.EXCEPTION_DATE'),
  ADD_EXCEPTION: t('JRC_CONTACT_CENTER.CALENDAR.ADD_EXCEPTION'),
  EXCEPTION_HOURS: t('JRC_CONTACT_CENTER.CALENDAR.EXCEPTION_HOURS'),
}));
const tr = key => labels.value[key];
const tabs = ['general', 'weekly', 'holidays', 'exceptions'];
const selected = ref('general');
const holidayDate = ref('');
const exceptionDate = ref('');
const set = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const setIntervals = (group, key, value) => {
  const schedule = calendarSchedule(props.modelValue);
  schedule.conditions[group][key] = value;
  emit('update:modelValue', updateCalendarSchedule(props.modelValue, schedule));
};
const patch = (group, index, values) =>
  set(
    group,
    props.modelValue[group].map((row, position) =>
      position === index ? { ...row, ...values } : row
    )
  );
const remove = (group, index) =>
  set(
    group,
    props.modelValue[group].filter((_row, position) => position !== index)
  );
const add = group => {
  const control = group === 'holidays' ? holidayDate : exceptionDate;
  if (
    !control.value ||
    props.modelValue[group].some(row => row.date === control.value)
  )
    return;
  const extra =
    group === 'holidays' ? { kind: '', type: '' } : { intervals: [] };
  set(group, [
    ...props.modelValue[group],
    { date: control.value, name: '', ...extra },
  ]);
  control.value = '';
};
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="min-w-0 space-y-3"
    data-calendar-definition-fields
  >
    <legend class="w-full">
      <div
        role="tablist"
        :aria-label="tr('DETAILS')"
        class="flex min-w-0 flex-wrap gap-2"
      >
        <button
          v-for="key in tabs"
          :id="`calendar-tab-${uid}-${key}`"
          :key="key"
          type="button"
          role="tab"
          :aria-selected="selected === key"
          :aria-controls="`calendar-panel-${uid}`"
          :data-calendar-tab="key"
          class="rounded-lg border px-3 py-2 text-sm"
          :class="
            selected === key
              ? 'border-n-blue-6 bg-n-blue-3 text-n-blue-11'
              : 'border-n-weak bg-n-solid-1 text-n-slate-12'
          "
          @click="selected = key"
        >
          {{ tr(`TABS.${key}`) }}
        </button>
      </div>
    </legend>
    <section
      :id="`calendar-panel-${uid}`"
      role="tabpanel"
      :aria-labelledby="`calendar-tab-${uid}-${selected}`"
      class="min-w-0 space-y-3"
    >
      <template v-if="selected === 'general'">
        <label class="grid gap-1 text-sm">
          <span>{{ tr('NAME') }}</span>
          <input
            :value="modelValue.name"
            maxlength="120"
            required
            data-calendar-name
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            @input="set('name', $event.target.value)"
          />
        </label>
        <label class="grid gap-1 text-sm">
          <span>{{ tr('DESCRIPTION') }}</span>
          <textarea
            :value="modelValue.description"
            maxlength="1000"
            rows="3"
            data-calendar-description
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            @input="set('description', $event.target.value)"
          />
        </label>
        <p
          class="break-words rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11"
          data-calendar-precedence
        >
          {{ tr('PRECEDENCE') }}
        </p>
        <p class="break-words text-sm">{{ tr('LOCAL_ONLY') }}</p>
      </template>
      <template v-else-if="selected === 'weekly'">
        <label class="grid gap-1 text-sm">
          <span>{{ tr('TIMEZONE') }}</span>
          <input
            :value="modelValue.timezone"
            required
            data-calendar-timezone
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            @input="set('timezone', $event.target.value)"
          />
        </label>
        <p class="text-xs text-n-slate-11">{{ tr('HOURS_HELP') }}</p>
        <CalendarHoursInput
          v-for="day in ['1', '2', '3', '4', '5', '6', '7']"
          :key="day"
          :model-value="modelValue.weekly[day]"
          :label="tr(`DAYS.${day}`)"
          :disabled="disabled"
          :data-calendar-weekday="day"
          @update:model-value="setIntervals('weekly', day, $event)"
        />
      </template>
      <template v-else-if="selected === 'holidays'">
        <p class="break-words text-xs text-n-slate-11">
          {{ tr('EXPLICIT_DATES') }}
        </p>
        <label class="grid gap-1 text-sm">
          <span>{{ tr('HOLIDAY_DATE') }}</span>
          <input
            v-model="holidayDate"
            type="date"
            data-calendar-holiday-date
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
        <button
          type="button"
          :disabled="
            !holidayDate ||
            modelValue.holidays.some(row => row.date === holidayDate)
          "
          data-add-calendar-holiday
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
          @click="add('holidays')"
        >
          {{ tr('ADD_HOLIDAY') }}
        </button>
        <section
          v-for="(row, index) in modelValue.holidays"
          :key="row.date"
          :data-calendar-holiday="row.date"
          class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        >
          <p>{{ row.date }}</p>
          <label class="grid gap-1 text-sm">
            <span>{{ tr('DATE_NAME') }}</span>
            <input
              :value="row.name"
              maxlength="120"
              required
              data-calendar-date-name
              class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              @input="patch('holidays', index, { name: $event.target.value })"
            />
          </label>
          <label class="grid gap-1 text-sm">
            <span>{{ tr('HOLIDAY_KIND') }}</span>
            <select
              :value="row.kind"
              required
              data-calendar-holiday-kind
              class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              @change="patch('holidays', index, { kind: $event.target.value })"
            >
              <option value="">{{ tr('SELECT') }}</option>
              <option
                v-for="kind in ['national', 'state', 'municipal', 'internal']"
                :key="kind"
                :value="kind"
              >
                {{ tr(`HOLIDAY_KINDS.${kind}`) }}
              </option>
            </select>
          </label>
          <label class="grid gap-1 text-sm">
            <span>{{ tr('HOLIDAY_TYPE') }}</span>
            <select
              :value="row.type"
              required
              data-calendar-holiday-type
              class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              @change="patch('holidays', index, { type: $event.target.value })"
            >
              <option value="">{{ tr('SELECT') }}</option>
              <option
                v-for="kind in ['fixed', 'movable']"
                :key="kind"
                :value="kind"
              >
                {{ tr(`HOLIDAY_TYPES.${kind}`) }}
              </option>
            </select>
          </label>
          <button
            type="button"
            data-remove-calendar-holiday
            class="rounded-lg px-3 py-2 text-sm text-n-ruby-11"
            @click="remove('holidays', index)"
          >
            {{ tr('REMOVE_DATE') }}
          </button>
        </section>
      </template>
      <template v-else>
        <p class="break-words text-xs text-n-slate-11">
          {{ tr('EXCEPTION_HELP') }}
        </p>
        <label class="grid gap-1 text-sm">
          <span>{{ tr('EXCEPTION_DATE') }}</span>
          <input
            v-model="exceptionDate"
            type="date"
            data-calendar-exception-date
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
        <button
          type="button"
          :disabled="
            !exceptionDate ||
            modelValue.exceptions.some(row => row.date === exceptionDate)
          "
          data-add-calendar-exception
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
          @click="add('exceptions')"
        >
          {{ tr('ADD_EXCEPTION') }}
        </button>
        <section
          v-for="(row, index) in modelValue.exceptions"
          :key="row.date"
          :data-calendar-exception="row.date"
          class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        >
          <p>{{ row.date }}</p>
          <label class="grid gap-1 text-sm">
            <span>{{ tr('DATE_NAME') }}</span>
            <input
              :value="row.name"
              maxlength="120"
              required
              data-calendar-date-name
              class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              @input="patch('exceptions', index, { name: $event.target.value })"
            />
          </label>
          <CalendarHoursInput
            :model-value="row.intervals"
            :label="tr('EXCEPTION_HOURS')"
            :disabled="disabled"
            @update:model-value="setIntervals('exceptions', row.date, $event)"
          />
          <button
            type="button"
            data-remove-calendar-exception
            class="rounded-lg px-3 py-2 text-sm text-n-ruby-11"
            @click="remove('exceptions', index)"
          >
            {{ tr('REMOVE_DATE') }}
          </button>
        </section>
      </template>
    </section>
  </fieldset>
</template>
