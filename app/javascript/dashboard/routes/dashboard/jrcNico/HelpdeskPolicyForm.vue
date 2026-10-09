<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { buildHelpdeskLabels } from './helpdeskLabels';
import { helpdeskGroupDefaults, HELPDESK_GROUPS } from './helpdeskPresentation';

const props = defineProps({
  definition: { type: Object, required: true },
  options: {
    type: Object,
    default: () => ({
      units: [],
      companies: [],
      operators: [],
      priorities: [],
    }),
  },
  busy: Boolean,
});
const emit = defineEmits(['save']);
const { t } = useI18n();
const label = computed(() => buildHelpdeskLabels(t));

const model = ref({});
const advanced = ref('');
const advancedError = ref(false);
watch(
  () => props.definition,
  value => {
    model.value = JSON.parse(JSON.stringify(value));
    model.value.rules.R12.priority_ids ||= {};
    model.value.groups = helpdeskGroupDefaults(value.groups);
    advanced.value = JSON.stringify(value, null, 2);
  },
  { immediate: true }
);
const numericFields = rule =>
  Object.keys(rule).filter(key => typeof rule[key] === 'number');
const priorities = unitId =>
  (props.options.priorities || []).filter(item => item.unit_id === unitId);
const priorityName = id =>
  props.options.priorities.find(item => item.id === id)?.name || id;
function setOrder(unitId) {
  model.value.priority_order[String(unitId)] = priorities(unitId).map(
    item => item.id
  );
}
function move(unitId, index, offset) {
  const order = model.value.priority_order[String(unitId)];
  const target = index + offset;
  if (target < 0 || target >= order.length) return;
  [order[index], order[target]] = [order[target], order[index]];
}
function applyAdvanced() {
  try {
    const parsed = JSON.parse(advanced.value);
    if (
      !['unit_ids', 'company_ids', 'operator_ids'].every(key =>
        Array.isArray(parsed[key])
      ) ||
      !parsed.roles ||
      !parsed.priority_order ||
      !parsed.daily ||
      !Array.isArray(parsed.daily.channels) ||
      !Array.isArray(parsed.roles.thiago) ||
      !parsed.rules?.R12?.priority_ids ||
      Array.isArray(parsed.rules.R12.priority_ids) ||
      Object.keys(parsed.rules || {}).length !== 16 ||
      !Object.values(parsed.rules).every(
        rule => Array.isArray(rule.recipients) && Array.isArray(rule.channels)
      )
    )
      throw new Error();
    model.value = parsed;
    model.value.groups = helpdeskGroupDefaults(parsed.groups);
    advancedError.value = false;
  } catch {
    advancedError.value = true;
  }
}
function save() {
  const value = JSON.parse(JSON.stringify(model.value));
  value.priority_order = Object.fromEntries(
    Object.entries(value.priority_order).filter(([id]) =>
      value.unit_ids.includes(Number(id))
    )
  );
  value.rules.R12.priority_ids = Object.fromEntries(
    Object.entries(value.rules.R12.priority_ids).filter(
      ([id, priorityId]) =>
        value.unit_ids.includes(Number(id)) && Number.isSafeInteger(priorityId)
    )
  );
  emit('save', value);
}
</script>

