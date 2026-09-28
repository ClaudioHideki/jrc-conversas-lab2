<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import PendingAction from '../components/PendingAction.vue';
import ScopeBar from '../components/ScopeBar.vue';
import ServiceDefinitionSelect from '../components/ServiceDefinitionSelect.vue';
import LookupSelect from '../components/LookupSelect.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canAct } from '../helpers/access';
import Feedback from '../components/WriteFeedback.vue';
import { createTicketDraft, updateTicketDraft, newRequestKey } from '../helpers/drafts';
import { serviceDeskRouteName } from '../routeDefinitions';
const props = defineProps({ screen: { type: String, default: 'new' } });
const { t, tm } = useI18n();
const session = useServiceDesk();
const route = useRoute();
const router = useRouter();
const key = 'ticket:edit';
const writeKey = 'ticket:form:write';
let requestKey = null;
const localError = ref(false);
const mutation = computed(() => session.operations?.mutation(writeKey) || { status: 'idle' });
const busy = computed(() => mutation.value.status === 'saving');
const step = ref(0);
const operatorId = ref('');
const blank = () => ({ unit_id: '', requester_id: '', priority_id: '', category_id: '', assignee_id: '', team_id: '', queue_id: '', title: '', description: '', conversation_id: '', service_id: '' });
const draft = reactive(blank());
const edit = computed(() => props.screen === 'edit');
const result = computed(() => session.resource(key));
const record = computed(() => result.value.record);
const unit = computed(() => session.state.context?.units.find(item => item.id === draft.unit_id));
const mayEdit = computed(() => edit.value ? !!record.value && canAct(record.value, 'update') : unit.value?.permissions.create_ticket === true);
const steps = computed(() => tm('JRC_SERVICE_DESK.FORM.steps'));
const selectedNames = reactive({ requester: null, priority: null, category: null });
const resetNames = () => { Object.keys(selectedNames).forEach(key => { selectedNames[key] = null; }); };
const lookupLabels = computed(() => Object.fromEntries(['requester', 'priority', 'category'].map(field => {
  const id = draft[`${field}_id`];
  const selected = selectedNames[field];
  const persisted = record.value?.[field];
  const label = selected?.id === id ? selected.name : persisted?.id === id ? persisted.name : '';
  return [field, id ? label || t('JRC_SERVICE_DESK.COMMON.selected_identifier', { id }) : t('JRC_SERVICE_DESK.COMMON.no_value')];
})));
const changeUnit = value => {
  if (!busy.value && value !== draft.unit_id) {
    Object.assign(draft, blank(), { unit_id: value });
    resetNames();
  }
};
const load = () => {
  step.value = 0;
  resetNames();
  operatorId.value = '';
  requestKey = null;
  Object.assign(draft, blank());
  if (edit.value)
    return session.load(key, 'tickets', {}, route.params.ticketId);
  return undefined;
};
watch([() => route.params.ticketId, () => session.state.status], load, { immediate: true });
watch(record, value => {
  if (!value || !edit.value || !canAct(value, 'update'))
    return;
  Object.assign(draft, { unit_id: value.unit_id, service_id: value.service?.id || '', requester_id: value.requester?.id || '', priority_id: value.priority?.id || '', category_id: value.category?.id || '', assignee_id: value.assignee?.id || '', team_id: value.team?.id || '', queue_id: value.queue?.id || '', title: value.title, description: value.description });
  operatorId.value = session.state.context?.units.find(item => item.id === value.unit_id)?.operator_company.id || '';
});
onBeforeUnmount(() => { Object.assign(draft, blank()); session.resetResource(key); session.operations?.cancel(writeKey); });
const cancel = () => router.push({ name: serviceDeskRouteName(edit.value ? 'detail' : 'tickets'), params: { accountId: session.accountId.value, ...(edit.value ? { ticketId: route.params.ticketId } : {}) } });

