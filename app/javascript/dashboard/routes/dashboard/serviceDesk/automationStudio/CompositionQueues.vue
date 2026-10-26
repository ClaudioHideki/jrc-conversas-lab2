<script setup>
import { computed, ref } from 'vue';
import Configuration from 'dashboard/api/serviceDeskConfiguration';
import LookupSelect from '../components/LookupSelect.vue';
import CalendarFields from './CalendarFields.vue';
import ClockThresholdEditor from '../components/ClockThresholdEditor.vue';
import OlaMonitoring from './OlaMonitoring.vue';
import { clone } from './compositionForm';
import { useCompositionCopy, fieldClass, buttonClass } from './compositionCopy';
const props = defineProps({
  accountId: { type: String, required: true },
  unitId: { type: String, required: true },
  disabled: Boolean,
});
const model = defineModel({ type: Array, required: true });
const tr = useCompositionCopy();
const selected = ref('');
const loading = ref(false);
const failed = ref(false);
const names = ref({});
const modes = ['manual', 'round_robin', 'least_load', 'skill', 'priority_sla'];
const selectedIds = computed(() => model.value.map(row => String(row.id)));
async function include() {
  if (
    !selected.value ||
    selectedIds.value.includes(selected.value) ||
    loading.value
  )
    return;
  const identity = `${props.accountId}:${props.unitId}`;
  loading.value = true;
  failed.value = false;
  try {
    const response = await Configuration.record(
      props.accountId,
      'queues',
      selected.value
    );
    if (identity !== `${props.accountId}:${props.unitId}`) return;
    const row = response.record;
    if (response.account_id !== props.accountId || row.unit_id !== props.unitId)
      throw new TypeError('Invalid queue scope');
    names.value[row.id] = row.name;
    const fields = [
      'team_id',
      'distribution_mode',
      'required_skills',
      'ola_targets',
      'ola_calendar',
      'ola_time_basis',
      'ola_pause_waiting',
      'ola_escalation_policy',
    ];
    model.value.push({
      id: Number(row.id),
      attributes: Object.fromEntries(fields.map(key => [key, clone(row[key])])),
    });
    selected.value = '';
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
}
function budget(row, clock, input) {
  const values = { ...row.attributes.ola_targets };
  if (input) values[clock] = Number(input) * 60;
  else delete values[clock];
  row.attributes.ola_targets = values;
}
</script>

<template>
  <fieldset
    :disabled="disabled || loading"
    class="grid gap-4"
  >
    <article class="rounded-xl border border-n-teal-5 bg-n-teal-2 p-4">
      <h3 class="font-semibold">{{ tr('internal_ola') }}</h3>
      <p class="mt-1 text-xs">{{ tr('internal_ola_help') }}</p>
    </article>
    <div class="grid items-end gap-3 sm:grid-cols-[1fr_auto]">
      <LookupSelect
        v-model="selected"
        resource="queues"
        :unit-id="unitId"
        :label="tr('choose_queue')"
        :disabled="disabled || loading"
      />
      <button
        type="button"
        :class="buttonClass"
        :disabled="!selected || loading || selectedIds.includes(selected)"
        @click="include"
      >
        {{ tr('include_queue') }}
      </button>
    </div>
    <p
      v-if="failed"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ tr('load_failed') }}
    </p>
    <p
      v-if="!model.length"
      class="rounded-xl border border-dashed border-n-weak p-5 text-sm text-n-slate-11"
    >
      {{ tr('queues_unchanged') }}
    </p>
    <article
      v-for="row in model"
      :key="row.id"
      class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <header class="flex items-center justify-between gap-3">
        <h3 class="font-semibold">
          {{ names[row.id] || tr('queue_reference', { id: row.id }) }}
        </h3>
        <span class="rounded-full bg-n-teal-2 px-3 py-1 text-xs text-n-teal-11">
          {{ tr('native_ola') }}
        </span>
      </header>
      <div class="grid gap-4 sm:grid-cols-2">
        <LookupSelect
          :model-value="String(row.attributes.team_id || '')"
          resource="teams"
          :unit-id="unitId"
          :label="tr('team')"
          :disabled="disabled"
          @update:model-value="
            row.attributes.team_id = $event ? Number($event) : null
          "
        />
        <label class="grid gap-1 text-sm">
          {{ tr('distribution') }}
          <select
            v-model="row.attributes.distribution_mode"
            :class="fieldClass"
          >
            <option
              v-for="mode in modes"
              :key="mode"
              :value="mode"
            >
              {{ tr(`modes.${mode}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-sm">
          {{ tr('skills') }}
          <input
            :value="row.attributes.required_skills.join(', ')"
            :class="fieldClass"
            @change="
              row.attributes.required_skills = $event.target.value
                .split(',')
                .map(s => s.trim())
                .filter(Boolean)
            "
          />
        </label>
        <label class="grid gap-1 text-sm">
          {{ tr('time_basis') }}
          <select
            v-model="row.attributes.ola_time_basis"
            :class="fieldClass"
          >
            <option value="">{{ tr('choose') }}</option>
            <option value="calendar">{{ tr('calendar_time') }}</option>
            <option value="business">{{ tr('business_time') }}</option>
          </select>
        </label>
      </div>
      <div class="grid gap-3 sm:grid-cols-3">
        <label
          v-for="clock in ['first_response', 'update', 'resolution']"
          :key="clock"
          class="grid gap-1 text-sm"
        >
          {{ tr(`clocks.${clock}`) }}
          <input
            type="number"
            min="1"
            :class="fieldClass"
            :value="row.attributes.ola_targets[clock] / 60 || ''"
            @input="budget(row, clock, $event.target.value)"
          />
        </label>
      </div>
      <label class="flex items-center gap-2 text-sm">
        <input
          v-model="row.attributes.ola_pause_waiting"
          type="checkbox"
        />
        {{ tr('pause_ola_waiting') }}
      </label>
      <CalendarFields
        v-if="row.attributes.ola_time_basis === 'business'"
        v-model="row.attributes.ola_calendar"
        :disabled="disabled"
      />
      <ClockThresholdEditor
        v-model="row.attributes.ola_escalation_policy"
        :unit-id="unitId"
        :disabled="disabled"
      />
      <p class="rounded-lg bg-n-amber-2 p-3 text-xs text-n-amber-11">
        {{ tr('shared_queue_help') }}
      </p>
      <details class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
        <summary class="cursor-pointer text-sm font-semibold">
          {{ tr('passage_title') }}
        </summary>
        <OlaMonitoring
          :account-id="accountId"
          :unit-id="unitId"
          :queue-id="String(row.id)"
        />
      </details>
    </article>
    <article class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4 text-xs">
      <strong>{{ tr('passage_title') }}</strong>
      <p class="mt-2">{{ tr('passage_help') }}</p>
      <p class="mt-2">{{ tr('capacity_help') }}</p>
    </article>
  </fieldset>
</template>
