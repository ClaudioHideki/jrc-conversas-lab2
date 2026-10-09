<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskConfiguration';
import LookupSelect from './LookupSelect.vue';
import ClockAutomationFields from './ClockAutomationFields.vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { canonicalId } from '../helpers/access';
import { DISTRIBUTION_MODES, portalOptions } from '../helpers/v2Configuration';
const props = defineProps({
  modelValue: { type: Object, required: true },
  resource: { type: String, required: true },
  unitId: { type: String, required: true },
  context: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const modes = computed(() => ({
  manual: t('JRC_SERVICE_DESK.V2_SETTINGS.mode_manual'),
  round_robin: t('JRC_SERVICE_DESK.V2_SETTINGS.mode_round_robin'),
  least_load: t('JRC_SERVICE_DESK.V2_SETTINGS.mode_least_load'),
  skill: t('JRC_SERVICE_DESK.V2_SETTINGS.mode_skill'),
  priority_sla: t('JRC_SERVICE_DESK.V2_SETTINGS.mode_priority_sla'),
}));
const fieldTypes = computed(() => ({
  text: t('JRC_SERVICE_DESK.V2_SETTINGS.type_text'),
  integer: t('JRC_SERVICE_DESK.V2_SETTINGS.type_integer'),
  boolean: t('JRC_SERVICE_DESK.V2_SETTINGS.type_boolean'),
  select: t('JRC_SERVICE_DESK.V2_SETTINGS.type_select'),
}));
const options = ref(null);
const optionsStatus = ref('idle');
const companyChoice = ref(null);
const contractChoice = ref('');
const serviceDefaults = computed(() => [
  {
    field: 'default_category_id',
    resource: 'categories',
    label: t('JRC_SERVICE_DESK.V2_SETTINGS.default_category'),
  },
  {
    field: 'default_ticket_type_id',
    resource: 'ticket_types',
    label: t('JRC_SERVICE_DESK.V2_SETTINGS.default_ticket_type'),
  },
  {
    field: 'default_assignee_membership_id',
    resource: 'assignees',
    label: t('JRC_SERVICE_DESK.V2_SETTINGS.default_assignee'),
    valueKey: 'membership_id',
  },
]);
const mayChooseCompany = computed(
  () =>
    props.context?.effective_permissions?.includes(
      'jrc_service_desk_customers_view'
    ) === true
);
let generation = 0;
let controller;
const update = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const updateField = (index, key, value) => {
  const fields = props.modelValue.form_fields.map((field, at) => {
    if (at !== index) return field;
    const result = { ...field, [key]: value };
    if (key === 'type') {
      if (value === 'select') result.options = [];
      else delete result.options;
    }
    return result;
  });
  update('form_fields', fields);
};
const addField = () =>
  update('form_fields', [
    ...props.modelValue.form_fields,
    { key: '', label: '', type: 'text', required: false },
  ]);
const addSelection = (field, value) => {
  const id = canonicalId(value);
  const current = props.modelValue[field];
  if (
    !id ||
    !Array.isArray(current) ||
    current.includes(id) ||
    current.length >= 100
  )
    return;
  update(field, [...current, id]);
  companyChoice.value = null;
  contractChoice.value = '';
};
const addThreshold = () =>
  update('ola_escalation_policy', {
    ...props.modelValue.ola_escalation_policy,
    enabled: props.modelValue.ola_escalation_policy?.enabled === true,
    thresholds: [
      ...(props.modelValue.ola_escalation_policy?.thresholds || []),
      { percent: null, queue_id: null, team_id: null },
    ],
  });
const updateThreshold = (index, key, value) => {
  const policy = props.modelValue.ola_escalation_policy;
  update('ola_escalation_policy', {
    ...policy,
    thresholds: policy.thresholds.map((row, at) =>
      at === index ? { ...row, [key]: value } : row
    ),
  });
};
const load = async () => {
  generation += 1;
  const turn = generation;
  controller?.abort();
  controller = new AbortController();
  options.value = null;
  if (props.resource !== 'services') return;
  const context = props.context;
  optionsStatus.value = 'loading';
  try {
    const payload = await API.portalOptions(
      context.account_id,
      props.unitId,
      props.modelValue.portal_inbox_id,
      controller.signal
    );
    if (turn !== generation || context !== props.context) return;
    options.value = portalOptions(payload, context, props.unitId);
    optionsStatus.value = 'ready';
  } catch {
    if (turn === generation) optionsStatus.value = 'error';
  }
};
watch(
  [
    () => props.context,
    () => props.resource,
    () => props.unitId,
    () => props.modelValue.portal_inbox_id,
  ],
  load,
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  options.value = null;
});
</script>

<template>
  <div class="grid gap-4">
    <fieldset
      v-if="resource === 'queues' && Array.isArray(modelValue.required_skills)"
      class="grid gap-3 border border-n-weak rounded-lg p-3"
      :disabled="disabled"
    >
      <legend>{{ t('JRC_SERVICE_DESK.V2_SETTINGS.distribution') }}</legend>
      <p class="text-sm">
        {{ t('JRC_SERVICE_DESK.V2_SETTINGS.distribution_help') }}
      </p>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_SERVICE_DESK.V2_SETTINGS.distribution') }}
        <select
          :value="modelValue.distribution_mode"
          class="border border-n-weak rounded-lg p-2"
          @change="update('distribution_mode', $event.target.value)"
        >
          <option
            v-for="value in DISTRIBUTION_MODES"
            :key="value"
            :value="value"
          >
            {{ modes[value] }}
          </option>
        </select>
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_SERVICE_DESK.V2_SETTINGS.required_skills') }}
        <textarea
          :value="modelValue.required_skills.join('\n')"
          class="border border-n-weak rounded-lg p-2"
          @input="
            update(
              'required_skills',
              $event.target.value
                .split(/\r?\n/)
                .map(value => value.trim())
                .filter(Boolean)
            )
          "
        />
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_SERVICE_DESK.V2_SETTINGS.ola_budget') }}
        <input
          type="number"
          min="1"
          :value="modelValue.ola_budget_seconds ?? ''"
          class="border border-n-weak rounded-lg p-2"
          @input="
            update(
              'ola_budget_seconds',
              $event.target.value === '' ? null : Number($event.target.value)
            )
          "
        />
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_SERVICE_DESK.V2_SETTINGS.ola_basis') }}
        <select
          :value="modelValue.ola_time_basis || ''"
          class="border border-n-weak rounded-lg p-2"
          @change="update('ola_time_basis', $event.target.value || null)"
        >
          <option value="">{{ t('JRC_SERVICE_DESK.COMMON.no_value') }}</option>
          <option value="calendar">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.calendar') }}
          </option>
          <option value="business">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.business') }}
          </option>
        </select>
      </label>
      <label class="text-sm">
        <input
          type="checkbox"
          :checked="modelValue.ola_pause_waiting"
          @change="update('ola_pause_waiting', $event.target.checked)"
        />
        {{ t('JRC_SERVICE_DESK.V2_SETTINGS.ola_pause') }}
      </label>
      <fieldset
        v-if="modelValue.ola_escalation_policy"
        class="grid gap-3 border border-n-weak rounded-lg p-3"
      >
        <legend>{{ t('JRC_SERVICE_DESK.V2_SETTINGS.escalation') }}</legend>
        <label class="text-sm">
          <input
            type="checkbox"
            :checked="modelValue.ola_escalation_policy.enabled === true"
            :disabled="!modelValue.ola_escalation_policy.thresholds?.length"
            @change="
              update('ola_escalation_policy', {
                ...modelValue.ola_escalation_policy,
                enabled: $event.target.checked,
                ...(Object.hasOwn(
                  modelValue.ola_escalation_policy,
                  'automatic'
                ) && !$event.target.checked
                  ? { automatic: false }
                  : {}),
              })
            "
          />
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.escalation_enabled') }}
        </label>
        <ClockAutomationFields
          :model-value="modelValue.ola_escalation_policy"
          :unit-id="unitId"
          :disabled="disabled"
          @update:model-value="update('ola_escalation_policy', $event)"
        />
        <div
          v-for="(threshold, index) in modelValue.ola_escalation_policy
            .thresholds || []"
          :key="index"
          class="grid gap-2 border border-n-weak rounded-lg p-2"
        >
          <label class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.escalation_percent') }}
            <input
              type="number"
              min="1"
              max="100"
              :value="threshold.percent ?? ''"
              class="border border-n-weak rounded-lg p-2"
              @input="
                updateThreshold(
                  index,
                  'percent',
                  $event.target.value === ''
                    ? null
                    : Number($event.target.value)
                )
              "
            />
          </label>
          <LookupSelect
            :model-value="threshold.queue_id || ''"
            resource="queues"
            :unit-id="unitId"
            :disabled="disabled"
            :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
            @update:model-value="
              updateThreshold(index, 'queue_id', $event || null)
            "
          />
          <LookupSelect
            :model-value="threshold.team_id || ''"
            resource="teams"
            :unit-id="unitId"
            :disabled="disabled || !threshold.queue_id"
            :label="t('JRC_SERVICE_DESK.FIELDS.team')"
            @update:model-value="
              updateThreshold(index, 'team_id', $event || null)
            "
          />
          <button
            type="button"
            @click="
              update(
                'ola_escalation_policy',
                modelValue.ola_escalation_policy.thresholds.length === 1
                  ? {}
                  : {
                      ...modelValue.ola_escalation_policy,
                      thresholds:
                        modelValue.ola_escalation_policy.thresholds.filter(
                          (_, at) => at !== index
                        ),
                    }
              )
            "
          >
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.remove_threshold') }}
          </button>
        </div>
        <button
          type="button"
          :disabled="
            (modelValue.ola_escalation_policy.thresholds || []).length >= 20
          "
          @click="addThreshold"
        >
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.add_threshold') }}
        </button>
      </fieldset>
    </fieldset>
    <template
      v-if="
        ['services', 'categories', 'ticket_types'].includes(resource) &&
        Array.isArray(modelValue.form_fields)
      "
    >
      <fieldset
        class="grid gap-3 border border-n-weak rounded-lg p-3"
        :disabled="disabled"
      >
        <legend>{{ t('JRC_SERVICE_DESK.V2_SETTINGS.catalogue') }}</legend>
        <LookupSelect
          v-if="resource === 'categories'"
          :model-value="modelValue.parent_id || ''"
          resource="categories"
          :unit-id="unitId"
          :disabled="disabled"
          :label="t('JRC_SERVICE_DESK.V2_SETTINGS.parent_category')"
          @update:model-value="update('parent_id', $event || null)"
        />
        <label v-if="resource === 'services'" class="grid gap-1 text-sm">
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.description') }}
          <textarea
            :value="modelValue.description || ''"
            maxlength="20000"
            class="border border-n-weak rounded-lg p-2"
            @input="update('description', $event.target.value)"
          />
        </label>
        <LookupSelect
          v-if="resource === 'services'"
          :model-value="modelValue.default_priority_id || ''"
          resource="priorities"
          :unit-id="unitId"
          :disabled="disabled"
          :label="t('JRC_SERVICE_DESK.V2_SETTINGS.default_priority')"
          @update:model-value="update('default_priority_id', $event || null)"
        />
        <LookupSelect
          v-if="resource === 'services'"
          :model-value="modelValue.default_queue_id || ''"
          resource="queues"
          :unit-id="unitId"
          :disabled="disabled"
          :label="t('JRC_SERVICE_DESK.V2_SETTINGS.default_queue')"
          @update:model-value="update('default_queue_id', $event || null)"
        />
        <template v-if="resource === 'services'">
          <LookupSelect
            v-for="item in serviceDefaults"
            :key="item.field"
            :model-value="modelValue[item.field] || ''"
            :resource="item.resource"
            :value-key="item.valueKey || 'id'"
            :unit-id="unitId"
            :disabled="disabled"
            :label="item.label"
            @update:model-value="update(item.field, $event || null)"
          />
          <p class="text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.restrictions_help') }}
          </p>
          <div v-if="mayChooseCompany" class="grid gap-2">
            <label class="text-sm">{{
              t('JRC_SERVICE_DESK.V2_SETTINGS.allowed_companies')
            }}</label>
            <CompanyPicker v-model="companyChoice" :disabled="disabled" />
            <button
              type="button"
              :disabled="disabled || !companyChoice"
              @click="addSelection('allowed_company_ids', companyChoice)"
            >
              {{ t('JRC_SERVICE_DESK.V2_SETTINGS.add_selection') }}
            </button>
          </div>
          <LookupSelect
            v-model="contractChoice"
            resource="contracts"
            :unit-id="unitId"
            :disabled="disabled"
            :label="t('JRC_SERVICE_DESK.V2_SETTINGS.allowed_contracts')"
          />
          <button
            type="button"
            :disabled="disabled || !contractChoice"
            @click="addSelection('allowed_contract_ids', contractChoice)"
          >
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.add_selection') }}
          </button>
          <div
            v-for="field in ['allowed_company_ids', 'allowed_contract_ids']"
            :key="field"
            class="flex flex-wrap gap-2"
          >
            <button
              v-for="id in modelValue[field] || []"
              :key="id"
              type="button"
              :disabled="disabled"
              class="rounded-lg border border-n-weak px-2 py-1 text-xs"
              @click="
                update(
                  field,
                  modelValue[field].filter(value => value !== id)
                )
              "
            >
              {{ t('JRC_SERVICE_DESK.COMMON.selected_identifier', { id }) }}
              {{ t('JRC_SERVICE_DESK.V2_SETTINGS.remove_selection') }}
            </button>
          </div>
        </template>
        <label v-if="resource === 'services'" class="text-sm">
          <input
            type="checkbox"
            :checked="modelValue.approval_required"
            @change="update('approval_required', $event.target.checked)"
          />
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.approval_required') }}
        </label>
        <div
          v-for="(field, index) in modelValue.form_fields"
          :key="index"
          class="grid gap-2 border border-n-weak rounded-lg p-3"
        >
          <label class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.field_key') }}
            <input
              :value="field.key"
              maxlength="80"
              required
              class="border border-n-weak rounded-lg p-2"
              @input="updateField(index, 'key', $event.target.value)"
            />
          </label>
          <label class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.field_label') }}
            <input
              :value="field.label"
              maxlength="255"
              required
              class="border border-n-weak rounded-lg p-2"
              @input="updateField(index, 'label', $event.target.value)"
            />
          </label>
          <label class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.field_type') }}
            <select
              :value="field.type"
              class="border border-n-weak rounded-lg p-2"
              @change="updateField(index, 'type', $event.target.value)"
            >
              <option
                v-for="(label, value) in fieldTypes"
                :key="value"
                :value="value"
              >
                {{ label }}
              </option>
            </select>
          </label>
          <label class="text-sm">
            <input
              type="checkbox"
              :checked="field.required"
              @change="updateField(index, 'required', $event.target.checked)"
            />
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.required') }}
          </label>
          <label v-if="field.type === 'select'" class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.options') }}
            <textarea
              :value="field.options.join('\n')"
              class="border border-n-weak rounded-lg p-2"
              @input="
                updateField(
                  index,
                  'options',
                  $event.target.value.split(/\r?\n/).filter(Boolean)
                )
              "
            />
          </label>
          <button
            type="button"
            @click="
              update(
                'form_fields',
                modelValue.form_fields.filter((_, at) => at !== index)
              )
            "
          >
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.remove_field') }}
          </button>
        </div>
        <button
          type="button"
          :disabled="modelValue.form_fields.length >= 50"
          @click="addField"
        >
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.add_field') }}
        </button>
      </fieldset>
      <fieldset
        v-if="resource === 'services'"
        class="grid gap-3 border border-n-weak rounded-lg p-3"
        :disabled="disabled"
      >
        <legend>{{ t('JRC_SERVICE_DESK.V2_SETTINGS.portal') }}</legend>
        <label class="grid gap-1 text-sm">
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.portal_history_days') }}
          <input
            type="number"
            min="1"
            :value="modelValue.portal_history_days ?? ''"
            class="border border-n-weak rounded-lg p-2"
            @input="
              update(
                'portal_history_days',
                $event.target.value === '' ? null : Number($event.target.value)
              )
            "
          />
        </label>
        <label class="grid gap-1 text-sm">
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.portal_access_until') }}
          <input
            type="text"
            maxlength="80"
            :value="modelValue.portal_access_until || ''"
            class="border border-n-weak rounded-lg p-2"
            @input="update('portal_access_until', $event.target.value || null)"
          />
        </label>
        <p class="text-sm">
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.portal_help') }}
        </p>
        <p v-if="optionsStatus === 'loading'">
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.loading_options') }}
        </p>
        <p v-if="optionsStatus === 'error'" role="alert">
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.options_unavailable') }}
        </p>
        <template v-if="optionsStatus === 'ready'">
          <label class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.widget') }}
            <select
              :value="modelValue.portal_inbox_id || ''"
              class="border border-n-weak rounded-lg p-2"
              @change="update('portal_inbox_id', $event.target.value || null)"
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.COMMON.select') }}
              </option>
              <option
                v-for="row in options.inboxes"
                :key="row.id"
                :value="row.id"
              >
                {{ row.name }}
              </option>
            </select>
          </label>
          <label class="grid gap-1 text-sm">
            {{ t('JRC_SERVICE_DESK.V2_SETTINGS.executor') }}
            <select
              :value="modelValue.portal_execution_membership_id || ''"
              :disabled="!modelValue.portal_inbox_id"
              class="border border-n-weak rounded-lg p-2"
              @change="
                update(
                  'portal_execution_membership_id',
                  $event.target.value || null
                )
              "
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.COMMON.select') }}
              </option>
              <option
                v-for="row in options.execution_memberships"
                :key="row.id"
                :value="row.id"
              >
                {{ row.name }}
              </option>
            </select>
          </label>
        </template>
        <label class="text-sm">
          <input
            type="checkbox"
            :checked="modelValue.portal_enabled"
            :disabled="
              !modelValue.portal_enabled &&
              (!modelValue.active ||
                !modelValue.default_priority_id ||
                !options?.inboxes.some(
                  row => row.id === modelValue.portal_inbox_id
                ) ||
                !options?.execution_memberships.some(
                  row => row.id === modelValue.portal_execution_membership_id
                ))
            "
            @change="update('portal_enabled', $event.target.checked)"
          />
          {{ t('JRC_SERVICE_DESK.V2_SETTINGS.portal_enabled') }}
        </label>
      </fieldset>
    </template>
  </div>
</template>