const maySave = computed(() => !!session.operations && mayEdit.value && !busy.value && draft.title.trim() && draft.priority_id && (edit.value || (draft.requester_id && unit.value?.initial_status?.id)));
const submit = async () => {
  if (!maySave.value) return;
  localError.value = false;
  try {
    if (!edit.value) requestKey ||= newRequestKey();
    const payload = edit.value ? updateTicketDraft(draft, record.value) : createTicketDraft(draft, unit.value, requestKey);
    const confirmed = await session.operations.write(writeKey, edit.value ? 'update' : 'create', payload, record.value);
    if (confirmed) await router.push({ name: serviceDeskRouteName('detail'), params: { accountId: session.accountId.value, ticketId: confirmed.id } });
  } catch { localError.value = true; }
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
      <Button color="slate" variant="ghost" :label="t('JRC_SERVICE_DESK.COMMON.cancel')" :disabled="busy" @click="cancel" />
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
      <div class="sd-wizard-steps" :aria-label="t('JRC_SERVICE_DESK.SCREENS.new')">
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
            <Feedback :status="localError ? 'invalid_input' : mutation.status" />
            <div v-if="step === 0" class="grid gap-4">
              <ScopeBar
                v-if="!edit"
                :unit-id="draft.unit_id"
                v-model:operator-id="operatorId"
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
              <Input :label="t('JRC_SERVICE_DESK.COMMON.client_company')" :placeholder="t('JRC_SERVICE_DESK.NATIVE.company_from_contact')" disabled />
              <LookupSelect
                v-model="draft.requester_id"
                @selected="selectedNames.requester = $event"
                resource="requesters"
                :label="t('JRC_SERVICE_DESK.FIELDS.requester')"
                :unit-id="draft.unit_id"
                :disabled="edit || !mayEdit || busy"
                :current-name="record?.requester?.name || ''"
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
                :placeholder="t('JRC_SERVICE_DESK.FORM.description_placeholder')"
                :disabled="!mayEdit || busy"
              />
              <p v-if="!mayEdit" class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.no_permission') }}
              </p>
              <PendingAction :label="t('JRC_SERVICE_DESK.TICKET.upload')" />
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.attachments_help') }}
              </p>
            </div>
            <div v-else-if="step === 1" class="grid gap-4">
              <p class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.FORM.classify_help') }}
              </p>
              <div class="sd-fields-grid">
                <LookupSelect
                  v-model="draft.priority_id"
                  @selected="selectedNames.priority = $event"
                  resource="priorities"
                  :label="t('JRC_SERVICE_DESK.FIELDS.priority')"
                  :unit-id="draft.unit_id"
                  :disabled="!mayEdit || busy || (edit && record?.permissions.change_priority !== true)"
                  :current-name="record?.priority?.name || ''"
                />
                <LookupSelect
                  v-model="draft.category_id"
                  @selected="selectedNames.category = $event"
                  resource="categories"
                  :label="t('JRC_SERVICE_DESK.FIELDS.category')"
                  :unit-id="draft.unit_id"
                  :disabled="!mayEdit || busy"
                  :current-name="record?.category?.name || ''"
                />
                <LookupSelect
                  v-model="draft.assignee_id"
                  resource="assignees"
                  :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
                  :unit-id="draft.unit_id"
                  :disabled="edit || !mayEdit || busy || unit?.permissions.assign_ticket !== true"
                  :current-name="record?.assignee?.name || ''"
                />
                <LookupSelect
                  v-model="draft.team_id"
                  resource="teams"
                  :label="t('JRC_SERVICE_DESK.FIELDS.team')"
                  :unit-id="draft.unit_id"
                  :disabled="edit || !mayEdit || busy || unit?.permissions.assign_ticket !== true"
                  :current-name="record?.team?.name || ''"
                />
                <LookupSelect
                  v-model="draft.queue_id"
                  resource="queues"
                  :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
                  :unit-id="draft.unit_id"
                  :disabled="edit || !mayEdit || busy || unit?.permissions.assign_ticket !== true"
                  :current-name="record?.queue?.name || ''"
                />
                <Input
                  :model-value="record?.status?.name || unit?.initial_status?.name || ''"
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
                  v-for="field in ['contract', 'asset', 'crm', 'parent_ticket']"
                  :key="field"
                  :label="t(`JRC_SERVICE_DESK.FIELDS.${field}`)"
                  :placeholder="t('JRC_SERVICE_DESK.COMMON.pending_cp4')"
                  disabled
                />
              </div>
              <ServiceDefinitionSelect v-if="!edit" v-model="draft.service_id" :unit-id="draft.unit_id" :disabled="!mayEdit || busy" />
              <p v-else class="text-xs">{{ record?.service?.name || t('JRC_SERVICE_DESK.LIFECYCLE.unit_policy') }}</p>
              <Input v-if="!edit" v-model="draft.conversation_id" :label="t('JRC_SERVICE_DESK.OPS.conversation_id')" :disabled="!mayEdit || busy || unit?.permissions.link_conversation !== true" maxlength="19" />
              <p class="text-xs text-n-slate-11">{{ t('JRC_SERVICE_DESK.OPS.conversation_help') }}</p>
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
              <State status="pending" compact :description="t('JRC_SERVICE_DESK.TICKET.sla_pending')" />
            </div>
            <div class="sd-footer-actions">
              <Button
                type="button"
                color="slate"
                variant="outline"
                :label="t('JRC_SERVICE_DESK.COMMON.previous')"
                :disabled="step === 0"
                @click="step -= 1"
              />
              <Button v-if="step < 3" type="button" :label="t('JRC_SERVICE_DESK.COMMON.next')" @click="step += 1" />
              <Button v-else type="submit" :disabled="!maySave" :label="t(edit ? 'JRC_SERVICE_DESK.COMMON.save' : 'JRC_SERVICE_DESK.COMMON.create')" />
            </div>
          </form>
        </Panel>
        <Panel :title="t('JRC_SERVICE_DESK.FORM.summary')" class="sd-sticky">
          <dl class="sd-detail-list">
            <dt>
              {{ t('JRC_SERVICE_DESK.FIELDS.operator_company') }}
            </dt>
            <dd>
              {{ unit?.operator_company.name || t('JRC_SERVICE_DESK.COMMON.no_value') }}
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
          <State status="pending" compact :description="t('JRC_SERVICE_DESK.TICKET.sla_pending')" />
        </Panel>
      </div>
    </template>
  </section>
</template>
