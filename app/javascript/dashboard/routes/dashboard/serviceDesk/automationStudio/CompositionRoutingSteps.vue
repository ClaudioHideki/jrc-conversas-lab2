<script setup>
import { computed, ref } from 'vue';
import LookupSelect from '../components/LookupSelect.vue';
import ServiceSelect from '../components/ServiceDefinitionSelect.vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import CompositionQueues from './CompositionQueues.vue';
import CompositionNotifications from './CompositionNotifications.vue';
import CalendarFields from './CalendarFields.vue';
import { emptyCalendar, emptyRule } from './compositionForm';
import { useCompositionCopy, fieldClass, buttonClass } from './compositionCopy';
defineProps({
  section: { type: String, required: true },
  unitId: { type: String, required: true },
  accountId: { type: String, required: true },
  disabled: Boolean,
  options: { type: Object, required: true },
});
const model = defineModel({ type: Object, required: true });
const tr = useCompositionCopy();
const rule = computed(() => model.value.definition.families.routing.rules[0]);
const matrix = computed(
  () => model.value.definition.families.priority_matrix?.rules || []
);
const classification = computed(() => rule.value.output.classification || {});
const company = ref(null);
const contract = ref('');
const selectedLabel = ref('');
function classify(field, value) {
  const values = { ...classification.value };
  if (value) values[field] = Number(value);
  else delete values[field];
  if (Object.keys(values).length) rule.value.output.classification = values;
  else delete rule.value.output.classification;
}
function assignmentMode(value) {
  rule.value.output.assignment = {
    mode: value,
    ...(rule.value.output.assignment?.fallback_queue_id
      ? { fallback_queue_id: rule.value.output.assignment.fallback_queue_id }
      : {}),
  };
}
function addMatrix() {
  model.value.definition.families.priority_matrix ||= { rules: [] };
  const row = emptyRule();
  row.match = { impact: '', urgency: '' };
  delete row.conditions;
  row.output = { priority_id: null };
  model.value.definition.families.priority_matrix.rules.push(row);
}
function windowEnabled(value) {
  if (value) rule.value.window = emptyCalendar();
  else delete rule.value.window;
}
function exceptions() {
  rule.value.exceptions ||= {
    company_ids: [],
    contract_ids: [],
    skip_assigned: false,
  };
  return rule.value.exceptions;
}
function addException(field, value) {
  if (value) {
    const data = exceptions();
    data[field] = [...new Set([...data[field], Number(value)])];
  }
  company.value = null;
  contract.value = '';
}
function label() {
  if (selectedLabel.value)
    rule.value.output.label_ids = [
      ...new Set([
        ...(rule.value.output.label_ids || []),
        Number(selectedLabel.value),
      ]),
    ];
  selectedLabel.value = '';
}
function validity(key, value) {
  if (value) rule.value[key] = new Date(value).toISOString();
  else delete rule.value[key];
}
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="grid gap-4"
  >
    <template v-if="section === 'destination'">
      <div class="grid gap-4 xl:grid-cols-2">
        <article
          class="grid content-start gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
        >
          <h3 class="font-semibold">{{ tr('destination_title') }}</h3>
          <p class="text-xs">{{ tr('destination_help') }}</p>
          <LookupSelect
            :model-value="String(rule.output.queue_id || '')"
            resource="queues"
            :unit-id="unitId"
            :label="tr('choose_queue')"
            :disabled="disabled"
            @update:model-value="
              rule.output.queue_id = $event ? Number($event) : null
            "
          />
          <label class="grid gap-1 text-sm">
            {{ tr('assignment') }}
            <select
              :value="rule.output.assignment?.mode || 'queue'"
              :class="fieldClass"
              @change="assignmentMode($event.target.value)"
            >
              <option value="queue">{{ tr('assignment_queue') }}</option>
              <option value="fixed">{{ tr('assignment_fixed') }}</option>
              <option value="hybrid">{{ tr('assignment_hybrid') }}</option>
            </select>
          </label>
          <LookupSelect
            v-if="['fixed', 'hybrid'].includes(rule.output.assignment?.mode)"
            :model-value="String(rule.output.assignment.account_user_id || '')"
            resource="assignees"
            :unit-id="unitId"
            :label="tr('fixed_assignee')"
            :disabled="disabled"
            @update:model-value="
              rule.output.assignment.account_user_id = $event
                ? Number($event)
                : null
            "
          />
          <p class="rounded-lg bg-n-solid-1 p-3 text-xs">
            {{ tr('capacity_help') }}
          </p>
        </article>
        <article
          class="grid content-start gap-4 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
        >
          <h3 class="font-semibold">{{ tr('additional_actions') }}</h3>
          <div class="grid gap-2">
            <label class="grid gap-1 text-sm">
              {{ tr('labels_ticket') }}
              <select
                v-model="selectedLabel"
                :class="fieldClass"
              >
                <option value="">{{ tr('choose') }}</option>
                <option
                  v-for="item in options.labels"
                  :key="item.id"
                  :value="String(item.id)"
                >
                  {{ item.name }}
                </option>
              </select>
            </label>
            <button
              type="button"
              :class="buttonClass"
              :disabled="!selectedLabel"
              @click="label"
            >
              {{ tr('add_label') }}
            </button>
            <button
              v-for="id in rule.output.label_ids || []"
              :key="id"
              type="button"
              :class="buttonClass"
              @click="
                rule.output.label_ids = rule.output.label_ids.filter(
                  value => value !== id
                )
              "
            >
              {{ options.labels.find(item => item.id === id)?.name || id }} ·
              {{ tr('remove') }}
            </button>
          </div>
          <label class="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              :checked="!!rule.output.task"
              @change="
                $event.target.checked
                  ? (rule.output.task = { title: '', description: '' })
                  : delete rule.output.task
              "
            />
            {{ tr('create_internal_task') }}
          </label>
          <template v-if="rule.output.task">
            <label class="grid gap-1 text-sm">
              {{ tr('task_title') }}
              <input
                v-model="rule.output.task.title"
                :class="fieldClass"
                maxlength="255"
              />
            </label>
            <label class="grid gap-1 text-sm">
              {{ tr('description') }}
              <textarea
                v-model="rule.output.task.description"
                :class="fieldClass"
                rows="3"
                maxlength="4000"
              />
            </label>
          </template>
          <label class="grid gap-1 text-sm">
            {{ tr('internal_note') }}
            <textarea
              :value="rule.output.internal_note || ''"
              :class="fieldClass"
              rows="3"
              maxlength="4000"
              @input="
                $event.target.value
                  ? (rule.output.internal_note = $event.target.value)
                  : delete rule.output.internal_note
              "
            />
          </label>
        </article>
      </div>
      <details class="rounded-xl border border-n-weak p-4">
        <summary class="cursor-pointer text-sm font-semibold">
          {{ tr('queue_settings') }}
        </summary>
        <CompositionQueues
          v-model="model.definition.queues"
          :account-id="accountId"
          :unit-id="unitId"
          :disabled="disabled"
        />
      </details>
      <details class="rounded-xl border border-n-weak p-4">
        <summary class="cursor-pointer text-sm font-semibold">
          {{ tr('notifications_title') }}
        </summary>
        <CompositionNotifications
          v-model="model.definition.notifications"
          :account-id="accountId"
          :unit-id="unitId"
          :service-id="model.service_id"
          :disabled="disabled"
        />
      </details>
    </template>
    <template v-else-if="section === 'impact'">
      <div class="grid gap-4 xl:grid-cols-2">
        <article
          class="grid content-start gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
        >
          <h3 class="font-semibold">{{ tr('classification_title') }}</h3>
          <LookupSelect
            v-for="(resource, key) in {
              priority_id: 'priorities',
              category_id: 'categories',
              subcategory_id: 'categories',
              ticket_type_id: 'ticket_types',
            }"
            :key="key"
            :model-value="String(classification[key] || '')"
            :resource="resource"
            :unit-id="unitId"
            :label="tr(`fields.${key}`)"
            :disabled="disabled"
            @update:model-value="classify(key, $event)"
          />
          <ServiceSelect
            :model-value="String(classification.service_id || '')"
            :unit-id="unitId"
            :disabled="disabled"
            @update:model-value="classify('service_id', $event)"
          />
        </article>
        <article
          class="grid content-start gap-3 rounded-xl border border-n-teal-5 bg-n-teal-2 p-4"
        >
          <h3 class="font-semibold">{{ tr('matrix_title') }}</h3>
          <p class="text-sm">{{ tr('matrix_help') }}</p>
          <p class="rounded-lg bg-n-solid-1 p-3 text-xs">
            {{ tr('ai_classification_notice') }}
          </p>
          <p class="text-xs">{{ tr('history_unchanged') }}</p>
        </article>
      </div>
      <header class="flex items-center justify-between gap-3">
        <h3 class="font-semibold">{{ tr('matrix_title') }}</h3>
        <button
          type="button"
          :class="buttonClass"
          :disabled="disabled || matrix.length >= 100"
          @click="addMatrix"
        >
          {{ tr('add_matrix') }}
        </button>
      </header>
      <article
        v-for="row in matrix"
        :key="row.key"
        class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-2 xl:grid-cols-5"
      >
        <label
          v-for="key in ['impact', 'urgency']"
          :key="key"
          class="grid gap-1 text-sm"
        >
          {{ tr(`fields.${key}`) }}
          <input
            v-model="row.match[key]"
            :class="fieldClass"
            maxlength="64"
          />
        </label>
        <LookupSelect
          :model-value="String(row.output.priority_id || '')"
          resource="priorities"
          :unit-id="unitId"
          :label="tr('calculated_priority')"
          :disabled="disabled"
          @update:model-value="
            row.output.priority_id = $event ? Number($event) : null
          "
        />
        <label class="grid gap-1 text-sm">
          {{ tr('precedence') }}
          <input
            v-model.number="row.precedence"
            type="number"
            min="1"
            :class="fieldClass"
          />
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            :checked="row.enabled !== false"
            @change="row.enabled = $event.target.checked"
          />
          {{ tr('include_target') }}
        </label>
      </article>
      <p
        v-if="!matrix.length"
        class="rounded-xl border border-dashed border-n-weak p-4 text-sm text-n-slate-11"
      >
        {{ tr('matrix_unchanged') }}
      </p>
    </template>
    <template v-else-if="section === 'advanced'">
      <div class="grid gap-4 xl:grid-cols-2">
        <article
          class="grid content-start gap-4 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
        >
          <h3 class="font-semibold">{{ tr('exceptions_title') }}</h3>
          <p class="text-xs">{{ tr('vip_help') }}</p>
          <CompanyPicker
            v-model="company"
            :disabled="disabled"
          />
          <button
            type="button"
            :class="buttonClass"
            :disabled="!company"
            @click="addException('company_ids', company)"
          >
            {{ tr('exclude_company') }}
          </button>
          <LookupSelect
            v-model="contract"
            resource="contracts"
            :unit-id="unitId"
            :label="tr('fields.contract_id')"
            :disabled="disabled"
          />
          <button
            type="button"
            :class="buttonClass"
            :disabled="!contract"
            @click="addException('contract_ids', contract)"
          >
            {{ tr('exclude_contract') }}
          </button>
          <div
            v-for="field in ['company_ids', 'contract_ids']"
            :key="field"
            class="flex flex-wrap gap-2"
          >
            <button
              v-for="id in rule.exceptions?.[field] || []"
              :key="id"
              type="button"
              :class="buttonClass"
              @click="
                rule.exceptions[field] = rule.exceptions[field].filter(
                  value => value !== id
                )
              "
            >
              {{ tr(`exception_${field}`) }} {{ id }} · {{ tr('remove') }}
            </button>
          </div>
          <label class="flex gap-2 text-sm">
            <input
              type="checkbox"
              :checked="rule.exceptions?.skip_assigned === true"
              @change="exceptions().skip_assigned = $event.target.checked"
            />
            {{ tr('skip_assigned') }}
          </label>
          <p class="rounded-lg bg-n-solid-1 p-3 text-xs">
            {{ tr('complexity_notice') }}
          </p>
        </article>
        <article
          class="grid content-start gap-4 rounded-xl border border-n-amber-5 bg-n-amber-2 p-4"
        >
          <h3 class="font-semibold">{{ tr('precedence_title') }}</h3>
          <label class="grid gap-1 text-sm">
            {{ tr('precedence') }}
            <input
              v-model.number="rule.precedence"
              type="number"
              min="1"
              max="1000000"
              :class="fieldClass"
            />
          </label>
          <p class="text-xs">{{ tr('precedence_help') }}</p>
          <LookupSelect
            :model-value="
              String(rule.output.assignment?.fallback_queue_id || '')
            "
            resource="queues"
            :unit-id="unitId"
            :label="tr('fallback_queue')"
            :disabled="disabled"
            @update:model-value="
              rule.output.assignment ||= { mode: 'queue' };
              $event
                ? (rule.output.assignment.fallback_queue_id = Number($event))
                : delete rule.output.assignment.fallback_queue_id;
            "
          />
          <p class="text-xs">{{ tr('fallback_help') }}</p>
        </article>
      </div>
      <article
        class="grid gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
      >
        <h3 class="font-semibold">{{ tr('validity_title') }}</h3>
        <div class="grid gap-3 sm:grid-cols-2">
          <label
            v-for="key in ['valid_from', 'valid_until']"
            :key="key"
            class="grid gap-1 text-sm"
          >
            {{ tr(key) }}
            <input
              type="datetime-local"
              :class="fieldClass"
              :value="
                rule[key]
                  ? new Date(
                      new Date(rule[key]).getTime() -
                        new Date(rule[key]).getTimezoneOffset() * 60000
                    )
                      .toISOString()
                      .slice(0, 16)
                  : ''
              "
              @change="validity(key, $event.target.value)"
            />
          </label>
        </div>
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            :checked="!!rule.window"
            @change="windowEnabled($event.target.checked)"
          />
          {{ tr('rule_window') }}
        </label>
        <CalendarFields
          v-if="rule.window"
          v-model="rule.window"
          :disabled="disabled"
        />
        <p class="text-xs">{{ tr('window_help') }}</p>
      </article>
    </template>
  </fieldset>
</template>
