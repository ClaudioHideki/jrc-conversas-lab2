<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import { useServiceDesk } from '../composables/useServiceDesk';
import { createTicketDraft, newRequestKey } from '../helpers/drafts';
import { confirmedCreationTicket } from '../helpers/ticketReceipt';
import {
  intakeErrorKey,
  ticketTypePreferenceKey,
} from '../helpers/quickIntake';
import { canonicalId } from '../helpers/access';
import LookupSelect from './LookupSelect.vue';
import RequesterSelect from './RequesterSelect.vue';
import ScopeBar from './ScopeBar.vue';
import CatalogueAnswers from './CatalogueAnswers.vue';
import TicketCreationReceipt from './TicketCreationReceipt.vue';
import WriteFeedback from './WriteFeedback.vue';

const props = defineProps({ initialDraft: { type: Object, default: null } });
const emit = defineEmits(['advanced', 'cancel', 'open']);
const { t } = useI18n();
const session = useServiceDesk();
const { canAccess } = useCustomerMaster();
const master = computed(
  () =>
    canAccess.value &&
    session.state.context?.effective_permissions?.includes(
      'jrc_service_desk_customers_view'
    )
);
const units = computed(() =>
  (session.state.context?.units || []).filter(
    row => row.permissions.create_ticket
  )
);
const blank = () => ({
  unit_id: '',
  company_id: null,
  requester_id: '',
  title: '',
  description: '',
  priority_id: '',
  ticket_type_id: '',
  service_fields: {},
  assignee_id: '',
  team_id: '',
  queue_id: '',
});
const draft = reactive(blank());
const operator = ref('');
const selectedRequester = ref(null);
const selectedPriority = ref(null);
const selectedType = ref(null);
const receipt = ref(null);
const defaultsVersion = ref(0);
const key = 'ticket:quick:write';
const priorityKey = 'ticket:quick:normal';
const unit = computed(() => units.value.find(row => row.id === draft.unit_id));
const mutation = computed(
  () => session.operations?.mutation(key) || { status: 'idle' }
);
const busy = computed(() => mutation.value.status === 'saving');
const locked = computed(
  () =>
    busy.value ||
    ['readback_pending', 'error', 'invalid_contract'].includes(
      mutation.value.status
    )
);
const creatingPerson = ref(false);
const rememberType = ref(false);
const catalogueReady = ref(true);
const created = computed(() =>
  confirmedCreationTicket(
    receipt.value,
    session.state,
    session.accountId.value,
    session.userId.value
  )
);
const specificError = computed(() => intakeErrorKey(mutation.value));
let requestKey = null;
let epoch = 0;
let restoredDraft = null;
const reset = (restore = false) => {
  epoch += 1;
  Object.assign(draft, blank());
  selectedRequester.value = null;
  receipt.value = null;
  requestKey = null;
  session.operations?.dismissConfirmation(key);
  const candidates = units.value;
  if (candidates.length === 1) {
    draft.unit_id = candidates[0].id;
    operator.value = candidates[0].operator_company.id;
  }
  restoredDraft = null;
  const seed = props.initialDraft;
  if (
    restore &&
    seed?.draft &&
    seed?.account_id === session.state.context?.account_id &&
    seed?.user_id === session.state.context?.user_id &&
    (!seed.draft.unit_id ||
      candidates.some(row => row.id === seed.draft.unit_id))
  ) {
    Object.assign(draft, seed.draft, {
      unit_id: seed.draft.unit_id || draft.unit_id,
      service_fields: { ...seed.draft.service_fields },
    });
    selectedRequester.value = seed.requester ? { ...seed.requester } : null;
    restoredDraft = { ...draft };
  }
  defaultsVersion.value += 1;
};
watch(
  () => session.state.context,
  () => reset(true),
  { immediate: true }
);
watch(
  () => props.initialDraft,
  () => {
    if (!locked.value) reset(true);
  }
);
const changeUnit = id => {
  if (!locked.value && id !== draft.unit_id) {
    reset();
    draft.unit_id = id;
  }
};
watch(
  [() => draft.unit_id, defaultsVersion],
  async ([id]) => {
    const turn = epoch;
    const restored = restoredDraft;
    restoredDraft = null;
    draft.priority_id = '';
    draft.ticket_type_id = '';
    selectedPriority.value = null;
    selectedType.value = null;
    draft.service_fields = {};
    rememberType.value = false;
    catalogueReady.value = true;
    if (!id) return;
    const context = session.state.context;
    // A normal priority must exist in the official unit catalogue; never invent it.
    await session.load(priorityKey, 'priorities', {
      unit_id: id,
      q: 'normal',
      per_page: 20,
    });
    if (
      turn !== epoch ||
      context !== session.state.context ||
      id !== draft.unit_id
    )
      return;
    const normal = session
      .resource(priorityKey)
      .items.filter(
        row =>
          row.code?.toLowerCase() === 'normal' ||
          row.name?.toLowerCase() === 'normal'
      );
    if (normal.length === 1) {
      draft.priority_id = normal[0].id;
      selectedPriority.value = normal[0];
    }
    try {
      const saved = localStorage.getItem(ticketTypePreferenceKey(context, id));
      if (canonicalId(saved)) draft.ticket_type_id = canonicalId(saved);
    } catch {
      /* A browser preference is optional and never establishes permission. */
    }
    if (restored)
      Object.assign(draft, restored, {
        priority_id: restored.priority_id || draft.priority_id,
        service_fields: { ...restored.service_fields },
      });
  },
  { immediate: true }
);
watch(
  () => draft.ticket_type_id,
  () => {
    catalogueReady.value = !draft.ticket_type_id;
  }
);
const maySave = computed(
  () =>
    !!session.operations &&
    !!unit.value?.initial_status?.id &&
    !!draft.requester_id &&
    !!draft.title.trim() &&
    !!draft.description.trim() &&
    !!draft.priority_id &&
    catalogueReady.value &&
    !locked.value &&
    !creatingPerson.value
);
const submit = async () => {
  if (
    !maySave.value &&
    !['readback_pending', 'error', 'invalid_contract'].includes(
      mutation.value.status
    )
  )
    return;
  if (busy.value || !unit.value) return;
  const context = session.state.context;
  requestKey ||= newRequestKey();
  const payload = createTicketDraft(
    draft,
    unit.value,
    requestKey,
    master.value
  );
  const confirmed = await session.operations.write(key, 'create', payload);
  if (!confirmed || context !== session.state.context) return;
  receipt.value = {
    ticket: confirmed,
    account_id: context.account_id,
    user_id: context.user_id,
  };
  if (rememberType.value) {
    try {
      const preference = ticketTypePreferenceKey(context, draft.unit_id);
      if (draft.ticket_type_id)
        localStorage.setItem(preference, draft.ticket_type_id);
      else localStorage.removeItem(preference);
    } catch {
      /* Ticket persistence does not depend on browser storage. */
    }
  }
};
onBeforeUnmount(() => {
  epoch += 1;
  session.resetResource(priorityKey);
  session.operations?.cancel(key);
});
defineExpose({ busy: locked });
</script>

