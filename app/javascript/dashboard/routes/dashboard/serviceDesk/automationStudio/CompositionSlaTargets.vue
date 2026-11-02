<script setup>
import { computed } from 'vue';
import LookupSelect from '../components/LookupSelect.vue';
import CalendarFields from './CalendarFields.vue';
import LifecycleVisualEditor from '../components/LifecycleVisualEditor.vue';
import ClockThresholdEditor from '../components/ClockThresholdEditor.vue';
import { useCompositionCopy, fieldClass, buttonClass } from './compositionCopy';
defineProps({ unitId: { type: String, required: true }, disabled: Boolean });
const model = defineModel({ type: Object, required: true });
const calendar = defineModel('calendar', { type: Object, required: true });
const calendarCode = defineModel('calendarCode', { type: String, default: '' });
const calendarVersion = defineModel('calendarVersion', {
  type: String,
  default: '',
});
const tr = useCompositionCopy();
const lifecycleText = computed({
  get: () => JSON.stringify(model.value.lifecycle),
  set: value => {
    model.value.lifecycle = JSON.parse(value);
  },
});
const rows = computed(() => model.value.families.sla_selection?.rules || []);
const clocks = computed(() =>
  model.value.lifecycle?.schema_version === 2
    ? ['first_response', 'attendance', 'resolution']
    : ['first_response', 'resolution']
);
function add() {
  model.value.families.sla_selection ||= { rules: [] };
  model.value.families.sla_selection.rules.push({
    key: crypto.randomUUID(),
    precedence: null,
    match: { priority_id: null },
    output: { snapshot: { policy_conditions: { clock_budgets_seconds: {} } } },
  });
}
function budget(row, clock, input) {
  row.output.snapshot.policy_conditions.clock_budgets_seconds[clock] = input
    ? Number(input) * 60
    : null;
}
</script>

<template>
  <div class="grid gap-4">
    <article class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
      <h3 class="text-base font-semibold">{{ tr('external_sla') }}</h3>
      <p class="mt-1 text-xs">{{ tr('external_sla_help') }}</p>
    </article>
    <LifecycleVisualEditor
      v-model="lifecycleText"
      :unit-id="unitId"
      :disabled="disabled"
      section="monitoring"
    />
    <section
      v-if="model.lifecycle?.sla.mode === 'calendar_snapshot'"
      class="grid gap-4"
    >
      <header class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="font-semibold">{{ tr('targets_priority') }}</h3>
        <button
          type="button"
          :class="buttonClass"
          :disabled="disabled || rows.length >= 100"
          @click="add"
        >
          {{ tr('add_target') }}
        </button>
      </header>
      <div class="overflow-x-auto rounded-xl border border-n-weak">
        <table class="w-full min-w-[600px] text-left text-sm">
          <thead class="bg-n-blue-2">
            <tr>
              <th class="p-3">{{ tr('fields.priority_id') }}</th>
              <th class="p-3">{{ tr('precedence') }}</th>
              <th
                v-for="clock in clocks"
                :key="clock"
                class="p-3"
              >
                {{ tr(`clocks.${clock}`) }}
              </th>
              <th class="p-3">{{ tr('state') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="row.key"
              class="border-t border-n-weak"
            >
              <td class="p-3">
                <LookupSelect
                  :model-value="String(row.match.priority_id || '')"
                  resource="priorities"
                  :unit-id="unitId"
                  :label="tr('fields.priority_id')"
                  :disabled="disabled"
                  @update:model-value="
                    row.match.priority_id = $event ? Number($event) : null
                  "
                />
              </td>
              <td class="p-3">
                <input
                  v-model.number="row.precedence"
                  type="number"
                  min="1"
                  :class="fieldClass"
                  :aria-label="tr('precedence')"
                />
              </td>
              <td
                v-for="clock in clocks"
                :key="clock"
                class="p-3"
              >
                <input
                  type="number"
                  min="1"
                  :class="fieldClass"
                  :aria-label="tr(`clocks.${clock}`)"
                  :value="
                    row.output.snapshot.policy_conditions.clock_budgets_seconds[
                      clock
                    ] / 60 || ''
                  "
                  @input="budget(row, clock, $event.target.value)"
                />
              </td>
              <td class="p-3">
                <label class="flex items-center gap-2 text-xs">
                  <input
                    type="checkbox"
                    :checked="row.enabled !== false"
                    :disabled="disabled"
                    @change="row.enabled = $event.target.checked"
                  />
                  {{ tr('include_target') }}
                </label>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p
        v-if="!rows.length"
        class="rounded-lg bg-n-amber-2 p-3 text-xs text-n-amber-11"
      >
        {{ tr('no_targets') }}
      </p>
      <article
        class="rounded-xl border border-n-amber-5 bg-n-amber-2 p-4 text-xs"
      >
        {{ tr('attendance_help') }}
      </article>
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="grid gap-1 text-sm">
          {{ tr('calendar_code') }}
          <input
            v-model="calendarCode"
            :class="fieldClass"
            :disabled="disabled"
          />
        </label>
        <label class="grid gap-1 text-sm">
          {{ tr('calendar_version') }}
          <input
            v-model="calendarVersion"
            :class="fieldClass"
            :disabled="disabled"
          />
        </label>
      </div>
      <CalendarFields
        v-model="calendar"
        :disabled="disabled"
      />
      <ClockThresholdEditor
        v-if="model.lifecycle.schema_version === 2"
        v-model="model.lifecycle.sla.escalation_policy"
        :unit-id="unitId"
        :disabled="disabled"
      />
    </section>
  </div>
</template>
