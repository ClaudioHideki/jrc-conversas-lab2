<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CatalogueAnswers from '../../serviceDesk/components/CatalogueAnswers.vue';
import LookupSelect from '../../serviceDesk/components/LookupSelect.vue';
import ServiceDefinitionSelect from '../../serviceDesk/components/ServiceDefinitionSelect.vue';
import ServiceDeskState from '../../serviceDesk/components/ServiceDeskState.vue';
import { provideServiceDesk } from '../../serviceDesk/composables/useServiceDesk';
import '../../serviceDesk/serviceDesk.css';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  value: { type: Object, default: null },
  options: { type: Object, required: true },
  labels: { type: Object, default: () => ({}) },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'cancel', 'remove']);
const { t } = useI18n();
const copy = computed(() => ({
  TITLE: t(
    'JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SERVICE_DESK_CONFIGURATION.TITLE'
  ),
  AUTHORITY: t(
    'JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SERVICE_DESK_CONFIGURATION.AUTHORITY'
  ),
  SOURCE_UNAVAILABLE: t(
    'JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SERVICE_DESK_CONFIGURATION.SOURCE_UNAVAILABLE'
  ),
  REVIEW: t(
    'JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SERVICE_DESK_CONFIGURATION.REVIEW'
  ),
  ASSIGNMENT_REQUIRED: t(
    'JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SERVICE_DESK_CONFIGURATION.ASSIGNMENT_REQUIRED'
  ),
  INITIAL_STATUS_REQUIRED: t(
    'JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.SERVICE_DESK_CONFIGURATION.INITIAL_STATUS_REQUIRED'
  ),
}));
const fieldLabels = computed(() => ({
  unit: t('JRC_SERVICE_DESK.FIELDS.unit'),
  status: t('JRC_SERVICE_DESK.FIELDS.status'),
  title: t('JRC_SERVICE_DESK.FIELDS.title'),
  description: t('JRC_SERVICE_DESK.FIELDS.description'),
  priority: t('JRC_SERVICE_DESK.FIELDS.priority'),
  category: t('JRC_SERVICE_DESK.FIELDS.category'),
  subcategory: t('JRC_SERVICE_DESK.FIELDS.subcategory'),
  ticket_type: t('JRC_SERVICE_DESK.FIELDS.ticket_type'),
  contract: t('JRC_SERVICE_DESK.FIELDS.contract'),
  queue: t('JRC_SERVICE_DESK.FIELDS.queue'),
  team: t('JRC_SERVICE_DESK.FIELDS.team'),
  assignee: t('JRC_SERVICE_DESK.FIELDS.assignee'),
}));
const text = key => copy.value[key];
const field = key => fieldLabels.value[key];
const session = provideServiceDesk();
const selection = ref(props.value?.service_id || '');
const attributes = ref({
  title: '',
  description: '',
  service_fields: {},
  ...JSON.parse(JSON.stringify(props.value?.attributes || {})),
});
const selectedNames = ref({ ...props.labels });
const catalogueReady = ref(false);
const reviewed = ref(false);
const mappedUnitId = computed(() => String(props.options.unit?.id || ''));
const unit = computed(() =>
  session.state.context?.units.find(row => row.id === mappedUnitId.value)
);
const authorized = computed(
  () =>
    !props.disabled &&
    props.options.configuration_available === true &&
    session.state.status === 'ready' &&
    session.state.context.account_id === String(props.accountId) &&
    unit.value?.permissions.create_ticket === true &&
    session.state.context.effective_permissions.includes(
      'jrc_service_desk_customers_view'
    )
);
const sameUnit = computed(
  () => !props.value || props.value.unit_id === mappedUnitId.value
);
const canAssign = computed(
  () => authorized.value && unit.value?.permissions.assign_ticket === true
);
const fields = [
  ['priority_id', 'priorities', 'priority'],
  ['category_id', 'categories', 'category'],
  ['subcategory_id', 'categories', 'subcategory'],
  ['ticket_type_id', 'ticket_types', 'ticket_type'],
  ['contract_id', 'contracts', 'contract'],
];
const assignmentFields = [
  ['queue_id', 'queues', 'queue'],
  ['team_id', 'teams', 'team'],
  ['assignee_account_user_id', 'assignees', 'assignee'],
];
const missingAssignmentAuthority = computed(
  () =>
    authorized.value &&
    !canAssign.value &&
    assignmentFields.some(([key]) => attributes.value[key])
);
const currentName = (key, name) => {
  const selected = selectedNames.value[name];
  return selected && selected.id === attributes.value[key] ? selected.name : '';
};
const valid = computed(
  () =>
    authorized.value &&
    sameUnit.value &&
    catalogueReady.value &&
    reviewed.value &&
    unit.value?.initial_status?.id &&
    attributes.value.status_id === unit.value?.initial_status?.id &&
    attributes.value.priority_id &&
    attributes.value.title.trim().length > 0 &&
    attributes.value.title.length <= 255 &&
    attributes.value.description.trim().length > 0 &&
    (canAssign.value ||
      !assignmentFields.some(([key]) => attributes.value[key]))
);
watch(
  () => unit.value?.initial_status?.id,
  id => {
    reviewed.value = false;
    // Only the local draft follows the current native initial status.
    // The immutable source remains intact and applying still requires review.
    if (id && attributes.value.status_id !== id)
      attributes.value.status_id = id;
  },
  { immediate: true }
);
watch(
  [attributes, selection],
  () => {
    reviewed.value = false;
  },
  { deep: true }
);
watch(canAssign, () => {
  reviewed.value = false;
});
watch([authorized, sameUnit, catalogueReady], values => {
  if (values.some(value => !value)) reviewed.value = false;
});
watch(
  () => attributes.value.category_id,
  (value, previous) => {
    if (previous && value !== previous) {
      attributes.value.subcategory_id = '';
      selectedNames.value.subcategory = null;
    }
  }
);
watch(
  () => attributes.value.team_id,
  (value, previous) => {
    if (previous && value !== previous) {
      attributes.value.assignee_account_user_id = '';
      selectedNames.value.assignee = null;
    }
  }
);
const applyCatalogue = value => {
  if (!value || !authorized.value) return;
  ['category', 'ticket_type'].forEach(name => {
    if (!attributes.value[`${name}_id`] && value[name]) {
      attributes.value[`${name}_id`] = value[name].id;
      selectedNames.value[name] = value[name];
    }
  });
  ['priority', 'queue'].forEach(name => {
    if (!attributes.value[`${name}_id`] && value.defaults[name]) {
      attributes.value[`${name}_id`] = value.defaults[name].id;
      selectedNames.value[name] = value.defaults[name];
    }
  });
  selectedNames.value.service = value.service;
};
const save = () => {
  if (!valid.value) return;
  const values = JSON.parse(JSON.stringify(attributes.value));
  [...fields, ...assignmentFields].forEach(([key]) => {
    if (!values[key]) delete values[key];
  });
  emit('save', {
    unit_id: mappedUnitId.value,
    service_id: selection.value || null,
    attributes: values,
  });
};
</script>