<template>
  <section data-testid="quick-ticket-form" class="mx-auto max-w-4xl space-y-4">
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 id="sd-ticket-form-title" class="sd-page-title">
          {{ t('JRC_SERVICE_DESK.SCREENS.new') }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.QUICK.subtitle') }}
        </p>
      </div>
      <Button
        variant="ghost"
        color="slate"
        :label="t('JRC_SERVICE_DESK.QUICK.advanced')"
        :disabled="locked || creatingPerson"
        @click="
          emit('advanced', {
            draft: { ...draft, service_fields: { ...draft.service_fields } },
            requester: selectedRequester,
          })
        "
      />
    </header>
    <TicketCreationReceipt
      v-if="created"
      :ticket="created"
      @open="emit('open', $event)"
      @list="emit('cancel')"
      @create-another="reset"
    />
    <form
      v-else
      class="grid gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 sm:p-6"
      @submit.prevent="submit"
    >
      <ScopeBar
        v-if="units.length !== 1"
        v-model:operator-id="operator"
        :unit-id="draft.unit_id"
        required
        :disabled="locked"
        @update:unit-id="changeUnit"
      />
      <p v-else class="m-0 text-xs text-n-slate-11">
        {{ unit?.operator_company.name }} / {{ unit?.name }}
      </p>
      <p
        v-if="unit && !unit.initial_status"
        role="alert"
        class="text-sm text-n-amber-11"
      >
        {{ t('JRC_SERVICE_DESK.FORM.initial_status_required') }}
      </p>
      <div v-if="master" class="grid gap-1">
        <p class="m-0 text-sm font-medium">
          {{ t('JRC_SERVICE_DESK.COMMON.client_company') }}
        </p>
        <CompanyPicker
          v-model="draft.company_id"
          :disabled="locked || creatingPerson || !unit"
        />
      </div>
      <RequesterSelect
        v-model="draft.requester_id"
        :company-id="draft.company_id"
        :unit-id="draft.unit_id"
        :current-name="selectedRequester?.name || ''"
        :current-phone="selectedRequester?.phone_number || ''"
        :disabled="locked || !unit"
        @selected="selectedRequester = $event"
        @busy="creatingPerson = $event"
      />
      <Input
        v-model="draft.title"
        :label="t('JRC_SERVICE_DESK.FIELDS.title')"
        maxlength="255"
        :disabled="locked"
      />
      <TextArea
        id="sd-quick-description"
        custom-text-area-class="min-h-24"
        v-model="draft.description"
        :label="t('JRC_SERVICE_DESK.FIELDS.description')"
        :max-length="20000"
        resize
        :disabled="locked"
      />
      <div class="grid gap-4 sm:grid-cols-2">
        <LookupSelect
          v-model="draft.priority_id"
          resource="priorities"
          compact
          :unit-id="draft.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.priority')"
          :current-name="selectedPriority?.name || ''"
          :disabled="locked || !unit"
          @selected="selectedPriority = $event"
        />
        <LookupSelect
          v-model="draft.ticket_type_id"
          resource="ticket_types"
          compact
          :unit-id="draft.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.ticket_type')"
          :current-name="selectedType?.name || ''"
          :disabled="locked || !unit"
          @selected="selectedType = $event"
        />
      </div>
      <div v-if="unit?.permissions.assign_ticket" class="grid gap-2">
        <LookupSelect
          v-model="draft.assignee_id"
          resource="assignees"
          compact
          :unit-id="draft.unit_id"
          :team-id="draft.team_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
          :disabled="locked || !unit"
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REQUESTERS.agent_help') }}
        </p>
      </div>
      <label class="flex items-start gap-2 text-sm"
        ><input
          v-model="rememberType"
          type="checkbox"
          :disabled="locked || !unit"
        /><span>{{ t('JRC_SERVICE_DESK.QUICK.remember_type') }}</span></label
      >
      <CatalogueAnswers
        v-if="
          draft.ticket_type_id ||
          draft.service_id ||
          draft.category_id ||
          draft.subcategory_id
        "
        v-model="draft.service_fields"
        :unit-id="draft.unit_id"
        :ticket-type-id="draft.ticket_type_id"
        :service-id="draft.service_id || ''"
        :category-id="draft.category_id || ''"
        :subcategory-id="draft.subcategory_id || ''"
        :disabled="locked"
        @ready="catalogueReady = $event"
        @catalogue="selectedType = $event?.ticket_type || null"
      />
      <p v-if="specificError" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ t(specificError) }}
      </p>
      <WriteFeedback v-else :status="mutation.status" />
      <div
        class="sticky bottom-0 z-10 flex flex-wrap justify-end gap-2 border-t border-n-weak bg-n-solid-1 py-3"
      >
        <Button
          type="button"
          variant="ghost"
          color="slate"
          :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
          :disabled="locked || creatingPerson"
          @click="emit('cancel')"
        />
        <Button
          v-if="
            ['readback_pending', 'error', 'invalid_contract'].includes(
              mutation.status
            )
          "
          type="button"
          :label="t('JRC_SERVICE_DESK.QUICK.recover_creation')"
          :disabled="busy"
          @click="submit"
        />
        <Button
          v-else
          type="submit"
          :label="t('JRC_SERVICE_DESK.COMMON.create')"
          :disabled="!maySave"
        />
      </div>
    </form>
  </section>
</template>
