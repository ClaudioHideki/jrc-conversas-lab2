<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
import { playbookFlowLabels } from './playbookFlowLabels';

const props = defineProps({ book: { type: Object, required: true } });
const emit = defineEmits(['updateStep', 'executed']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const reasonLabel = computed(() => playbookFlowLabels(t));
const options = ref({
  assignments: [],
  flows: [],
  contacts: [],
  conversations: [],
});
const assignmentId = ref('');
const preview = ref(null);
const error = ref('');
const busy = ref(false);
const execution = ref(null);
const sourceKey = ref('');
const requestId = ref('');
const flows = computed(() =>
  props.book.steps
    .map((step, index) => ({ step, index }))
    .filter(({ step }) => step.kind === 'flow')
);
let generation = 0;
let previewGeneration = 0;
let approvalTimer;
const clearApproval = () => {
  window.clearTimeout(approvalTimer);
  preview.value = null;
  sourceKey.value = '';
  requestId.value = '';
};
const approvalSteps = computed(() =>
  (preview.value?.steps || []).filter(step => step.kind === 'flow')
);
const canRun = computed(
  () =>
    props.book.id &&
    props.book.active === true &&
    preview.value?.matched === true &&
    approvalSteps.value.length > 0 &&
    approvalSteps.value.every(
      step =>
        step.approval_token &&
        !step.reason &&
        Number.isFinite(Date.parse(step.approval_expires_at)) &&
        Date.parse(step.approval_expires_at) > Date.now()
    )
);
const load = async () => {
  generation += 1;
  const version = generation;
  previewGeneration += 1;
  busy.value = false;
  clearApproval();
  execution.value = null;
  error.value = '';
  try {
    const { data } = await API.playbookOptions(route.params.accountId, {
      assignment_id: assignmentId.value || undefined,
    });
    if (version === generation) options.value = data;
  } catch (err) {
    if (version === generation) error.value = message(err);
  }
};
const update = (index, attrs) =>
  emit('updateStep', index, { ...props.book.steps[index], ...attrs });
const chooseFlow = (index, id) => {
  const flow = options.value.flows.find(row => String(row.id) === id);
  update(index, {
    flow_id: flow?.id || null,
    flow_lock_version: flow?.flow_lock_version ?? null,
    flow_digest: flow?.flow_digest || '',
    after_days: 0,
  });
};
const chooseContact = (index, id) =>
  update(index, {
    contact_id: Number(id) || null,
    conversation_id: null,
    message_id: undefined,
  });
const chooseMessage = (index, text) => {
  const step = { ...props.book.steps[index] };
  delete step.message_id;
  if (text !== '') {
    if (!/^[1-9]\d*$/.test(text) || !Number.isSafeInteger(Number(text))) {
      error.value = t('RELATIONSHIP.PLAYBOOK_PREVIEW.INVALID_MESSAGE');
      return;
    }
    step.message_id = Number(text);
  }
  emit('updateStep', index, step);
};
const simulate = async () => {
  const version = generation;
  previewGeneration += 1;
  const previewVersion = previewGeneration;
  busy.value = true;
  clearApproval();
  error.value = '';
  sourceKey.value = `preview:${crypto.randomUUID()}`;
  requestId.value = crypto.randomUUID();
  try {
    const { data } = await API.previewPlaybook(route.params.accountId, {
      id: props.book.id,
      assignment_id: Number(assignmentId.value),
      source_key: sourceKey.value,
      playbook: props.book,
    });
    if (version === generation && previewVersion === previewGeneration) {
      preview.value = data;
      const expiries = approvalSteps.value
        .map(step => Date.parse(step.approval_expires_at))
        .filter(Number.isFinite);
      if (expiries.length)
        approvalTimer = window.setTimeout(
          () => {
            clearApproval();
            error.value = t('RELATIONSHIP.PLAYBOOK_PREVIEW.EXPIRED');
          },
          Math.max(0, Math.min(...expiries) - Date.now())
        );
    }
  } catch (err) {
    if (version === generation && previewVersion === previewGeneration)
      error.value = message(err);
  } finally {
    if (version === generation && previewVersion === previewGeneration)
      busy.value = false;
  }
};
const run = async () => {
  if (busy.value || !canRun.value) return;
  const version = generation;
  const reviewVersion = previewGeneration;
  const current = () =>
    version === generation && reviewVersion === previewGeneration;
  const account = route.params.accountId;
  const assignment = Number(assignmentId.value);
  const origin = sourceKey.value;
  const bookId = props.book.id;
  const publishedVersion = preview.value.version;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.portfolioBatch(account, [assignment], {
      operation: 'playbook',
      playbook_id: bookId,
      request_id: requestId.value,
      source_key: origin,
      flow_approvals: Object.fromEntries(
        approvalSteps.value.map(step => [step.step_key, step.approval_token])
      ),
    });
    if (!current()) return;
    if (data.updated !== 1)
      throw new Error(t('RELATIONSHIP.PLAYBOOK_PREVIEW.UNVERIFIED'));
    const { data: readback } = await API.playbookExecutions(account);
    if (!current()) return;
    const row = readback.payload.find(
      item =>
        item.assignment_id === assignment &&
        item.playbook_id === bookId &&
        item.version === publishedVersion &&
        item.source_key === origin
    );
    if (!row) throw new Error(t('RELATIONSHIP.PLAYBOOK_PREVIEW.UNVERIFIED'));
    execution.value = row;
    clearApproval();
    emit('executed', row.id);
  } catch (err) {
    if (current()) error.value = message(err);
  } finally {
    if (current()) busy.value = false;
  }
};
watch(assignmentId, () => {
  flows.value.forEach(({ index }) =>
    update(index, {
      contact_id: null,
      conversation_id: null,
      business_unit_id: null,
      message_id: undefined,
    })
  );
  load();
});
watch(
  () => props.book,
  () => {
    previewGeneration += 1;
    busy.value = false;
    clearApproval();
    execution.value = null;
  },
  { deep: true }
);
watch(
  [() => route.params.accountId, () => store.getters.getCurrentUserID],
  () => {
    assignmentId.value = '';
    options.value = {
      assignments: [],
      flows: [],
      contacts: [],
      conversations: [],
    };
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  previewGeneration += 1;
  clearApproval();
});
</script>

