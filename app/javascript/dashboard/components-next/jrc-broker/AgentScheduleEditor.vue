<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { emptyWeek, validAgentSchedules } from './agentSchedules';

const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
  agents: { type: Array, default: () => [] },
  timezone: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue', 'removeObsoleteAgent']);
const { t, locale } = useI18n();
const selected = ref('');
const days = Array.from({ length: 7 }, (_, day) => String(day));
watch(
  () => props.agents,
  agents => {
    if (!agents.some(agent => String(agent.id) === selected.value))
      selected.value = String(agents[0]?.id || '');
  },
  { immediate: true }
);
const enabled = computed(() => Object.hasOwn(props.modelValue, selected.value));
const obsolete = computed(() =>
  Object.keys(props.modelValue).filter(
    id => !props.agents.some(agent => String(agent.id) === id)
  )
);
const week = computed(() => props.modelValue[selected.value] || emptyWeek());
const valid = computed(() => validAgentSchedules(props.modelValue));
const dayName = day =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    weekday: 'long',
    timeZone: 'UTC',
  }).format(new Date(Date.UTC(2026, 0, 4 + Number(day))));
const change = edit => {
  const next = JSON.parse(JSON.stringify(props.modelValue));
  edit(next);
  emit('update:modelValue', next);
};
const toggle = value =>
  change(next => {
    if (value) next[selected.value] = emptyWeek();
    else delete next[selected.value];
  });
const removeSchedule = id => {
  change(next => {
    delete next[id];
  });
  emit('removeObsoleteAgent', id);
};
const addPeriod = day =>
  change(next => {
    next[selected.value][day].push({ start: '09:00', end: '17:00' });
  });
const removePeriod = (day, index) =>
  change(next => {
    next[selected.value][day].splice(index, 1);
  });
const updatePeriod = (day, index, key, value) =>
  change(next => {
    const period = next[selected.value][day][index];
    period[key] = value;
    if (period.start === '00:00' && period.end === '00:00')
      period.end = '24:00';
  });
</script>

<template>
  <fieldset
    class="flex min-w-0 flex-col gap-3 rounded-xl border border-n-weak p-4"
  >
    <legend class="text-sm font-medium">
      {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.TITLE') }}
    </legend>
    <p class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.HELP', { timezone }) }}
    </p>
    <p v-if="!agents.length" class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.NO_AGENTS') }}
    </p>
    <template v-else>
      <label class="flex flex-col gap-1 text-sm">
        {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.AGENT') }}
        <select v-model="selected" data-testid="schedule-agent">
          <option
            v-for="agent in agents"
            :key="agent.id"
            :value="String(agent.id)"
          >
            {{ agent.name }}
          </option>
        </select>
      </label>
      <label class="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          data-testid="schedule-enabled"
          :checked="enabled"
          @change="toggle($event.target.checked)"
        />
        {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.ENABLED') }}
      </label>
      <p v-if="!enabled" class="text-sm text-n-slate-11">
        {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.INHERITED') }}
      </p>
      <template v-else>
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.PERIOD_HELP') }}
        </p>
        <fieldset
          v-for="day in days"
          :key="day"
          class="flex min-w-0 flex-col gap-2 border-t border-n-weak pt-2"
        >
          <legend class="text-sm font-medium">{{ dayName(day) }}</legend>
          <p v-if="!week[day].length" class="text-xs text-n-slate-11">
            {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.OFF') }}
          </p>
          <div
            v-for="(period, index) in week[day]"
            :key="index"
            class="flex flex-wrap items-end gap-2"
          >
            <label class="flex flex-col gap-1 text-xs">
              {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.START') }}
              <input
                type="time"
                :value="period.start"
                :data-period-start="`${day}-${index}`"
                :aria-label="
                  t('JRC_BROKER.DISTRIBUTION.SHIFTS.START_LABEL', {
                    day: dayName(day),
                    period: index + 1,
                  })
                "
                @input="updatePeriod(day, index, 'start', $event.target.value)"
              />
            </label>
            <label class="flex flex-col gap-1 text-xs">
              {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.END') }}
              <input
                type="time"
                :value="period.end === '24:00' ? '00:00' : period.end"
                :data-period-end="`${day}-${index}`"
                :aria-label="
                  t('JRC_BROKER.DISTRIBUTION.SHIFTS.END_LABEL', {
                    day: dayName(day),
                    period: index + 1,
                  })
                "
                @input="updatePeriod(day, index, 'end', $event.target.value)"
              />
            </label>
            <p
              v-if="period.end === '24:00' || period.end < period.start"
              class="text-xs text-n-slate-11"
            >
              {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.NEXT_DAY') }}
            </p>
            <button
              type="button"
              class="rounded border border-n-weak px-2 py-1 text-sm"
              :aria-label="
                t('JRC_BROKER.DISTRIBUTION.SHIFTS.REMOVE_LABEL', {
                  day: dayName(day),
                  period: index + 1,
                })
              "
              @click="removePeriod(day, index)"
            >
              {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.REMOVE') }}
            </button>
          </div>
          <button
            type="button"
            class="self-start rounded border border-n-weak px-2 py-1 text-sm"
            :data-add-period-day="day"
            :disabled="week[day].length >= 4"
            :aria-label="
              t('JRC_BROKER.DISTRIBUTION.SHIFTS.ADD_LABEL', {
                day: dayName(day),
              })
            "
            @click="addPeriod(day)"
          >
            {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.ADD') }}
          </button>
        </fieldset>
      </template>
    </template>
    <div
      v-for="id in obsolete"
      :key="id"
      class="flex flex-wrap items-center gap-2 rounded border border-n-weak p-2"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.OBSOLETE', { id }) }}
      </p>
      <button
        type="button"
        class="rounded border border-n-weak px-2 py-1 text-sm"
        :data-remove-schedule-id="id"
        @click="removeSchedule(id)"
      >
        {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.REMOVE_SCHEDULE') }}
      </button>
    </div>
    <p v-if="!valid" role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_BROKER.DISTRIBUTION.SHIFTS.INVALID') }}
    </p>
  </fieldset>
</template>
