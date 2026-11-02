<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import LifecycleAPI from 'dashboard/api/serviceDeskLifecycle';
import { useServiceDesk } from '../composables/useServiceDesk';
import {
  createLifecycleSession,
  createLifecycleState,
} from '../helpers/lifecycle';
import { closureFieldsValid } from '../helpers/closurePresentation';
import {
  closureCommand,
  requiredClosureFields,
} from '../helpers/closureWorkflow';
import { newRequestKey } from '../helpers/drafts';
import State from './ServiceDeskState.vue';

const props = defineProps({ ticket: { type: Object, required: true } });
const emit = defineEmits(['updated', 'busyChange', 'cancel', 'refresh']);
const { t } = useI18n();
const session = useServiceDesk();
const state = reactive(createLifecycleState());
const lifecycle = createLifecycleSession(
  LifecycleAPI,
  () => (session.state.status === 'ready' ? session.state.context : null),
  state
);
const currentTicket = ref(props.ticket);
const selected = ref('');
const saving = ref(false);
const pending = ref(null);
const completed = ref(0);
const failure = ref('');
const draft = reactive({
  reason: '',
  solution: '',
  note: '',
  evidence: '',
  fields: {},
});
const plans = computed(() => state.data?.closure_options || []);
const plan = computed(() =>
  plans.value.find(row => row.key === selected.value)
);
const fields = computed(() => requiredClosureFields(plan.value));
const needs = name => plan.value?.steps.some(step => step.requirements[name]);
const unavailable = computed(
  () =>
    state.data?.closure_unavailable_reason ||
    state.data?.unavailable_reason ||
    'closure_unavailable'
);
const protectedContent = computed(
  () => currentTicket.value.permissions.view_notes === true
);
const valid = computed(
  () =>
    !!plan.value &&
    protectedContent.value &&
    !!draft.reason.trim() &&
    draft.reason.length <= 4000 &&
    plan.value.steps.every(step =>
      closureFieldsValid(
        step,
        {
          note: draft.note,
          solution: draft.solution,
          evidence: draft.evidence,
          fields: {
            ...(step.requirements.fields?.closing_reason?.type === 'text' &&
            !Object.hasOwn(step.requirements.fields.closing_reason, 'equals')
              ? { closing_reason: draft.reason }
              : {}),
            ...Object.fromEntries(
              fields.value
                .filter(row => row.rules.includes(step.key))
                .map(row => [row.key, draft.fields[row.input]])
            ),
          },
        },
        protectedContent.value
      )
    ) &&
    (!needs('classification') || !!currentTicket.value.category)
);
watch(
  [saving, pending],
  () => emit('busyChange', saving.value || !!pending.value),
  { immediate: true }
);
watch(plans, rows => {
  if (
    !saving.value &&
    !pending.value &&
    !rows.some(row => row.key === selected.value)
  )
    selected.value = rows.length === 1 ? rows[0].key : '';
});
watch(
  [() => props.ticket.id, () => session.state.context],
  () => {
    lifecycle.clear();
    currentTicket.value = props.ticket;
    pending.value = null;
    completed.value = 0;
    selected.value = '';
    failure.value = '';
    Object.assign(draft, {
      reason: '',
      solution: '',
      note: '',
      evidence: '',
      fields: {},
    });
    if (session.state.status === 'ready') lifecycle.load(currentTicket.value);
  },
  { immediate: true }
);
const run = async () => {
  if (saving.value || !pending.value) return;
  saving.value = true;
  failure.value = '';
  const operation = pending.value;
  const next = async () => {
    if (operation.context !== session.state.context) return undefined;
    if (operation.index === operation.steps.length) {
      pending.value = null;
      if (session.operations) session.operations.state.revision += 1;
      emit('updated', currentTicket.value);
      return undefined;
    }
    const stage = operation.steps[operation.index];
    if (!stage.command) {
      const rule = state.data?.options.find(
        row =>
          row.key === stage.rule.key &&
          row.action === stage.rule.action &&
          row.to_status_id === stage.rule.to_status_id
      );
      if (!rule || state.data.policy?.id !== operation.policy) {
        pending.value = null;
        failure.value = 'closure_unavailable';
        return undefined;
      }
      stage.command = closureCommand(
        rule,
        state.data,
        operation.draft,
        operation.fields
      );
    }
    const confirmed = await lifecycle.apply(
      currentTicket.value,
      stage.command,
      stage.key
    );
    if (operation.context !== session.state.context) return undefined;
    if (!confirmed) {
      if (state.status === 'denied') {
        pending.value = null;
        Object.assign(draft, {
          solution: '',
          reason: '',
          note: '',
          evidence: '',
          fields: {},
        });
        emit('refresh');
      }
      if (
        ['denied', 'invalid_input', 'dependency', 'conflict'].includes(
          state.writeStatus
        )
      )
        pending.value = null;
      failure.value = state.writeStatus;
      return undefined;
    }
    currentTicket.value = confirmed;
    operation.index += 1;
    completed.value += 1;
    return next();
  };
  try {
    await next();
  } finally {
    saving.value = false;
    if (!pending.value && plans.value.length === 1)
      selected.value = plans.value[0].key;
  }
};
const submit = () => {
  if (!valid.value || saving.value || pending.value) return undefined;
  const request = newRequestKey();
  pending.value = {
    context: session.state.context,
    policy: state.data.policy.id,
    index: 0,
    fields: fields.value,
    draft: { ...draft, fields: { ...draft.fields } },
    steps: plan.value.steps.map((rule, index) => ({
      rule,
      key: `${request}:${index}`,
      command: null,
    })),
  };
  return run();
};
const cancel = () => {
  if (saving.value || pending.value) return;
  if (completed.value) {
    if (session.operations) session.operations.state.revision += 1;
    emit('updated', currentTicket.value);
  } else emit('cancel');
};
onBeforeUnmount(() => {
  lifecycle.clear();
  emit('busyChange', false);
});
</script>