<template>
  <form
    class="jrc-service-desk-root min-w-0 space-y-4"
    data-ending-service-desk-configuration
    @submit.prevent="save"
  >
    <h3 class="text-base font-semibold">{{ text('TITLE') }}</h3>
    <p class="break-words text-sm text-n-slate-11">{{ text('AUTHORITY') }}</p>
    <ServiceDeskState
      v-if="session.state.status !== 'ready'"
      :status="session.state.status"
      compact
    />
    <p
      v-else-if="!authorized || !sameUnit"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ text('SOURCE_UNAVAILABLE') }}
    </p>
    <fieldset
      v-else
      :disabled="disabled"
      class="grid min-w-0 gap-4 sm:grid-cols-2"
    >
      <p
        v-if="!unit.initial_status?.id"
        role="alert"
        class="text-sm text-n-ruby-11 sm:col-span-2"
      >
        {{ text('INITIAL_STATUS_REQUIRED') }}
      </p>
      <label class="min-w-0 text-sm">
        {{ field('unit') }}
        <input
          :value="unit.name"
          disabled
          class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ field('status') }}
        <input
          :value="unit.initial_status?.name || ''"
          disabled
          class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <div class="min-w-0 sm:col-span-2">
        <ServiceDefinitionSelect
          v-model="selection"
          :unit-id="mappedUnitId"
          :disabled="disabled"
        />
        <p
          v-if="selectedNames.service?.id === selection"
          class="text-xs text-n-slate-11"
        >
          {{ selectedNames.service.name }}
        </p>
      </div>
      <label class="min-w-0 text-sm sm:col-span-2">
        {{ field('title') }}
        <input
          v-model="attributes.title"
          required
          maxlength="255"
          class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-service-desk-title
        />
      </label>
      <label class="min-w-0 text-sm sm:col-span-2">
        {{ field('description') }}
        <textarea
          v-model="attributes.description"
          required
          class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-service-desk-description
        />
      </label>
      <div
        v-for="[key, resource, name] in fields"
        :key="key"
        class="min-w-0"
        :data-ending-sd-lookup="resource"
      >
        <LookupSelect
          :model-value="attributes[key] || ''"
          :resource="resource"
          :label="field(name)"
          :unit-id="mappedUnitId"
          :current-name="currentName(key, name)"
          :disabled="disabled"
          :roots-only="name === 'category'"
          :parent-id="
            name === 'subcategory' ? attributes.category_id || '' : ''
          "
          @update:model-value="attributes[key] = $event"
          @selected="selectedNames[name] = $event"
        />
      </div>
      <p
        v-if="missingAssignmentAuthority"
        role="alert"
        class="text-sm text-n-ruby-11 sm:col-span-2"
      >
        {{ text('ASSIGNMENT_REQUIRED') }}
      </p>
      <template v-if="canAssign">
        <div
          v-for="[key, resource, name] in assignmentFields"
          :key="key"
          class="min-w-0"
          :data-ending-sd-lookup="resource"
        >
          <LookupSelect
            :model-value="attributes[key] || ''"
            :resource="resource"
            :label="field(name)"
            :unit-id="mappedUnitId"
            :current-name="currentName(key, name)"
            :disabled="disabled"
            :team-id="name === 'assignee' ? attributes.team_id || '' : ''"
            :queue-id="name === 'assignee' ? attributes.queue_id || '' : ''"
            @update:model-value="attributes[key] = $event"
            @selected="selectedNames[name] = $event"
          />
        </div>
      </template>
      <div class="min-w-0 sm:col-span-2">
        <CatalogueAnswers
          v-model="attributes.service_fields"
          :unit-id="mappedUnitId"
          :service-id="selection"
          :ticket-type-id="attributes.ticket_type_id || ''"
          :category-id="attributes.category_id || ''"
          :subcategory-id="attributes.subcategory_id || ''"
          :disabled="disabled"
          @ready="catalogueReady = $event"
          @catalogue="applyCatalogue"
        />
      </div>
      <label class="flex min-w-0 items-start gap-2 text-sm sm:col-span-2">
        <input
          v-model="reviewed"
          type="checkbox"
          class="mt-1"
          data-ending-service-desk-reviewed
        />
        <span>{{ text('REVIEW') }}</span>
      </label>
    </fieldset>
    <div class="flex flex-wrap gap-3">
      <button
        type="submit"
        :disabled="!valid"
        class="rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
        data-ending-service-desk-apply
      >
        {{ t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.APPLY') }}
      </button>
      <button
        type="button"
        :disabled="disabled"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
        @click="emit('cancel')"
      >
        {{ t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.BACK') }}
      </button>
      <button
        v-if="value"
        type="button"
        :disabled="!authorized || !sameUnit"
        class="rounded-lg border border-n-ruby-6 px-3 py-2 text-sm text-n-ruby-11"
        @click="emit('remove')"
      >
        {{
          t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.CRM_CONFIGURATION.REMOVE')
        }}
      </button>
    </div>
  </form>
</template>