<template>
  <form class="space-y-5" @submit.prevent="save">
    <fieldset class="grid gap-4 md:grid-cols-3">
      <legend class="mb-3 font-semibold">
        {{ $t('JRC_NICO_HELPDESK.PILOT') }}
      </legend>
      <label class="text-sm">
        {{ $t('JRC_NICO_HELPDESK.UNITS') }}
        <select
          v-model="model.unit_ids"
          multiple
          class="mt-2 block min-h-28 w-full rounded-lg border border-n-weak bg-n-background p-2"
        >
          <option v-for="unit in options.units" :key="unit.id" :value="unit.id">
            {{ unit.name }}
          </option>
        </select>
      </label>
      <label class="text-sm">
        {{ $t('JRC_NICO_HELPDESK.COMPANIES') }}
        <select
          v-model="model.company_ids"
          multiple
          class="mt-2 block min-h-28 w-full rounded-lg border border-n-weak bg-n-background p-2"
        >
          <option
            v-for="company in options.companies"
            :key="company.id"
            :value="company.id"
          >
            {{ company.name }}
          </option>
        </select>
      </label>
      <label class="text-sm">
        {{ $t('JRC_NICO_HELPDESK.OPERATORS') }}
        <select
          v-model="model.operator_ids"
          multiple
          class="mt-2 block min-h-28 w-full rounded-lg border border-n-weak bg-n-background p-2"
        >
          <option
            v-for="operator in options.operators"
            :key="operator.id"
            :value="operator.id"
          >
            {{ operator.name }}
          </option>
        </select>
      </label>
    </fieldset>
    <p class="text-xs text-n-slate-11">
      {{ $t('JRC_NICO_HELPDESK.EMPTY_SCOPE') }}
    </p>
    <div class="grid gap-4 md:grid-cols-2">
      <label class="text-sm">
        {{ $t('JRC_NICO_HELPDESK.HOURLY_LIMIT') }}
        <input
          v-model.number="model.hourly_limit"
          type="number"
          min="1"
          max="1000"
          required
          class="mt-2 block w-full rounded-lg border border-n-weak bg-n-background p-2"
        />
      </label>
      <label class="text-sm">
        {{ $t('JRC_NICO_HELPDESK.APPROVAL_TTL') }}
        <input
          v-model.number="model.approval_ttl_seconds"
          type="number"
          min="30"
          max="900"
          required
          class="mt-2 block w-full rounded-lg border border-n-weak bg-n-background p-2"
        />
      </label>
    </div>
    <details class="rounded-lg border border-n-weak p-3">
      <summary class="cursor-pointer font-medium">
        {{ $t('JRC_NICO_HELPDESK.PRIORITY_ORDER') }}
      </summary>
      <div
        v-for="unit in options.units.filter(item =>
          model.unit_ids.includes(item.id)
        )"
        :key="unit.id"
        class="mt-4"
      >
        <h3 class="font-medium">
          {{ unit.name }}
        </h3>
        <button
          type="button"
          class="mt-2 rounded border border-n-weak px-3 py-1 text-sm"
          @click="setOrder(unit.id)"
        >
          {{ $t('JRC_NICO_HELPDESK.SET_ORDER') }}
        </button>
        <ol class="mt-2 list-inside list-decimal">
          <li
            v-for="(id, index) in model.priority_order[String(unit.id)] || []"
            :key="id"
            class="mb-2"
          >
            {{ priorityName(id) }}
            <button
              type="button"
              :disabled="index === 0"
              class="ml-3 rounded border border-n-weak px-2 disabled:opacity-40"
              @click="move(unit.id, index, -1)"
            >
              {{ $t('JRC_NICO_HELPDESK.UP') }}
            </button>
            <button
              type="button"
              :disabled="
                index === model.priority_order[String(unit.id)].length - 1
              "
              class="ml-2 rounded border border-n-weak px-2 disabled:opacity-40"
              @click="move(unit.id, index, 1)"
            >
              {{ $t('JRC_NICO_HELPDESK.DOWN') }}
            </button>
          </li>
        </ol>
      </div>
    </details>
    <details class="rounded-lg border border-n-weak p-3">
      <summary class="cursor-pointer font-medium">
        {{ $t('JRC_NICO_HELPDESK.ROLE_RECIPIENTS') }}
      </summary>
      <div class="mt-3 grid gap-4 md:grid-cols-4">
        <label v-for="(_, role) in model.roles" :key="role" class="text-sm">
          <span>
            {{ label('roles', role) }}
          </span>
          <select
            v-model="model.roles[role]"
            multiple
            class="mt-2 block min-h-20 w-full rounded border border-n-weak bg-n-background p-2"
          >
            <option
              v-for="operator in options.operators"
              :key="operator.id"
              :value="operator.id"
            >
              {{ operator.name }}
            </option>
          </select>
        </label>
      </div>
    </details>
    <fieldset>
      <legend class="mb-3 font-semibold">
        {{ $t('JRC_NICO_HELPDESK.GROUP_POLICY') }}
      </legend>
      <p class="mb-3 text-xs text-n-slate-11">
        {{ $t('JRC_NICO_HELPDESK.GROUP_DEFAULT_OFF') }}
      </p>
      <div class="grid gap-3 sm:grid-cols-3">
        <label
          v-for="key in HELPDESK_GROUPS"
          :key="key"
          class="flex items-center gap-2 rounded border border-n-weak p-3"
        >
          <input
            v-model="model.groups[key].enabled"
            type="checkbox"
            :data-group-policy="key"
          />{{ key }}
        </label>
      </div>
    </fieldset>
    <fieldset>
      <legend class="mb-3 font-semibold">
        {{ $t('JRC_NICO_HELPDESK.RULES') }}
      </legend>
      <div class="grid gap-3 lg:grid-cols-2">
        <article
          v-for="(rule, key) in model.rules"
          :key="key"
          class="rounded-lg border border-n-weak p-4"
        >
          <label class="flex items-center gap-3 font-medium">
            <input
              v-model="rule.enabled"
              type="checkbox"
              :disabled="rule.confirmed === false"
            />
            {{ key }} {{ label('rules', key) }}
          </label>
          <div
            v-if="Object.hasOwn(rule, 'confirmed')"
            class="mt-3 rounded bg-n-amber-2 p-3 text-sm"
          >
            <p>
              {{ label('conflicts', key) }}
            </p>
            <label class="mt-2 flex items-center gap-2">
              <input
                v-model="rule.confirmed"
                type="checkbox"
                @change="rule.enabled = false"
              />
              {{ $t('JRC_NICO_HELPDESK.CONFIRM_BASIS') }}
            </label>
          </div>
          <div class="mt-3 grid gap-3 sm:grid-cols-2">
            <label
              v-for="field in numericFields(rule)"
              :key="field"
              class="text-xs"
            >
              {{ label('fields', field) }}
              <input
                v-model.number="rule[field]"
                type="number"
                min="1"
                max="365"
                class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
              />
            </label>
            <label v-if="rule.basis" class="text-xs">
              <span>
                {{ $t('JRC_NICO_HELPDESK.TIME_BASIS') }}
              </span>
              <select
                v-model="rule.basis"
                class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
              >
                <option value="calendar">
                  {{ $t('JRC_NICO_HELPDESK.CALENDAR') }}
                </option>
                <option value="business">
                  {{ $t('JRC_NICO_HELPDESK.BUSINESS') }}
                </option>
              </select>
            </label>
            <label v-if="key === 'R12'" class="text-xs">
              <span>
                {{ $t('JRC_NICO_HELPDESK.CRITICAL_COMPANIES') }}
              </span>
              <select
                v-model="rule.critical_company_ids"
                multiple
                class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
              >
                <option
                  v-for="company in options.companies.filter(item =>
                    model.company_ids.includes(item.id)
                  )"
                  :key="company.id"
                  :value="company.id"
                >
                  {{ company.name }}
                </option>
              </select>
            </label>
          </div>
          <div v-if="key === 'R12'" class="mt-3 grid gap-3 sm:grid-cols-2">
            <label
              v-for="unit in options.units.filter(item =>
                model.unit_ids.includes(item.id)
              )"
              :key="unit.id"
              class="text-xs"
            >
              <span>
                {{ $t('JRC_NICO_HELPDESK.CRITICAL_PRIORITY_TARGET') }}
                {{ unit.name }}
              </span>
              <select
                v-model="rule.priority_ids[String(unit.id)]"
                :required="rule.enabled"
                :data-priority-unit="unit.id"
                class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
              >
                <option :value="undefined" disabled>
                  {{ $t('JRC_NICO_HELPDESK.EMPTY') }}
                </option>
                <option
                  v-for="priority in priorities(unit.id)"
                  :key="priority.id"
                  :value="priority.id"
                >
                  {{ priority.name }} {{ priority.id }}
                </option>
              </select>
            </label>
          </div>
          <div v-if="key === 'R13'" class="mt-3 grid grid-cols-3 gap-2">
            <label v-for="(_, index) in rule.days" :key="index" class="text-xs">
              <span>
                {{
                  $t('JRC_NICO_HELPDESK.INACTIVITY_LEVEL', { level: index + 1 })
                }}
              </span>
              <input
                v-model.number="rule.days[index]"
                type="number"
                min="1"
                max="365"
                class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
              />
            </label>
          </div>
          <label class="mt-3 block text-xs">
            {{ $t('JRC_NICO_HELPDESK.RECIPIENTS') }}
            <select
              v-model="rule.recipients"
              multiple
              class="mt-1 block min-h-20 w-full rounded border border-n-weak bg-n-background p-2"
            >
              <option
                v-for="operator in options.operators"
                :key="operator.id"
                :value="operator.id"
              >
                {{ operator.name }}
              </option>
            </select>
          </label>
          <div class="mt-3 flex flex-wrap gap-3 text-xs">
            <label
              v-for="channel in ['nico', 'email', 'whatsapp']"
              :key="channel"
              class="flex items-center gap-2"
            >
              <input v-model="rule.channels" type="checkbox" :value="channel" />
              {{ label('channels', channel) }}
            </label>
          </div>
        </article>
      </div>
    </fieldset>
    <fieldset class="rounded-lg border border-n-weak p-4">
      <legend class="font-semibold">
        {{ $t('JRC_NICO_HELPDESK.DAILY_CONFIGURATION') }}
      </legend>
      <label class="flex gap-2 text-sm">
        <input v-model="model.daily.enabled" type="checkbox" />
        {{ $t('JRC_NICO_HELPDESK.DAILY_ENABLED') }}
      </label>
      <div class="mt-3 grid gap-3 md:grid-cols-2">
        <label class="text-sm">
          {{ $t('JRC_NICO_HELPDESK.TIMEZONE') }}
          <input
            v-model="model.daily.timezone"
            type="text"
            required
            class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          />
        </label>
        <label class="text-sm">
          {{ $t('JRC_NICO_HELPDESK.RECIPIENTS') }}
          <select
            v-model="model.daily.recipients"
            multiple
            class="mt-1 block min-h-20 w-full rounded border border-n-weak bg-n-background p-2"
          >
            <option
              v-for="operator in options.operators.filter(item =>
                model.roles.thiago.includes(item.id)
              )"
              :key="operator.id"
              :value="operator.id"
            >
              {{ operator.name }}
            </option>
          </select>
        </label>
      </div>
      <div class="mt-3 flex gap-3 text-sm">
        <label
          v-for="channel in ['nico', 'email', 'whatsapp']"
          :key="channel"
          class="flex gap-2"
        >
          <input
            v-model="model.daily.channels"
            type="checkbox"
            :value="channel"
          />
          {{ label('channels', channel) }}
        </label>
      </div>
    </fieldset>
    <p class="text-sm text-n-amber-11">
      {{ $t('JRC_NICO_HELPDESK.EXTERNAL_CHANNELS_BLOCKED') }}
    </p>
    <details class="rounded-lg border border-n-weak p-3">
      <summary class="cursor-pointer">
        {{ $t('JRC_NICO_HELPDESK.ADVANCED') }}
      </summary>
      <textarea
        v-model="advanced"
        rows="10"
        :aria-label="$t('JRC_NICO_HELPDESK.DEFINITION')"
        class="mt-3 w-full rounded border border-n-weak bg-n-background p-2 font-mono text-xs"
      />
      <button
        type="button"
        class="mt-2 rounded border border-n-weak px-3 py-1"
        @click="applyAdvanced"
      >
        {{ $t('JRC_NICO_HELPDESK.APPLY_ADVANCED') }}
      </button>
      <p v-if="advancedError" class="mt-2 text-n-ruby-9">
        {{ $t('JRC_NICO_HELPDESK.ERROR') }}
      </p>
    </details>
    <button
      :disabled="busy"
      type="submit"
      class="rounded-lg bg-n-brand px-4 py-2 text-white disabled:opacity-50"
    >
      {{ $t('JRC_NICO_HELPDESK.SAVE_DRAFT') }}
    </button>
  </form>
</template>
