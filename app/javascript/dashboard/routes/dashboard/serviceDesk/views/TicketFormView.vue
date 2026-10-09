<script setup>
import ImpactUrgencySelect from '../components/ImpactUrgencySelect.vue';
import { T } from 'dashboard/routes/dashboard/jrcCustomers/copy';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import RelationshipAPI from 'dashboard/api/jrcRelationship';
const props = defineProps({ screen: { type: String, default: 'new' } });
const { canAccess: mayUseMasterDirectory } = useCustomerMaster();
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import ScopeBar from '../components/ScopeBar.vue';
import ServiceDefinitionSelect from '../components/ServiceDefinitionSelect.vue';
import CatalogueAnswers from '../components/CatalogueAnswers.vue';
import LookupSelect from '../components/LookupSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canAct, canonicalId } from '../helpers/access';
import Feedback from '../components/WriteFeedback.vue';
import {
  createTicketDraft,
  updateTicketDraft,
  newRequestKey,
  ticketFileFingerprints,
} from '../helpers/drafts';
import { serviceDeskRouteName } from '../routeDefinitions';
const { t, tm } = useI18n();
const session = useServiceDesk();
const hasCustomerMaster = computed(
  () =>
    mayUseMasterDirectory.value &&
    session.state.context?.effective_permissions?.includes(
      'jrc_service_desk_customers_view'
    ) === true
);
const route = useRoute();
const router = useRouter();
const key = 'ticket:edit';
const writeKey = 'ticket:form:write';
let requestKey = null;
const localError = ref(false);
const mutation = computed(
  () => session.operations?.mutation(writeKey) || { status: 'idle' }
);
const hashingFiles = ref(false);
const busy = computed(
  () => mutation.value.status === 'saving' || hashingFiles.value
);
const step = ref(0);
const operatorId = ref('');
const blank = () => ({
  company_id: null,
  unit_id: '',
  requester_id: '',
  priority_id: '',
  impact_code: '',
  urgency_code: '',
  use_channel_routing: false,
  category_id: '',
  ticket_type_id: '',
  subcategory_id: '',
  contract_id: '',
  assignee_id: '',
  team_id: '',
  queue_id: '',
  title: '',
  description: '',
  conversation_id: '',
  service_id: '',
  service_fields: {},
});
const serviceReady = ref(true);
const catalogue = ref(null);
const files = ref([]);
const draft = reactive(blank());
watch(
  [
    () => draft.service_id,
    () => draft.ticket_type_id,
    () => draft.category_id,
    () => draft.subcategory_id,
  ],
  values => {
    serviceReady.value = !values.some(Boolean);
  }
);
const edit = computed(() => props.screen === 'edit');
const result = computed(() => session.resource(key));
const record = computed(() => result.value.record);
const unit = computed(() =>
  session.state.context?.units.find(item => item.id === draft.unit_id)
);
const mayEdit = computed(() =>
  edit.value
    ? !!record.value && canAct(record.value, 'update')
    : unit.value?.permissions.create_ticket === true
);
const steps = computed(() => tm('JRC_SERVICE_DESK.FORM.steps'));
const selectedNames = reactive({
  requester: null,
  priority: null,
  category: null,
  ticket_type: null,
  subcategory: null,
  contract: null,
});
const applyCatalogue = value => {
  catalogue.value = value;
  if (!value || edit.value) return;
  ['category', 'ticket_type'].forEach(field => {
    if (!draft[`${field}_id`] && value[field]) {
      draft[`${field}_id`] = value[field].id;
      selectedNames[field] = value[field];
    }
  });
  ['priority', 'queue', 'assignee'].forEach(field => {
    const defaultKey =
      field === 'assignee' ? 'assignee_account_user_id' : `${field}_id`;
    if (
      !draft[`${field}_id`] &&
      value.defaults[defaultKey] &&
      (field === 'priority' || unit.value?.permissions.assign_ticket === true)
    ) {
      draft[`${field}_id`] = value.defaults[defaultKey];
      if (field === 'priority')
        selectedNames.priority = value.defaults.priority;
    }
  });
};
watch(
  () => draft.category_id,
  (value, previous) => {
    if (previous && value !== previous) {
      draft.subcategory_id = '';
      selectedNames.subcategory = null;
    }
  }
);
watch(
  [() => draft.company_id, () => draft.requester_id],
  (values, previous) => {
    if (
      previous.some(Boolean) &&
      values.some((value, index) => value !== previous[index])
    ) {
      draft.contract_id = '';
      selectedNames.contract = null;
    }
  }
);
const catalogueAccess = computed(() => {
  if (!catalogue.value) return true;
  const companies = catalogue.value.allowed_company_ids;
  const contracts = catalogue.value.allowed_contract_ids;
  return (
    (!companies.length || companies.includes(canonicalId(draft.company_id))) &&
    (!contracts.length || contracts.includes(draft.contract_id))
  );
});
const relationshipCustomer = ref(null);
let relationshipEpoch = 0;
const applyRelationshipCustomer = () => {
  if (edit.value || !relationshipCustomer.value || !hasCustomerMaster.value)
    return;
  draft.requester_id = relationshipCustomer.value.id;
  draft.company_id = relationshipCustomer.value.company_id;
  selectedNames.requester = relationshipCustomer.value;
};
const loadRelationshipCustomer = async () => {
  relationshipEpoch += 1;
  const epoch = relationshipEpoch;
  relationshipCustomer.value = null;
  const assignmentId = canonicalId(route.query.relationship_assignment_id);
  const requesterId = canonicalId(route.query.requester_id);
  if (edit.value || !hasCustomerMaster.value || !assignmentId || !requesterId)
    return;
  try {
    const { data } = await RelationshipAPI.channels(
      route.params.accountId,
      assignmentId
    );
    if (epoch !== relationshipEpoch || !data.can_service_desk) return;
    const contact = data.contacts.find(
      item => canonicalId(item.id) === requesterId
    );
    if (!contact) return;
    relationshipCustomer.value = {
      id: requesterId,
      name: contact.name,
      company_id: data.company_id || null,
    };
    applyRelationshipCustomer();
  } catch {
    /* Native form stays available without an unauthorized prefill. */
  }
};
const resetNames = () => {
  Object.keys(selectedNames).forEach(field => {
    selectedNames[field] = null;
  });
};
const lookupLabels = computed(() =>
  Object.fromEntries(
    Object.keys(selectedNames).map(field => {
      const id = draft[`${field}_id`];
      const selected = selectedNames[field];
      const persisted = record.value?.[field];
      const matching = [selected, persisted].find(item => item?.id === id);
      const label = matching?.name || '';
      return [
        field,
        id
          ? label || t('JRC_SERVICE_DESK.COMMON.selected_identifier', { id })
          : t('JRC_SERVICE_DESK.COMMON.no_value'),
      ];
    })
  )
);
const changeUnit = value => {
  if (!busy.value && value !== draft.unit_id) {
    Object.assign(draft, blank(), { unit_id: value });
    files.value = [];
    resetNames();
    applyRelationshipCustomer();
  }
};
const load = () => {
  step.value = 0;
  resetNames();
  operatorId.value = '';
  requestKey = null;
  Object.assign(draft, blank());
  files.value = [];
  applyRelationshipCustomer();
  if (edit.value)
    return session.load(key, 'tickets', {}, route.params.ticketId);
  return undefined;
};
watch([() => route.params.ticketId, () => session.state.status], load, {
  immediate: true,
});
watch(
  [
    () => route.params.accountId,
    () => route.query.relationship_assignment_id,
    () => route.query.requester_id,
    () => session.userId?.value,
    hasCustomerMaster,
    edit,
  ],
  loadRelationshipCustomer,
  { immediate: true }
);
watch(record, value => {
  if (!value || !edit.value || !canAct(value, 'update')) return;
  Object.assign(draft, {
    company_id: value.company?.id || null,
    unit_id: value.unit_id,
    service_id: value.service?.id || '',
    requester_id: value.requester?.id || '',
    priority_id: value.priority?.id || '',
    category_id: value.category?.id || '',
    ticket_type_id: value.ticket_type?.id || '',
    subcategory_id: value.subcategory?.id || '',
    contract_id: value.contract?.id || '',
    assignee_id: value.assignee?.id || '',
    team_id: value.team?.id || '',
    queue_id: value.queue?.id || '',
    title: value.title,
    description: value.description,
    service_fields: { ...(value.service_fields || {}) },
  });
  operatorId.value =
    session.state.context?.units.find(item => item.id === value.unit_id)
      ?.operator_company.id || '';
});
onBeforeUnmount(() => {
  relationshipEpoch += 1;
  relationshipCustomer.value = null;
  Object.assign(draft, blank());
  files.value = [];
  session.resetResource(key);
  session.operations?.cancel(writeKey);
});
const cancel = () =>
  router.push({
    name: serviceDeskRouteName(edit.value ? 'detail' : 'tickets'),
    params: {
      accountId: session.accountId.value,
      ...(edit.value ? { ticketId: route.params.ticketId } : {}),
    },
  });

