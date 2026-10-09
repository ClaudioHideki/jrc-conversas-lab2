<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, ref, watch } from 'vue';
import LookupSelect from '../serviceDesk/components/LookupSelect.vue';
import CatalogueAnswers from '../serviceDesk/components/CatalogueAnswers.vue';
import { provideServiceDesk } from '../serviceDesk/composables/useServiceDesk';
import { helpdeskCurrentClassification } from './helpdeskPresentation';
const props = defineProps({
  modelValue: { type: Object, required: true },
  source: { type: Object, required: true },
  groupKey: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'ready']);
const session = provideServiceDesk();
const key = `helpdesk-group-ticket:${getCurrentInstance().uid}`;
const ticketReady = ref(false);
const catalogueReady = ref(true);
const readbackFailed = ref(false);
const ready = computed(
  () =>
    session.state.status === 'ready' &&
    catalogueReady.value &&
    (props.groupKey !== 'D1' || ticketReady.value)
);
watch(ready, value => emit('ready', value), { immediate: true });
watch(
  [() => session.state.context, () => props.source],
  ([context]) => {
    ticketReady.value = false;
    readbackFailed.value = false;
    if (!context || props.groupKey !== 'D1') return;
    session.load(
      key,
      'tickets',
      { unit_id: String(props.source.unit_id) },
      String(props.source.ticket_id)
    );
  },
  { immediate: true }
);
watch(
  () => session.resource(key),
  resource => {
    if (props.groupKey !== 'D1') return;
    const ticket = resource.record;
    if (resource.status !== 'ready') {
      ticketReady.value = false;
      readbackFailed.value = [
        'denied',
        'error',
        'invalid_contract',
        'not_found',
      ].includes(resource.status);
      return;
    }
    try {
      const classification = helpdeskCurrentClassification(
        ticket,
        props.source,
        props.modelValue.classification
      );
      ticketReady.value = true;
      emit('update:modelValue', { ...props.modelValue, classification });
    } catch {
      ticketReady.value = false;
      readbackFailed.value = true;
    }
  },
  { deep: true }
);
onBeforeUnmount(() => session.resetResource(key));
const selection = (part, field) =>
  String(props.modelValue[part]?.[field] || '');
function update(part, field, value) {
  const result = {
    ...props.modelValue,
    [part]: { ...props.modelValue[part], [field]: value },
  };
  if (field === 'category_id') result.classification.subcategory_id = '';
  emit('update:modelValue', result);
}
</script>

<template>
  <div class="grid gap-4 md:grid-cols-2">
    <p
      v-if="groupKey === 'D1' && (!ticketReady || readbackFailed)"
      class="text-xs text-n-slate-11"
      role="status"
    >
      {{ $t('JRC_NICO_HELPDESK.GROUP_CURRENT_TICKET_REQUIRED') }}
    </p>
    <fieldset
      v-if="groupKey === 'D1' && ticketReady"
      class="space-y-3 rounded border border-n-weak p-3"
    >
      <legend>{{ $t('JRC_NICO_HELPDESK.GROUP_CLASSIFICATION') }}</legend>
      <LookupSelect
        :model-value="selection('classification', 'ticket_type_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.ticket_type')"
        resource="ticket_types"
        :unit-id="String(source.unit_id)"
        :disabled="disabled"
        @update:model-value="
          value => update('classification', 'ticket_type_id', value)
        "
      />
      <LookupSelect
        :model-value="selection('classification', 'category_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.category')"
        resource="categories"
        roots-only
        :unit-id="String(source.unit_id)"
        :disabled="disabled"
        @update:model-value="
          value => update('classification', 'category_id', value)
        "
      />
      <LookupSelect
        :model-value="selection('classification', 'subcategory_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.subcategory')"
        resource="categories"
        :parent-id="selection('classification', 'category_id')"
        :unit-id="String(source.unit_id)"
        :disabled="disabled || !selection('classification', 'category_id')"
        @update:model-value="
          value => update('classification', 'subcategory_id', value)
        "
      />
      <LookupSelect
        :model-value="selection('classification', 'priority_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.priority')"
        resource="priorities"
        :unit-id="String(source.unit_id)"
        :disabled="disabled"
        @update:model-value="
          value => update('classification', 'priority_id', value)
        "
      />
      <LookupSelect
        v-if="Object.hasOwn(session.resource(key).record || {}, 'contract')"
        :model-value="selection('classification', 'contract_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.contract')"
        resource="contracts"
        :unit-id="String(source.unit_id)"
        :company-id="source.company_id"
        :disabled="disabled"
        @update:model-value="
          value => update('classification', 'contract_id', value)
        "
      />
      <CatalogueAnswers
        v-if="
          Object.hasOwn(session.resource(key).record || {}, 'service_fields')
        "
        editing
        :model-value="modelValue.classification?.service_fields || {}"
        :service-id="String(source.service_id || '')"
        :ticket-type-id="selection('classification', 'ticket_type_id')"
        :category-id="selection('classification', 'category_id')"
        :subcategory-id="selection('classification', 'subcategory_id')"
        :unit-id="String(source.unit_id)"
        :disabled="disabled"
        @ready="value => (catalogueReady = value)"
        @update:model-value="
          value => update('classification', 'service_fields', value)
        "
      />
    </fieldset>
    <fieldset class="space-y-3 rounded border border-n-weak p-3">
      <legend>{{ $t('JRC_NICO_HELPDESK.GROUP_HANDOFF') }}</legend>
      <LookupSelect
        :model-value="selection('handoff', 'queue_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.queue')"
        resource="queues"
        :unit-id="String(source.unit_id)"
        :disabled="disabled"
        @update:model-value="value => update('handoff', 'queue_id', value)"
      />
      <LookupSelect
        :model-value="selection('handoff', 'team_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.team')"
        resource="teams"
        :unit-id="String(source.unit_id)"
        :disabled="disabled"
        @update:model-value="value => update('handoff', 'team_id', value)"
      />
      <LookupSelect
        :model-value="selection('handoff', 'assignee_account_user_id')"
        :label="$t('JRC_SERVICE_DESK.OPS.assignee')"
        resource="assignees"
        value-key="membership_id"
        :unit-id="String(source.unit_id)"
        :disabled="disabled"
        @update:model-value="
          value => update('handoff', 'assignee_account_user_id', value)
        "
      />
    </fieldset>
  </div>
</template>