<template>
  <section class="mt-4 space-y-3 rounded-lg border border-n-weak p-4">
    <h3>{{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.TITLE') }}</h3>
    <p class="text-sm">{{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.GUIDANCE') }}</p>
    <label class="block text-sm">
      {{ t('RELATIONSHIP.FIELDS.customer') }}
      <select
        v-model="assignmentId"
        :class="inputClass"
        data-testid="preview-assignment"
      >
        <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
        <option
          v-for="row in options.assignments"
          :key="row[0]"
          :value="row[0]"
        >
          {{ row[1] }}
        </option>
      </select>
    </label>
    <fieldset
      v-for="{ step, index } in flows"
      :key="step.step_key || index"
      class="space-y-2 rounded border border-n-weak p-3"
    >
      <legend>{{ step.title }}</legend>
      <label class="block text-sm">
        {{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.FLOW') }}
        <select
          :value="step.flow_id || ''"
          :class="inputClass"
          @change="chooseFlow(index, $event.target.value)"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="flow in options.flows"
            :key="flow.id"
            :value="flow.id"
          >
            {{ flow.name }} · {{ flow.flow_lock_version }}
          </option>
        </select>
      </label>
      <label class="block text-sm">
        {{ t('RELATIONSHIP.FIELDS.contact_id') }}
        <select
          :value="step.contact_id || ''"
          :class="inputClass"
          @change="chooseContact(index, $event.target.value)"
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="row in options.contacts"
            :key="row[0]"
            :value="row[0]"
          >
            {{ row[1] }}
          </option>
        </select>
      </label>
      <label class="block text-sm">
        {{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.CONVERSATION') }}
        <select
          :value="step.conversation_id || ''"
          :class="inputClass"
          @change="
            update(index, {
              conversation_id: Number($event.target.value) || null,
              business_unit_id: options.business_unit_id || null,
              message_id: undefined,
            })
          "
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="row in (options.conversations || []).filter(
              item => item.contact_id === step.contact_id
            )"
            :key="row.id"
            :value="row.id"
          >
            #{{ row.display_id }}
          </option>
        </select>
      </label>
      <label class="block text-sm">
        {{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.MESSAGE_ID') }}
        <input
          :value="step.message_id || ''"
          type="number"
          min="1"
          step="1"
          :class="inputClass"
          :required="
            options.flows.find(flow => flow.id === step.flow_id)
              ?.keyword_required === true
          "
          :disabled="!step.conversation_id"
          data-testid="flow-message-id"
          @change="chooseMessage(index, $event.target.value)"
        />
        <span class="text-xs text-n-slate-11">{{
          t('RELATIONSHIP.PLAYBOOK_PREVIEW.MESSAGE_GUIDANCE')
        }}</span>
      </label>
      <p class="break-all text-xs">
        {{
          t('RELATIONSHIP.PLAYBOOK_PREVIEW.DEFINITION', {
            version: step.flow_lock_version,
            digest: step.flow_digest,
          })
        }}
      </p>
    </fieldset>
    <button
      type="button"
      :class="buttonClass"
      :disabled="busy || !assignmentId || !book.steps.length"
      @click="simulate"
    >
      {{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.SIMULATE') }}
    </button>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <div
      v-if="preview"
      role="status"
    >
      <p>
        {{ t(`RELATIONSHIP.STATES.${preview.state}`) }} ·
        {{ reasonLabel(preview.reason) }}
      </p>
      <ul>
        <li
          v-for="step in preview.steps"
          :key="step.step_key"
        >
          {{ t(`RELATIONSHIP.PLAYBOOK_STEPS.${step.kind}`) }} ·
          {{ t(`RELATIONSHIP.STATES.${step.state}`) }} ·
          {{ reasonLabel(step.reason) }}
          <span
            v-for="dependency in step.dependencies || []"
            :key="dependency"
            class="ml-2"
            >{{ reasonLabel(dependency) }}</span
          >
        </li>
      </ul>
      <button
        v-if="canRun"
        type="button"
        :class="buttonClass"
        :disabled="busy"
        data-testid="run-approved-playbook"
        @click="run"
      >
        {{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.RUN') }}
      </button>
    </div>
    <p
      v-if="execution"
      role="status"
    >
      {{ t('RELATIONSHIP.PLAYBOOK_PREVIEW.VERIFIED', { id: execution.id }) }}
    </p>
  </section>
</template>