const maySave = computed(
  () =>
    !!session.operations &&
    mayEdit.value &&
    !busy.value &&
    !hashingFiles.value &&
    files.value.length <= 5 &&
    draft.title.trim() &&
    (draft.priority_id ||
      (!edit.value && draft.impact_code && draft.urgency_code)) &&
    serviceReady.value &&
    catalogueAccess.value &&
    (edit.value || (draft.requester_id && unit.value?.initial_status?.id))
);
const submit = async () => {
  if (!maySave.value) return;
  localError.value = false;
  try {
    if (!edit.value) requestKey ||= newRequestKey();
    const payload = edit.value
      ? updateTicketDraft(draft, record.value, hasCustomerMaster.value)
      : createTicketDraft(
          draft,
          unit.value,
          requestKey,
          hasCustomerMaster.value
        );
    if (!edit.value && files.value.length) {
      hashingFiles.value = true;
      const context = session.state.context;
      const selected = [...files.value];
      const fingerprints = await ticketFileFingerprints(selected);
      if (
        context !== session.state.context ||
        selected.some((file, index) => file !== files.value[index]) ||
        selected.length !== files.value.length
      )
        return;
      payload.files = selected;
      payload.file_fingerprints = fingerprints;
    }
    const confirmed = await session.operations.write(
      writeKey,
      edit.value ? 'update' : 'create',
      payload,
      record.value
    );
    if (confirmed)
      await router.push({
        name: serviceDeskRouteName('detail'),
        params: { accountId: session.accountId.value, ticketId: confirmed.id },
      });
  } catch {
    localError.value = true;
  } finally {
    hashingFiles.value = false;
  }
};
</script>

