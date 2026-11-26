<script setup>
import { useEndingAutomationLabels } from '../composables/useEndingAutomationLabels';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AcwRuleTarget from './AcwRuleTarget.vue';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import EndingProjectTaskConfiguration from './EndingProjectTaskConfiguration.vue';
import EndingCrmConfiguration from './EndingCrmConfiguration.vue';
import EndingServiceDeskConfiguration from './EndingServiceDeskConfiguration.vue';
import EndingRuleActivation from './EndingRuleActivation.vue';
import { useEndingAutomationEditor } from '../composables/useEndingAutomationEditor';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const text = useEndingAutomationLabels();
const editor = useEndingAutomationEditor({
  accountId: computed(() => props.accountId),
});
const {
  items,
  meta,
  q,
  status,
  page,
  draft,
  source,
  persisted,
  reasons,
  crmOptions,
  serviceDeskOptions,
  destinationPresentations,
  loading,
  saving,
  sourceLoading,
  error,
  reviewed,
  saved,
  dirty,
  canSave,
  revision,
  activationRevision,
} = editor;
const activationBusy = ref(false);
const taskConfiguration = ref(false);
const crmConfiguration = ref(false);
const serviceDeskConfiguration = ref(false);
const discard = ref('');
const conditions = computed({
  get: () => draft.value.conditions.outcome_codes.join('\n'),
  set: value => {
    draft.value.conditions.outcome_codes = value
      .split('\n')
      .map(code => code.trim())
      .filter(Boolean);
  },
});
const task = computed(() =>
  draft.value?.actions.find(action => action.kind === 'project_task')
);
const crm = computed(() =>
  draft.value?.actions.find(action => action.kind === 'crm')
);
const serviceDesk = computed(() =>
  draft.value?.actions.find(action => action.kind === 'service_desk')
);
const configured = kind =>
  draft.value?.actions.some(action => action.kind === kind);
const destinationAllowed = kind =>
  kind === 'project_task' ||
  (kind === 'crm' && crmOptions.value.configuration_available) ||
  (kind === 'service_desk' && serviceDeskOptions.value.configuration_available);
const destinationDescription = kind => {
  if (configured(kind)) return 'DESTINATION_CONFIGURED';
  if (destinationAllowed(kind)) return 'DESTINATION_AVAILABLE';
  return ['crm', 'service_desk', 'project_task'].includes(kind)
    ? 'DESTINATION_UNAVAILABLE'
    : 'DESTINATION_PENDING';
};
const configureDestination = kind => {
  if (kind === 'project_task') taskConfiguration.value = true;
  if (
    kind === 'service_desk' &&
    serviceDeskOptions.value.configuration_available
  )
    serviceDeskConfiguration.value = true;
  if (kind === 'crm' && crmOptions.value.configuration_available)
    crmConfiguration.value = true;
};
const locked = computed(
  () =>
    loading.value || saving.value || sourceLoading.value || activationBusy.value
);
const requestClose = () => {
  if (locked.value) return;
  if (dirty.value) discard.value = 'close';
  else emit('close');
};
const backToList = () => {
  if (locked.value) return;
  if (dirty.value) discard.value = 'list';
  else editor.discard();
};
const confirmDiscard = async () => {
  const target = discard.value;
  discard.value = '';
  await editor.discard();
  taskConfiguration.value = false;
  crmConfiguration.value = false;
  serviceDeskConfiguration.value = false;
  if (target === 'close') emit('close');
};
const applyTask = parameters => {
  draft.value.actions = [
    ...draft.value.actions.filter(action => action.kind !== 'project_task'),
    { kind: 'project_task', parameters },
  ];
  taskConfiguration.value = false;
};
const applyCrm = parameters => {
  draft.value.destination_schema_version = 2;
  draft.value.actions = [
    ...draft.value.actions.filter(action => action.kind !== 'crm'),
    { kind: 'crm', parameters },
  ];
  crmConfiguration.value = false;
};
const removeCrm = () => {
  draft.value.actions = draft.value.actions.filter(
    action => action.kind !== 'crm'
  );
  crmConfiguration.value = false;
};
const applyServiceDesk = parameters => {
  draft.value.destination_schema_version = 2;
  draft.value.actions = [
    ...draft.value.actions.filter(action => action.kind !== 'service_desk'),
    { kind: 'service_desk', parameters },
  ];
  serviceDeskConfiguration.value = false;
};
const removeServiceDesk = () => {
  draft.value.actions = draft.value.actions.filter(
    action => action.kind !== 'service_desk'
  );
  serviceDeskConfiguration.value = false;
};
// This is an explicit user choice. Opening a historical v1 rule never
// upgrades it, arms it, or grants consent for an individual attendance action.
const useManualFlow = () => {
  if (locked.value || !draft.value) return;
  draft.value.destination_schema_version = 2;
  reviewed.value = false;
};
const executionModeChanged = () => {
  reviewed.value = false;
  if (draft.value?.execution_mode === 'agent_confirmation') useManualFlow();
};
const destinations = [
  'crm',
  'service_desk',
  'project_task',
  'notifications',
  'nico',
];
</script>