<template>
  <div data-testid="simple-closure" class="grid gap-4">
    <template v-if="state.status !== 'ready'">
      <State
        :status="state.status"
        :retry="state.status === 'error'"
        @retry="lifecycle.load(currentTicket)"
      />
      <Button
        v-if="state.status === 'denied'"
        type="button"
        variant="ghost"
        color="slate"
        :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
        @click="cancel"
      />
    </template>
    <template v-else>
      <p
        v-if="state.data?.closure_revision"
        class="text-sm text-n-blue-11"
        data-testid="effective-closure-revision"
      >
        {{
          t(
            state.data.closure_revision.active
              ? 'JRC_SERVICE_DESK.CLOSURE_REVISION.applied_notice'
              : 'JRC_SERVICE_DESK.CLOSURE_REVISION.inactive_notice',
            {
              revision: state.data.closure_revision.target_version,
              original: state.data.policy.version,
            }
          )
        }}
      </p>
      <p
        v-if="state.data?.measurement?.result === 'unavailable'"
        class="m-0 text-sm text-n-amber-11"
      >
        {{
          t(
            `JRC_SERVICE_DESK.SIMPLE_SLA.pending.${state.data.measurement.pending_reason || 'result_unavailable'}`
          )
        }}
        {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.result_unavailable') }}
      </p>
      <p
        v-if="completed && failure"
        role="alert"
        class="m-0 rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11"
      >
        {{ t('JRC_SERVICE_DESK.QUICK.partial_closure') }}
      </p>
      <p v-if="!plans.length" role="alert" class="m-0 text-sm text-n-amber-11">
        {{ t(`JRC_SERVICE_DESK.QUICK.${unavailable}`) }}
      </p>
      <form v-else class="grid gap-4" @submit.prevent="submit">
        <Select
          v-if="plans.length > 1"
          v-model="selected"
          :disabled="saving || !!pending"
          :placeholder="t('JRC_SERVICE_DESK.LIFECYCLE.choose_action')"
          :options="
            plans.map(row => ({
              value: row.key,
              label: row.steps.map(step => step.to_status_name).join(' → '),
            }))
          "
        />
        <TextArea
          id="sd-close-reason"
          v-model="draft.reason"
          :label="t('JRC_SERVICE_DESK.SIMPLE_SLA.closing_reason')"
          :max-length="4000"
          custom-text-area-class="min-h-24"
          :disabled="saving || !!pending"
        />
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.closing_help') }}
        </p>
        <p
          v-if="
            needs('note') ||
            needs('solution') ||
            needs('classification') ||
            needs('evidence') ||
            fields.length
          "
          class="m-0 text-sm text-n-amber-11"
        >
          {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.specific_requirements') }}
        </p>
        <TextArea
          v-if="needs('solution')"
          id="sd-close-resolution"
          custom-text-area-class="min-h-24"
          v-model="draft.solution"
          :label="t('JRC_SERVICE_DESK.QUICK.resolution')"
          :max-length="20000"
          resize
          :disabled="saving || !!pending"
        />
        <TextArea
          v-if="needs('note')"
          id="sd-close-diagnosis"
          v-model="draft.note"
          :label="t('JRC_SERVICE_DESK.QUICK.required_diagnosis')"
          :max-length="20000"
          :disabled="saving || !!pending"
        />
        <Input
          v-if="needs('evidence')"
          v-model="draft.evidence"
          :label="t('JRC_SERVICE_DESK.QUICK.required_evidence')"
          :disabled="saving || !!pending"
        />
        <p
          v-if="needs('classification') && !currentTicket.category"
          role="alert"
          class="m-0 text-sm text-n-amber-11"
        >
          {{ t('JRC_SERVICE_DESK.QUICK.classification_required') }}
        </p>
        <template v-for="row in fields" :key="row.input">
          <label
            v-if="row.spec.type === 'boolean'"
            class="flex items-start gap-2 text-sm"
            ><input
              v-model="draft.fields[row.input]"
              type="checkbox"
              :disabled="saving || !!pending"
            /><span>{{ row.spec.label }}</span></label
          >
          <Input
            v-else
            v-model="draft.fields[row.input]"
            :type="row.spec.type === 'integer' ? 'number' : 'text'"
            :label="row.spec.label"
            :disabled="saving || !!pending"
          />
          <p
            v-if="Object.hasOwn(row.spec, 'equals')"
            class="m-0 text-xs text-n-slate-11"
          >
            {{ t('JRC_SERVICE_DESK.LIFECYCLE.expected_value') }}:
            {{ row.spec.equals }}
          </p>
        </template>
        <p v-if="failure" role="alert" class="m-0 text-sm text-n-ruby-11">
          {{
            t(
              `JRC_SERVICE_DESK.QUICK.${['dependency', 'denied', 'conflict', 'closure_unavailable'].includes(failure) ? failure : 'closure_failed'}`
            )
          }}
        </p>
        <div
          class="flex flex-wrap justify-end gap-2 border-t border-n-weak pt-4"
        >
          <Button
            type="button"
            color="slate"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
            :disabled="saving || !!pending"
            @click="cancel"
          />
          <Button
            v-if="pending && !saving"
            type="button"
            :label="t('JRC_SERVICE_DESK.QUICK.recover_closure')"
            @click="run"
          />
          <Button
            v-else
            type="submit"
            :label="t('JRC_SERVICE_DESK.QUICK.confirm_close')"
            :disabled="!valid || saving"
          />
        </div>
      </form>
      <Button
        v-if="!plans.length"
        variant="ghost"
        color="slate"
        :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
        :disabled="saving || !!pending"
        @click="cancel"
      />
    </template>
  </div>
</template>