<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t(`JRC_SERVICE_DESK.SCREENS.${screen}`) }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.FORM.subtitle') }}
        </p>
      </div>
      <Button
        color="slate"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
        :disabled="busy"
        @click="cancel"
      />
    </header>
    <Banner color="amber" class="mb-4">
      {{ t('JRC_SERVICE_DESK.FORM.draft_notice') }}
    </Banner>
    <State
      v-if="edit && result.status !== 'ready'"
      :status="result.status"
      retry
      @retry="session.state.status === 'ready' ? load() : session.retry()"
    />
    <State v-else-if="edit && !mayEdit" status="denied" />
    <template v-else>
      <div
        class="sd-wizard-steps"
        :aria-label="t('JRC_SERVICE_DESK.SCREENS.new')"
      >
        <button
          v-for="(label, index) in steps"
          :key="index"
          type="button"
          class="sd-wizard-step"
          :aria-current="index === step ? 'step' : undefined"
          @click="step = index"
        >
          <span class="sd-badge">
            {{ index + 1 }}
          </span>
          <span>
            {{ label }}
          </span>
        </button>
      </div>
      <div class="sd-two-columns">
        <Panel :title="steps[step]">
          <form @submit.prevent="submit">
            <Feedback
              :status="localError ? 'invalid_input' : mutation.status"
            />
            <div v-if="step === 0" class="grid gap-4">
              <ScopeBar
                v-if="!edit"
                v-model:operator-id="operatorId"
                :unit-id="draft.unit_id"
                required
                :disabled="busy"
                @update:unit-id="changeUnit"
              />
              <p v-else class="text-sm text-n-slate-11">
                {{ unit?.operator_company.name }} / {{ unit?.name }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.client_help') }}
              </p>
              <div v-if="hasCustomerMaster">
                <p class="mb-1 text-sm font-medium">{{ T.servedCompany }}</p>
                <CompanyPicker
                  v-model="draft.company_id"
                  :disabled="!mayEdit || busy"
                />
              </div>
              <Input
                v-else
                :label="t('JRC_SERVICE_DESK.COMMON.client_company')"
                :placeholder="t('JRC_SERVICE_DESK.NATIVE.company_from_contact')"
                disabled
              />
              <LookupSelect
                v-model="draft.requester_id"
                resource="requesters"
                :label="t('JRC_SERVICE_DESK.FIELDS.requester')"
                :unit-id="draft.unit_id"
                :disabled="edit || !mayEdit || busy"
                :current-name="record?.requester?.name || ''"
                @selected="selectedNames.requester = $event"
              />
              <Input
                v-model="draft.title"
                :label="t('JRC_SERVICE_DESK.FIELDS.title')"
                :placeholder="t('JRC_SERVICE_DESK.FORM.title_placeholder')"
                :disabled="!mayEdit || busy"
                maxlength="255"
              />
              <TextArea
                v-model="draft.description"
                :max-length="20000"
                resize
                :label="t('JRC_SERVICE_DESK.FIELDS.description')"
                :placeholder="
                  t('JRC_SERVICE_DESK.FORM.description_placeholder')
                "
                :disabled="!mayEdit || busy"
              />
              <p v-if="!mayEdit" class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.no_permission') }}
              </p>
              <label v-if="!edit" class="grid gap-1 text-sm">
                {{ t('JRC_SERVICE_DESK.TICKET.upload') }}
                <input
                  type="file"
                  multiple
                  :disabled="!mayEdit || busy || hashingFiles"
                  @change="files = Array.from($event.target.files)"
                />
              </label>
              <ul v-if="files.length" class="m-0 text-xs text-n-slate-11">
                <li v-for="(file, index) in files" :key="index">
                  {{ file.name }}
                </li>
              </ul>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.attachments_help') }}
              </p>
            </div>
            <div v-else-if="step === 1" class="grid gap-4">
              <ImpactUrgencySelect
                v-if="!edit"
                v-model:impact="draft.impact_code"
                v-model:urgency="draft.urgency_code"
                :unit-id="draft.unit_id"
                :disabled="!mayEdit || busy"
              />
              <label
                v-if="!edit && unit?.permissions.assign_ticket === true"
                class="flex items-start gap-2 text-sm"
              >
                <input
                  v-model="draft.use_channel_routing"
                  type="checkbox"
                  :disabled="!mayEdit || busy"
                />
                <span>{{ t('JRC_SERVICE_DESK.COMPLETION.routing_help') }}</span>
              </label>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.classify_help') }}
              </p>
              <div class="sd-fields-grid">
                <LookupSelect
                  v-model="draft.priority_id"
                  resource="priorities"
                  :label="t('JRC_SERVICE_DESK.FIELDS.priority')"
                  :unit-id="draft.unit_id"
                  :disabled="
                    !mayEdit ||
                    busy ||
                    (edit && record?.permissions.change_priority !== true) ||
                    (!edit && !!draft.impact_code && !!draft.urgency_code)
                  "
                  :current-name="record?.priority?.name || ''"
                  @selected="selectedNames.priority = $event"
                />
                <LookupSelect
                  v-model="draft.category_id"
                  resource="categories"
                  roots-only
                  :label="t('JRC_SERVICE_DESK.FIELDS.category')"
                  :unit-id="draft.unit_id"
                  :disabled="!mayEdit || busy"
                  :current-name="record?.category?.name || ''"
                  @selected="selectedNames.category = $event"
                />
                <LookupSelect
                  v-model="draft.subcategory_id"
                  resource="categories"
                  :parent-id="draft.category_id"
                  :label="t('JRC_SERVICE_DESK.FIELDS.subcategory')"
                  :unit-id="draft.unit_id"
                  :disabled="!mayEdit || busy || !draft.category_id"
                  :current-name="record?.subcategory?.name || ''"
                  @selected="selectedNames.subcategory = $event"
                />
                <LookupSelect
                  v-model="draft.ticket_type_id"
                  resource="ticket_types"
                  :label="t('JRC_SERVICE_DESK.FIELDS.ticket_type')"
                  :unit-id="draft.unit_id"
                  :disabled="!mayEdit || busy"
                  :current-name="record?.ticket_type?.name || ''"
                  @selected="selectedNames.ticket_type = $event"
                />
                <LookupSelect
                  v-model="draft.assignee_id"
                  resource="assignees"
                  :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
                  :unit-id="draft.unit_id"
                  :disabled="
                    edit ||
                    !mayEdit ||
                    busy ||
                    unit?.permissions.assign_ticket !== true
                  "
                  :current-name="record?.assignee?.name || ''"
                />
                <LookupSelect
                  v-model="draft.team_id"
                  resource="teams"
                  :label="t('JRC_SERVICE_DESK.FIELDS.team')"
                  :unit-id="draft.unit_id"
                  :disabled="
                    edit ||
                    !mayEdit ||
                    busy ||
                    unit?.permissions.assign_ticket !== true
                  "
                  :current-name="record?.team?.name || ''"
                />
                <LookupSelect
                  v-model="draft.queue_id"
                  resource="queues"
                  :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
                  :unit-id="draft.unit_id"
                  :disabled="
                    edit ||
                    !mayEdit ||
                    busy ||
                    unit?.permissions.assign_ticket !== true
                  "
                  :current-name="record?.queue?.name || ''"
                />
                <Input
                  :model-value="
                    record?.status?.name || unit?.initial_status?.name || ''
                  "
                  :label="t('JRC_SERVICE_DESK.FIELDS.status')"
                  :placeholder="t('JRC_SERVICE_DESK.FORM.status_help')"
                  disabled
                />
              </div>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.source_help') }}
              </p>
            </div>
            <div v-else-if="step === 2" class="grid gap-4">
              <p class="text-sm text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.relationships_help') }}
              </p>
              <div class="sd-fields-grid">
                <Input
                  v-for="field in ['asset', 'crm', 'parent_ticket']"
                  :key="field"
                  :label="t(`JRC_SERVICE_DESK.FIELDS.${field}`)"
                  :placeholder="t('JRC_SERVICE_DESK.COMMON.pending_cp4')"
                  disabled
                />
              </div>
              <LookupSelect
                v-model="draft.contract_id"
                resource="contracts"
                :label="t('JRC_SERVICE_DESK.FIELDS.contract')"
                :unit-id="draft.unit_id"
                :company-id="draft.company_id"
                :contact-id="draft.requester_id"
                :allowed-ids="catalogue?.allowed_contract_ids || []"
                :disabled="!mayEdit || busy || !draft.requester_id"
                :current-name="record?.contract?.name || ''"
                @selected="selectedNames.contract = $event"
              />
              <ServiceDefinitionSelect
                v-if="!edit"
                v-model="draft.service_id"
                :unit-id="draft.unit_id"
                :disabled="!mayEdit || busy"
              />
              <p v-if="edit" class="text-xs">
                {{
                  record?.service?.name ||
                  t('JRC_SERVICE_DESK.LIFECYCLE.unit_policy')
                }}
              </p>
              <Input
                v-if="!edit"
                v-model="draft.conversation_id"
                :label="t('JRC_SERVICE_DESK.OPS.conversation_id')"
                :disabled="
                  !mayEdit ||
                  busy ||
                  unit?.permissions.link_conversation !== true
                "
                maxlength="19"
              />
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.OPS.conversation_help') }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.projects_help') }}
              </p>
            </div>
            <div v-else class="grid gap-4">
              <p class="text-sm text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.review_help') }}
              </p>
              <h3 class="text-base break-words">
                {{ draft.title || t('JRC_SERVICE_DESK.COMMON.no_value') }}
              </h3>
              <p class="whitespace-pre-wrap break-words text-sm">
                {{ draft.description || t('JRC_SERVICE_DESK.COMMON.no_value') }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.required_help') }}
              </p>
              <State
                status="pending"
                compact
                :description="t('JRC_SERVICE_DESK.TICKET.sla_pending')"
              />
            </div>
            <CatalogueAnswers
              v-show="step === 2"
              v-model="draft.service_fields"
              :service-id="draft.service_id"
              :ticket-type-id="draft.ticket_type_id"
              :category-id="draft.category_id"
              :subcategory-id="draft.subcategory_id"
              :editing="edit"
              :unit-id="draft.unit_id"
              :disabled="!mayEdit || busy"
              @ready="serviceReady = $event"
              @catalogue="applyCatalogue"
            />
            <p
              v-if="!catalogueAccess"
              role="alert"
              class="text-sm text-n-ruby-11"
            >
              {{ t('JRC_SERVICE_DESK.FORM.catalogue_restricted') }}
            </p>
            <div class="sd-footer-actions">
              <Button
                type="button"
                color="slate"
                variant="outline"
                :label="t('JRC_SERVICE_DESK.COMMON.previous')"
                :disabled="step === 0"
                @click="step -= 1"
              />
              <Button
                v-if="step < 3"
                type="button"
                :label="t('JRC_SERVICE_DESK.COMMON.next')"
                @click="step += 1"
              />
              <Button
                v-else
                type="submit"
                :disabled="!maySave"
                :label="
                  t(
                    edit
                      ? 'JRC_SERVICE_DESK.COMMON.save'
                      : 'JRC_SERVICE_DESK.COMMON.create'
                  )
                "
              />
            </div>
          </form>
        </Panel>
        <Panel :title="t('JRC_SERVICE_DESK.FORM.summary')" class="sd-sticky">
          <dl class="sd-detail-list">
            <dt>
              {{ t('JRC_SERVICE_DESK.FIELDS.operator_company') }}
            </dt>
            <dd>
              {{
                unit?.operator_company.name ||
                t('JRC_SERVICE_DESK.COMMON.no_value')
              }}
            </dd>
            <dt>
              {{ t('JRC_SERVICE_DESK.FIELDS.unit') }}
            </dt>
            <dd>
              {{ unit?.name || t('JRC_SERVICE_DESK.COMMON.no_value') }}
            </dd>
            <template v-for="(value, field) in lookupLabels" :key="field">
              <dt>
                {{ t(`JRC_SERVICE_DESK.FIELDS.${field}`) }}
              </dt>
              <dd>
                {{ value }}
              </dd>
            </template>
            <dt>
              {{ t('JRC_SERVICE_DESK.FIELDS.title') }}
            </dt>
            <dd>
              {{ draft.title || t('JRC_SERVICE_DESK.COMMON.no_value') }}
            </dd>
          </dl>
          <p class="text-xs text-n-slate-11 mt-4">
            {{ t('JRC_SERVICE_DESK.FORM.draft_notice') }}
          </p>
          <State
            status="pending"
            compact
            :description="t('JRC_SERVICE_DESK.TICKET.sla_pending')"
          />
        </Panel>
      </div>
    </template>
  </section>
</template>