<template>
  <section
    class="min-w-0 space-y-4 text-n-slate-12"
    data-ending-automation-editor
  >
    <h3 class="text-lg font-semibold">{{ text('TITLE') }}</h3>
    <p
      class="rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
      data-ending-configuration-only
    >
      {{ text('CONFIGURATION_ONLY') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
    >
      {{ text(error) }}
    </p>
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ text('LOADING') }}
    </p>
    <button
      v-if="error === 'LOAD_FAILED'"
      type="button"
      :disabled="loading"
      class="rounded-lg border border-n-weak px-3 py-2 text-sm"
      @click="editor.load()"
    >
      {{ text('RETRY') }}
    </button>
    <template v-if="error !== 'DENIED' && error !== 'LOAD_FAILED' && !loading">
      <EndingServiceDeskConfiguration
        v-if="
          draft &&
          serviceDeskConfiguration &&
          serviceDeskOptions.configuration_available
        "
        :key="`${accountId}:${source.scope_revision}`"
        :account-id="accountId"
        :value="serviceDesk?.parameters || null"
        :options="serviceDeskOptions"
        :labels="destinationPresentations[draft.code]?.service_desk || {}"
        :disabled="saving"
        @save="applyServiceDesk"
        @cancel="serviceDeskConfiguration = false"
        @remove="removeServiceDesk"
      />
      <EndingCrmConfiguration
        v-else-if="
          draft && crmConfiguration && crmOptions.configuration_available
        "
        :key="String(accountId)"
        :value="crm?.parameters || null"
        :options="crmOptions"
        :disabled="saving"
        @save="applyCrm"
        @cancel="crmConfiguration = false"
        @remove="removeCrm"
      />
      <EndingProjectTaskConfiguration
        v-else-if="draft && taskConfiguration"
        :key="String(accountId)"
        :account-id="accountId"
        :value="task?.parameters || null"
        :disabled="saving"
        @save="applyTask"
        @cancel="taskConfiguration = false"
        @denied="editor.deny"
      />
      <template v-else-if="draft">
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          resource="ending_rules"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="editor.reviewConflict"
        />
        <fieldset :disabled="locked" class="grid min-w-0 gap-3 sm:grid-cols-2">
          <label class="min-w-0 text-sm">
            {{ text('CODE') }}
            <input
              v-model="draft.code"
              :disabled="persisted"
              maxlength="100"
              required
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-rule-code
            />
          </label>
          <label class="min-w-0 text-sm">
            {{ text('NAME') }}
            <input
              v-model="draft.name"
              maxlength="120"
              required
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-rule-name
            />
          </label>
          <label class="min-w-0 text-sm">
            {{ text('REASON') }}
            <select
              v-model="draft.reason_code"
              required
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-rule-reason
            >
              <option value="">{{ text('SELECT') }}</option>
              <option
                v-for="reason in reasons"
                :key="reason.code"
                :value="reason.code"
              >
                {{ reason.name }} {{ text('SEPARATOR') }} {{ reason.code }}
              </option>
            </select>
          </label>
          <label class="min-w-0 text-sm">
            {{ text('TIMING') }}
            <select
              v-model="draft.timing"
              required
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-rule-timing
            >
              <option value="">{{ text('SELECT') }}</option>
              <option value="call_end">{{ text('TIMINGS.call_end') }}</option>
              <option value="acw_completed">
                {{ text('TIMINGS.acw_completed') }}
              </option>
            </select>
          </label>
          <label class="min-w-0 text-sm sm:col-span-2">
            {{ text('EXECUTION_MODE') }}
            <select
              v-model="draft.execution_mode"
              required
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-execution-mode
              @change="executionModeChanged"
            >
              <option value="">{{ text('MODE_REVIEW_REQUIRED') }}</option>
              <option value="automatic">{{ text('MODES.automatic') }}</option>
              <option value="agent_confirmation">
                {{ text('MODES.agent_confirmation') }}
              </option>
            </select>
          </label>
          <div class="min-w-0 sm:col-span-2">
            <p class="mb-2 text-sm font-semibold">{{ text('SOURCE_QUEUE') }}</p>
            <AcwRuleTarget
              :account-id="accountId"
              scope="queue"
              :model-value="draft.queue_id"
              :disabled="locked"
              @update:model-value="editor.selectQueue"
            />
            <p
              v-if="source"
              class="mt-2 break-words text-sm text-n-slate-11"
              data-ending-rule-source
            >
              {{ source.unit.name }} {{ text('SEPARATOR') }} {{ source.name }}
            </p>
            <p
              v-if="source && !source.configuration_available"
              role="alert"
              class="mt-2 text-sm text-n-amber-11"
            >
              {{ text('SOURCE_UNAVAILABLE') }}
            </p>
          </div>
          <label class="min-w-0 text-sm sm:col-span-2">
            {{ text('CONDITIONS') }}
            <textarea
              v-model="conditions"
              :disabled="draft.timing !== 'acw_completed'"
              maxlength="1010"
              rows="2"
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-rule-conditions
            />
            <span class="mt-1 block text-xs text-n-slate-11">{{
              text('CONDITIONS_HELP')
            }}</span>
          </label>
          <label class="flex items-start gap-2 text-sm sm:col-span-2">
            <input
              v-model="draft.active"
              type="checkbox"
              class="mt-1"
              data-ending-rule-active
            />
            <span>{{ text('ACTIVE') }}</span>
          </label>
        </fieldset>
        <p class="rounded-lg border border-n-weak p-3 text-sm text-n-slate-11">
          {{ text('DISABLE_BARRIER') }}
        </p>
        <div
          class="grid min-w-0 gap-3 sm:grid-cols-2"
          data-ending-rule-destinations
        >
          <section
            v-for="kind in destinations"
            :key="kind"
            class="min-w-0 rounded-xl border border-n-weak p-3"
            :class="destinationAllowed(kind) ? 'bg-n-blue-2' : 'bg-n-solid-2'"
          >
            <h4 class="break-words text-sm font-semibold">
              {{ text(`DESTINATIONS.${kind}`) }}
            </h4>
            <p
              class="my-2 break-words text-xs text-n-slate-11"
              :data-ending-destination-description="kind"
            >
              {{ text(destinationDescription(kind)) }}
            </p>
            <button
              type="button"
              :disabled="locked || !destinationAllowed(kind)"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-40"
              :data-ending-configure-destination="kind"
              @click="configureDestination(kind)"
            >
              {{ text('CONFIGURE') }}
            </button>
          </section>
        </div>
        <details
          v-if="draft.actions.length"
          class="min-w-0 rounded-lg border border-n-weak p-3 text-sm"
          data-ending-rule-preview
        >
          <summary>{{ text('PREVIEW') }}</summary>
          <pre class="mt-2 whitespace-pre-wrap break-all">{{
            JSON.stringify(draft, null, 2)
          }}</pre>
        </details>
        <label class="flex items-start gap-2 text-sm">
          <input
            v-model="reviewed"
            type="checkbox"
            :disabled="locked"
            class="mt-1"
            data-ending-rule-reviewed
          />
          <span>{{ text('REVIEW') }}</span>
        </label>
        <p
          v-if="saved && !dirty"
          role="status"
          class="text-sm text-n-teal-11"
          data-ending-rule-saved
        >
          {{ text('SAVED') }}
        </p>
        <EndingRuleActivation
          v-if="
            persisted &&
            !dirty &&
            draft.active &&
            (draft.execution_mode === 'automatic' ||
              (draft.destination_schema_version === 2 &&
                draft.execution_mode === 'agent_confirmation'))
          "
          :account-id="accountId"
          :rule="draft"
          :revision="activationRevision"
          :disabled="
            loading || saving || sourceLoading || revision.state.conflict
          "
          @busy="activationBusy = $event"
          @denied="editor.deny"
          @reload="editor.discard"
        />
        <section
          v-if="
            persisted &&
            !dirty &&
            draft.active &&
            draft.execution_mode === 'agent_confirmation' &&
            draft.destination_schema_version !== 2
          "
          class="rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
          data-ending-manual-activation-pending
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.MANUAL_PENDING') }}
          <span class="mt-2 block">{{
            t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.MANUAL_VERSION_HINT')
          }}</span>
          <button
            type="button"
            :disabled="locked"
            class="mt-3 max-w-full whitespace-normal rounded-lg border border-n-amber-7 px-3 py-2 text-sm disabled:opacity-40"
            data-enable-ending-manual-flow
            @click="useManualFlow"
          >
            {{
              t('JRC_CONTACT_CENTER.ENDING_ACTIVATION.MANUAL_VERSION_REVIEW')
            }}
          </button>
        </section>
        <div class="flex flex-wrap gap-3">
          <button
            type="button"
            :disabled="!canSave"
            class="rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
            data-ending-rule-save
            @click="editor.save"
          >
            {{ text('SAVE') }}
          </button>
          <button
            type="button"
            :disabled="locked"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm"
            data-ending-rule-back
            @click="backToList"
          >
            {{ text('BACK') }}
          </button>
        </div>
      </template>
      <template v-else>
        <form
          class="grid min-w-0 gap-3 sm:grid-cols-3"
          data-ending-rule-filters
          @submit.prevent="editor.load(1)"
        >
          <label class="min-w-0 text-sm">
            <span>{{ text('SEARCH') }}</span>
            <input
              v-model="q"
              maxlength="100"
              type="search"
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-rule-search
            />
          </label>
          <label class="min-w-0 text-sm">
            <span>{{ text('STATUS') }}</span>
            <select
              v-model="status"
              class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-ending-rule-status
            >
              <option value="all">{{ text('ALL') }}</option>
              <option value="active">{{ text('ACTIVE') }}</option>
              <option value="inactive">{{ text('INACTIVE') }}</option>
            </select>
          </label>
          <button
            type="submit"
            :disabled="locked"
            class="self-end rounded-lg border border-n-weak px-3 py-2 text-sm"
          >
            {{ text('FILTER') }}
          </button>
        </form>
        <button
          type="button"
          :disabled="locked"
          class="rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
          data-ending-rule-new
          @click="editor.edit(null)"
        >
          {{ text('ADD') }}
        </button>
        <p v-if="!items.length" class="text-sm text-n-slate-11">
          {{ text('EMPTY') }}
        </p>
        <article
          v-for="row in items"
          :key="row.code"
          class="min-w-0 rounded-xl border border-n-weak p-3"
          data-ending-rule-entry
        >
          <h4 class="break-words text-sm font-semibold">{{ row.name }}</h4>
          <p class="mt-1 break-words text-xs text-n-slate-11">
            {{ row.code }} {{ text('SEPARATOR') }}
            {{ text(row.active ? 'ACTIVE' : 'INACTIVE') }}
            {{ text('SEPARATOR') }}
            {{ text(`TIMINGS.${row.timing}`) }}
          </p>
          <p v-if="!row.execution_mode" class="my-2 text-xs text-n-amber-11">
            {{ text('MODE_REVIEW_REQUIRED') }}
          </p>
          <button
            type="button"
            :disabled="locked"
            class="mt-2 rounded-lg border border-n-weak px-3 py-2 text-sm"
            data-ending-rule-edit
            @click="editor.edit(row)"
          >
            {{ text('EDIT') }}
          </button>
        </article>
        <div class="flex flex-wrap items-center gap-3 text-sm">
          <button
            type="button"
            :disabled="locked || page <= 1"
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
            data-ending-rule-previous
            @click="editor.load(page - 1)"
          >
            {{ text('PREVIOUS') }}
          </button>
          <span>{{
            t('JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.PAGINATION', {
              page,
              pages: Math.max(1, meta.pages),
              total: meta.total,
            })
          }}</span>
          <button
            type="button"
            :disabled="locked || page >= meta.pages"
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-40"
            data-ending-rule-next
            @click="editor.load(page + 1)"
          >
            {{ text('NEXT') }}
          </button>
        </div>
      </template>
    </template>
    <div
      v-if="discard"
      class="space-y-3 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-sm"
      data-ending-automation-discard
    >
      <p>{{ text('DISCARD') }}</p>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2"
        @click="discard = ''"
      >
        {{ text('STAY') }}
      </button>
      <button
        type="button"
        class="ml-2 rounded-lg border border-n-ruby-6 px-3 py-2"
        data-ending-automation-discard-confirm
        @click="confirmDiscard"
      >
        {{ text('DISCARD_CONFIRM') }}
      </button>
    </div>
    <button
      v-if="!taskConfiguration"
      type="button"
      :disabled="locked"
      class="rounded-lg border border-n-weak px-3 py-2 text-sm"
      data-ending-automation-close
      @click="requestClose"
    >
      {{ text('CLOSE') }}
    </button>
  </section>
</template>
