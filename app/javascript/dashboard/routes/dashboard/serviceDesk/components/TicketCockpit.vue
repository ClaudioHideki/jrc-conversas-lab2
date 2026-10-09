<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import API from 'dashboard/api/serviceDeskCockpit';
import LifecycleAPI from 'dashboard/api/serviceDeskLifecycle';
import Button from 'dashboard/components-next/button/Button.vue';
import State from './ServiceDeskState.vue';
import InteractionComposer from './InteractionComposer.vue';
import RecipientPreferences from './RecipientPreferences.vue';
import Lookup from './LookupSelect.vue';
import TicketTimeline from './TicketTimeline.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeCockpit } from '../helpers/cockpitContract';
import { newRequestKey } from '../helpers/drafts';
import { formatTimestamp } from '../helpers/presentation';
import { serviceDeskRouteName } from '../routeDefinitions';
import { v2Labels } from '../helpers/v2Labels';
import { errorStatus } from '../helpers/session';
import { decodeLifecycle } from '../helpers/lifecycle';
const props = defineProps({
  ticket: { type: Object, required: true },
  mode: { type: String, default: 'all' },
});
const emit = defineEmits(['updated']);
const { t, locale } = useI18n();
const labels = computed(() => v2Labels(t));
const session = useServiceDesk();
const router = useRouter();
const knowledge = () =>
  router.push({
    name: serviceDeskRouteName('knowledge'),
    params: { accountId: props.ticket.account_id },
    query: { query: props.ticket.title.slice(0, 200) },
  });
const separator = '·';
const numberPrefix = '#';
const data = ref(null);
const status = ref('loading');
const feedback = ref(null);
const busy = ref(false);
const visibility = ref('internal');
const previous = ref(null);
const revision = ref(0);
const taskTitle = ref('');
const checklistText = ref('');
const taskDue = ref('');
const taskPriority = ref('normal');
const taskAssignee = ref('');
const parentTask = ref('');
const nextTaskTitle = ref('');
const progressionEnabled = ref(false);
const lifecycle = ref(null);
const lifecycleStatus = ref('idle');
const approvalTarget = ref('person');
const approvalTeam = ref('');
const approvalRole = ref('');
const waitingRule = ref('');
const waitingReason = ref('');
const waitingNote = ref('');
const escalations = ref({});
const approvalTitle = ref('');
const approver = ref('');
const approvalDue = ref('');
const decisionComments = ref({});
let epoch = 0;
let controller;
const requestKeys = new Map();
const active = () =>
  session.state.status === 'ready' &&
  session.state.context?.account_id === props.ticket.account_id;
const permissions = computed(() => props.ticket.permissions || {});
const audiences = computed(() => [
  'internal',
  ...(permissions.value.technical_notes && props.ticket.team
    ? ['technical_team']
    : []),
  ...(permissions.value.customer_publish
    ? ['customer', 'public_without_notification']
    : []),
]);
const showInteractions = computed(() =>
  ['all', 'notes', 'files'].includes(props.mode)
);
const showTasks = computed(() => ['all', 'tasks'].includes(props.mode));
const canPublishProgression = computed(
  () =>
    session.state.context?.capabilities?.lifecycle_policies?.publish === true
);
const waitingOptions = computed(
  () =>
    lifecycle.value?.options.filter(
      row =>
        row.action === 'pause' &&
        !row.requirements.solution &&
        !row.requirements.evidence &&
        !row.requirements.classification &&
        !Object.values(row.requirements.fields).some(field => field.required)
    ) || []
);
const selectedWaiting = computed(() =>
  waitingOptions.value.find(row => row.key === waitingRule.value)
);
const loadLifecycle = async () => {
  if (!active() || !permissions.value.lifecycle_inspect) return;
  const context = session.state.context;
  const turn = epoch;
  const ticket = props.ticket;
  lifecycle.value = null;
  lifecycleStatus.value = 'loading';
  try {
    const payload = await LifecycleAPI.read(
      context.account_id,
      ticket.id,
      1,
      controller.signal
    );
    if (
      turn !== epoch ||
      context !== session.state.context ||
      ticket.id !== props.ticket.id
    )
      return;
    lifecycle.value = decodeLifecycle(payload, context, ticket);
    lifecycleStatus.value = 'ready';
  } catch (error) {
    if (turn === epoch) lifecycleStatus.value = errorStatus(error);
  }
};
const load = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  const context = session.state.context;
  data.value = null;
  status.value = 'loading';
  if (!active()) {
    status.value = 'denied';
    return null;
  }
  try {
    const payload = await API.read(
      context.account_id,
      props.ticket.id,
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context || !active())
      return null;
    data.value = decodeCockpit(payload, context, props.ticket);
    status.value = 'ready';
    return data.value;
  } catch (error) {
    if (turn !== epoch || context !== session.state.context) return null;
    status.value = errorStatus(error);
    return null;
  }
};
watch(
  [
    () => props.ticket.id,
    () => session.state.context,
    () => session.state.status,
  ],
  () => {
    previous.value = null;
    lifecycle.value = null;
    lifecycleStatus.value = 'idle';
    progressionEnabled.value = false;
    waitingRule.value = '';
    waitingReason.value = '';
    escalations.value = {};
    requestKeys.clear();
    load();
  },
  { immediate: true }
);
const write = async (operation, payload, send, verify) => {
  if (busy.value || !active()) return false;
  busy.value = true;
  feedback.value = null;
  const context = session.state.context;
  const ticketId = props.ticket.id;
  const turn = epoch;
  const fingerprint = `${operation}:${JSON.stringify(payload)}`;
  if (!requestKeys.has(fingerprint))
    requestKeys.set(fingerprint, newRequestKey());
  try {
    const acknowledgement = await send(
      context.account_id,
      ticketId,
      requestKeys.get(fingerprint),
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context || !active())
      return false;
    if (
      acknowledgement.applied !== true ||
      acknowledgement.account_id !== context.account_id ||
      acknowledgement.ticket_id !== ticketId
    )
      throw new Error('Invalid acknowledgement');
    const refreshed = await load();
    if (!refreshed || !verify(refreshed, acknowledgement.result_id))
      throw new Error('Write could not be verified');
    requestKeys.delete(fingerprint);
    feedback.value = 'saved';
    emit('updated');
    return true;
  } catch (error) {
    if (context === session.state.context && active()) {
      if (error?.response?.status === 409) feedback.value = 'conflict';
      else if ([401, 403].includes(error?.response?.status))
        feedback.value = 'denied';
      else feedback.value = 'error';
      if (feedback.value === 'denied') {
        data.value = null;
        status.value = 'denied';
      }
    }
    return false;
  } finally {
    busy.value = false;
  }
};
const audience = () => ({
  visibility: visibility.value,
  ...(visibility.value === 'technical_team'
    ? { audience_team_id: props.ticket.team.id }
    : {}),
});
const createTask = async () => {
  if (
    progressionEnabled.value &&
    (!canPublishProgression.value ||
      !lifecycle.value?.policy ||
      !nextTaskTitle.value.trim())
  )
    return;
  const task = {
    title: taskTitle.value,
    ...audience(),
    checklist: checklistText.value
      .split('\n')
      .filter(line => line.trim())
      .map(line => ({ title: line.trim(), done: false })),
    ...(taskDue.value ? { due_at: new Date(taskDue.value).toISOString() } : {}),
    priority: taskPriority.value,
    assignee_account_user_id: taskAssignee.value || null,
    parent_task_id: parentTask.value || null,
    ...(progressionEnabled.value
      ? {
          completion_policy: {
            enabled: true,
            lifecycle_policy_version_id: lifecycle.value.policy.id,
            lifecycle_policy_digest: lifecycle.value.policy.digest,
            next_task: { title: nextTaskTitle.value, visibility: 'internal' },
            approval: null,
            transition: null,
          },
        }
      : {}),
  };
  if (
    await write(
      'create_task',
      task,
      (account, ticket, key, signal) =>
        API.task(account, ticket, task, key, signal),
      (result, resultId) =>
        result.tasks.some(
          row => row.id === resultId && row.title === task.title
        )
    )
  ) {
    taskTitle.value = '';
    checklistText.value = '';
    taskDue.value = '';
    parentTask.value = '';
    nextTaskTitle.value = '';
    progressionEnabled.value = false;
  }
};
const updateTask = async (row, changes) =>
  write(
    'update_task',
    { id: row.id, changes, version: row.lock_version },
    (account, ticket, _key, signal) =>
      API.updateTask(account, ticket, row, changes, signal),
    result =>
      result.tasks.some(
        item =>
          item.id === row.id &&
          (!changes.status || item.status === changes.status) &&
          (!changes.checklist ||
            JSON.stringify(item.checklist) ===
              JSON.stringify(changes.checklist))
      )
  );
const toggleItem = (row, index, done) =>
  updateTask(row, {
    checklist: row.checklist.map((item, at) => ({
      ...item,
      done: at === index ? done : item.done,
    })),
  });
const targetPayload = (mode, target) => {
  const field = {
    person: 'approver_account_user_id',
    team: 'approver_team_id',
    role: 'approver_role',
  }[mode];
  if (!field || !target) throw new Error('Explicit approval target required');
  return { [field]: target };
};
const approvalSelection = computed(
  () =>
    ({
      person: approver.value,
      team: approvalTeam.value,
      role: approvalRole.value,
    })[approvalTarget.value]
);
const requestApproval = async () => {
  const approval = {
    title: approvalTitle.value,
    ...targetPayload(approvalTarget.value, approvalSelection.value),
    due_at: new Date(approvalDue.value).toISOString(),
    ...(waitingRule.value && selectedWaiting.value && lifecycle.value?.policy
      ? {
          waiting_transition: {
            rule_key: waitingRule.value,
            reason_code: waitingReason.value,
            expected_policy_version_id: lifecycle.value.policy.id,
            note: waitingNote.value || null,
          },
        }
      : {}),
  };
  if (
    await write(
      'request_approval',
      approval,
      (account, ticket, key, signal) =>
        API.approval(account, ticket, approval, key, signal),
      (result, resultId) =>
        result.approvals.some(
          row => row.id === resultId && row.title === approval.title
        )
    )
  ) {
    approvalTitle.value = '';
    approver.value = '';
    approvalDue.value = '';
    approvalTeam.value = '';
    approvalRole.value = '';
    waitingRule.value = '';
    waitingReason.value = '';
    waitingNote.value = '';
  }
};
const decide = (row, decision) =>
  write(
    'decide_approval',
    {
      id: row.id,
      status: decision,
      comment: decisionComments.value[row.id] || null,
    },
    (account, ticket, _key, signal) =>
      API.decision(
        account,
        ticket,
        row,
        { status: decision, comment: decisionComments.value[row.id] || null },
        signal
      ),
    result =>
      result.approvals.some(
        item => item.id === row.id && item.status === decision
      )
  );
const escalation = row => {
  const values = escalations.value[row.id];
  const payload = {
    reason: values.reason,
    ...targetPayload(values.mode, values.target),
    ...(values.due ? { due_at: new Date(values.due).toISOString() } : {}),
  };
  return write(
    'escalate_approval',
    { id: row.id, ...payload },
    (account, ticket, _key, signal) =>
      API.escalateApproval(account, ticket, row, payload, signal),
    result =>
      result.approvals.some(
        item =>
          item.id === row.id &&
          item.lock_version > row.lock_version &&
          item.history.length > row.history.length
      )
  );
};
const evaluateClocks = () =>
  write(
    'evaluate_clocks',
    {},
    (account, ticket, _key, signal) =>
      API.evaluateClocks(account, ticket, signal),
    () => true
  );
const republish = row => {
  previous.value = row;
};
const refreshed = publication => {
  previous.value = null;
  revision.value += 1;
  emit('updated', publication);
  load();
};
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  data.value = null;
  requestKeys.clear();
});
</script>

<template>
  <div class="grid gap-5">
    <Button
      v-if="session.state.context?.capabilities?.knowledge?.index"
      size="xs"
      variant="outline"
      :label="t('JRC_SERVICE_DESK.SCREENS.knowledge')"
      @click="knowledge"
    />
    <State v-if="status !== 'ready'" :status="status" retry @retry="load" />
    <template v-else>
      <div
        v-if="data.incident && mode === 'all'"
        class="rounded-lg border border-n-weak p-3 text-sm"
      >
        {{ t('JRC_SERVICE_DESK.COCKPIT.incident') }} {{ numberPrefix
        }}{{ data.incident.id }} {{ separator }} {{ data.incident.title }}
        {{ separator }} {{ data.incident.severity }}
      </div>
      <div v-if="showInteractions" class="grid gap-3">
        <TicketTimeline
          :ticket="ticket"
          :revision="revision"
          @republish="republish"
          @updated="refreshed"
        />
        <InteractionComposer
          v-if="permissions.add_note"
          :ticket="ticket"
          :previous="previous"
          @updated="refreshed"
        />
        <RecipientPreferences :ticket="ticket" @updated="refreshed" />
      </div>
      <section v-if="showTasks && permissions.tasks_view" class="grid gap-3">
        <h3 class="font-semibold">
          {{ t('JRC_SERVICE_DESK.TICKET.tabs.tasks') }}
        </h3>
        <article
          v-for="row in data.tasks"
          :key="row.id"
          class="rounded-lg border border-n-weak p-3 grid gap-2"
        >
          <p class="font-medium text-sm">
            {{ row.title }} {{ separator }}
            {{ labels.task[row.status] }}
          </p>
          <p class="text-xs">
            {{ labels.visibility[row.visibility] }} {{ separator }}
            {{ formatTimestamp(row.due_at, locale) }}
          </p>
          <p v-if="row.parent_task_id" class="text-xs">
            {{ t('JRC_SERVICE_DESK.R3.parent_task') }}:
            {{
              data.tasks.find(parent => parent.id === row.parent_task_id)
                ?.title || numberPrefix + row.parent_task_id
            }}
          </p>
          <p v-if="row.pending_children" class="text-xs">
            {{
              t('JRC_SERVICE_DESK.R3.pending_subtasks', {
                count: row.pending_children,
              })
            }}
          </p>
          <label
            v-for="(item, index) in row.checklist"
            :key="index"
            class="flex gap-2 text-sm"
          >
            <input
              type="checkbox"
              :checked="item.done"
              :disabled="
                busy ||
                !row.permissions.update ||
                ['completed', 'cancelled'].includes(row.status)
              "
              @change="toggleItem(row, index, $event.target.checked)"
            />{{ item.title }}
          </label>
          <Button
            v-if="
              row.permissions.update &&
              !['completed', 'cancelled'].includes(row.status)
            "
            size="xs"
            :disabled="
              busy ||
              row.pending_children > 0 ||
              row.checklist.some(item => !item.done)
            "
            :label="t('JRC_SERVICE_DESK.COCKPIT.complete_task')"
            @click="updateTask(row, { status: 'completed' })"
          />
        </article>
        <form
          v-if="permissions.tasks_manage"
          class="grid gap-3"
          @submit.prevent="createTask"
        >
          <label class="text-sm">
            {{ t('JRC_SERVICE_DESK.COCKPIT.audience') }}
            <select
              v-model="visibility"
              :disabled="busy"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option v-for="value in audiences" :key="value" :value="value">
                {{ labels.visibility[value] }}
              </option>
            </select>
          </label>
          <input
            v-model="taskTitle"
            required
            maxlength="255"
            :aria-label="t('JRC_SERVICE_DESK.COCKPIT.task_title')"
            :placeholder="t('JRC_SERVICE_DESK.COCKPIT.task_title')"
            class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
          />
          <textarea
            v-model="checklistText"
            :aria-label="t('JRC_SERVICE_DESK.COCKPIT.checklist')"
            :placeholder="t('JRC_SERVICE_DESK.COCKPIT.checklist')"
            class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
          />
          <input
            v-model="taskDue"
            type="datetime-local"
            :aria-label="t('JRC_SERVICE_DESK.COCKPIT.deadline')"
            class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
          />
          <Lookup
            v-model="taskAssignee"
            resource="assignees"
            :unit-id="ticket.unit_id"
            :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
            :disabled="busy"
          />
          <label
            >{{ t('JRC_SERVICE_DESK.FIELDS.priority')
            }}<select
              v-model="taskPriority"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option
                v-for="value in ['low', 'normal', 'high', 'urgent']"
                :key="value"
                :value="value"
              >
                {{ t(`JRC_SERVICE_DESK.R3.priority.${value}`) }}
              </option>
            </select></label
          >
          <label
            >{{ t('JRC_SERVICE_DESK.R3.parent_task')
            }}<select
              v-model="parentTask"
              class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">{{ t('JRC_SERVICE_DESK.COMMON.none') }}</option>
              <option
                v-for="row in data.tasks.filter(
                  task => !['completed', 'cancelled'].includes(task.status)
                )"
                :key="row.id"
                :value="row.id"
              >
                {{ row.title }}
              </option>
            </select></label
          >
          <template
            v-if="canPublishProgression && permissions.lifecycle_inspect"
          >
            <label class="flex gap-2 text-sm"
              ><input
                v-model="progressionEnabled"
                type="checkbox"
                @change="progressionEnabled && loadLifecycle()"
              />{{ t('JRC_SERVICE_DESK.R3.task_progression') }}</label
            >
            <template v-if="progressionEnabled">
              <State
                v-if="lifecycleStatus !== 'ready'"
                :status="lifecycleStatus"
                compact
                retry
                @retry="loadLifecycle"
              /><input
                v-model="nextTaskTitle"
                :aria-label="t('JRC_SERVICE_DESK.R3.next_task')"
                :placeholder="t('JRC_SERVICE_DESK.R3.next_task')"
                maxlength="255"
                class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
              />
              <p class="text-xs">
                {{ t('JRC_SERVICE_DESK.R3.published_progression_help') }}
              </p>
            </template>
          </template>
          <Button
            type="submit"
            :disabled="
              busy ||
              !taskTitle.trim() ||
              (progressionEnabled &&
                (!lifecycle?.policy || !nextTaskTitle.trim()))
            "
            :label="t('JRC_SERVICE_DESK.COCKPIT.create_task')"
          />
        </form>
      </section>
      <section
        v-if="showTasks && permissions.approvals_view"
        class="grid gap-3"
      >
        <h3 class="font-semibold">
          {{ t('JRC_SERVICE_DESK.COCKPIT.approvals') }}
        </h3>
        <article
          v-for="row in data.approvals"
          :key="row.id"
          class="rounded-lg border border-n-weak p-3 grid gap-2"
        >
          <p class="text-sm">
            {{ row.title }} {{ separator }} {{ labels.approval[row.status] }}
            {{ separator }}
            {{ formatTimestamp(row.due_at, locale) }}
          </p>
          <p v-if="row.comment" class="text-sm whitespace-pre-wrap">
            {{ row.comment }}
          </p>
          <details v-if="row.history.length">
            <summary class="text-xs">
              {{ t('JRC_SERVICE_DESK.R3.resource_history') }}
            </summary>
            <p
              v-for="(entry, index) in row.history"
              :key="index"
              class="text-xs"
            >
              {{ formatTimestamp(entry.occurred_at, locale) }}
              {{ t(`JRC_SERVICE_DESK.R3.history.${entry.action}`) }}
            </p>
          </details>
          <Button
            v-if="row.permissions.escalate && !escalations[row.id]"
            size="xs"
            variant="outline"
            :label="t('JRC_SERVICE_DESK.R3.escalate_approval')"
            @click="
              escalations[row.id] = {
                mode: 'person',
                target: '',
                reason: '',
                due: '',
              }
            "
          />
          <form
            v-if="escalations[row.id] && row.permissions.escalate"
            class="grid gap-2"
            @submit.prevent="escalation(row)"
          >
            <select
              v-model="escalations[row.id].mode"
              :aria-label="t('JRC_SERVICE_DESK.R3.approval_target')"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
              @change="escalations[row.id].target = ''"
            >
              <option
                v-for="value in ['person', 'team', 'role']"
                :key="value"
                :value="value"
              >
                {{ t(`JRC_SERVICE_DESK.R3.targets.${value}`) }}
              </option>
            </select>
            <Lookup
              v-if="escalations[row.id].mode !== 'role'"
              v-model="escalations[row.id].target"
              :resource="
                escalations[row.id].mode === 'team' ? 'teams' : 'assignees'
              "
              :unit-id="ticket.unit_id"
              :label="t('JRC_SERVICE_DESK.COCKPIT.approver')"
              :disabled="busy"
            />
            <select
              v-else
              v-model="escalations[row.id].target"
              :aria-label="t('JRC_SERVICE_DESK.R3.approval_role')"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.COMMON.select') }}
              </option>
              <option
                v-for="value in ['agent', 'administrator']"
                :key="value"
                :value="value"
              >
                {{ t(`JRC_SERVICE_DESK.R3.roles.${value}`) }}
              </option>
            </select>
            <textarea
              v-model="escalations[row.id].reason"
              required
              maxlength="4000"
              :aria-label="t('JRC_SERVICE_DESK.R3.escalation_reason')"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
            <input
              v-model="escalations[row.id].due"
              type="datetime-local"
              :aria-label="t('JRC_SERVICE_DESK.COCKPIT.deadline')"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
            <div class="flex gap-2">
              <Button
                type="submit"
                :disabled="
                  busy ||
                  !escalations[row.id].target ||
                  !escalations[row.id].reason.trim()
                "
                :label="t('JRC_SERVICE_DESK.R3.escalate_approval')"
              /><Button
                variant="outline"
                :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
                @click="delete escalations[row.id]"
              />
            </div>
          </form>
          <template v-if="row.status === 'pending' && row.permissions.decide">
            <textarea
              v-model="decisionComments[row.id]"
              :aria-label="t('JRC_SERVICE_DESK.COCKPIT.decision_comment')"
              class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
            />
            <div class="flex flex-wrap gap-2">
              <Button
                v-for="decision in ['approved', 'rejected', 'returned']"
                :key="decision"
                size="xs"
                :disabled="
                  busy ||
                  (decision !== 'approved' && !decisionComments[row.id]?.trim())
                "
                :label="labels.approval[decision]"
                @click="decide(row, decision)"
              />
            </div>
          </template>
        </article>
        <form
          v-if="permissions.approvals_request"
          class="grid gap-3"
          @submit.prevent="requestApproval"
        >
          <input
            v-model="approvalTitle"
            required
            maxlength="255"
            :aria-label="t('JRC_SERVICE_DESK.COCKPIT.approval_title')"
            :placeholder="t('JRC_SERVICE_DESK.COCKPIT.approval_title')"
            class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
          />
          <select
            v-model="approvalTarget"
            :aria-label="t('JRC_SERVICE_DESK.R3.approval_target')"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option
              v-for="value in ['person', 'team', 'role']"
              :key="value"
              :value="value"
            >
              {{ t(`JRC_SERVICE_DESK.R3.targets.${value}`) }}
            </option>
          </select>
          <Lookup
            v-if="approvalTarget === 'team'"
            v-model="approvalTeam"
            resource="teams"
            :unit-id="ticket.unit_id"
            :label="t('JRC_SERVICE_DESK.FIELDS.team')"
            :disabled="busy"
          />
          <select
            v-else-if="approvalTarget === 'role'"
            v-model="approvalRole"
            :aria-label="t('JRC_SERVICE_DESK.R3.approval_role')"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">{{ t('JRC_SERVICE_DESK.COMMON.select') }}</option>
            <option
              v-for="value in ['agent', 'administrator']"
              :key="value"
              :value="value"
            >
              {{ t(`JRC_SERVICE_DESK.R3.roles.${value}`) }}
            </option>
          </select>
          <select
            v-else
            v-model="approver"
            required
            :aria-label="t('JRC_SERVICE_DESK.COCKPIT.approver')"
            class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
          >
            <option value="">
              {{ t('JRC_SERVICE_DESK.COCKPIT.approver') }}
            </option>
            <option
              v-for="member in data.approvers"
              :key="member.id"
              :value="member.id"
            >
              {{ member.name }}
            </option>
          </select>
          <input
            v-model="approvalDue"
            required
            type="datetime-local"
            :aria-label="t('JRC_SERVICE_DESK.COCKPIT.deadline')"
            class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
          />
          <template v-if="permissions.lifecycle_inspect">
            <Button
              size="xs"
              variant="outline"
              :label="t('JRC_SERVICE_DESK.R3.approval_waiting')"
              :disabled="busy"
              @click="loadLifecycle"
            />
            <template v-if="lifecycleStatus === 'ready'">
              <select
                v-model="waitingRule"
                :aria-label="t('JRC_SERVICE_DESK.R3.approval_waiting')"
                class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                @change="waitingReason = ''"
              >
                <option value="">
                  {{ t('JRC_SERVICE_DESK.COMMON.none') }}
                </option>
                <option
                  v-for="row in waitingOptions"
                  :key="row.key"
                  :value="row.key"
                >
                  {{ row.to_status_name }}
                </option></select
              ><select
                v-if="selectedWaiting"
                v-model="waitingReason"
                required
                :aria-label="t('JRC_SERVICE_DESK.R3.waiting_reason')"
                class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">
                  {{ t('JRC_SERVICE_DESK.COMMON.select') }}
                </option>
                <option
                  v-for="reason in selectedWaiting.reasons"
                  :key="reason.code"
                  :value="reason.code"
                >
                  {{ reason.name }}
                </option></select
              ><textarea
                v-if="selectedWaiting?.requirements.note"
                v-model="waitingNote"
                required
                :aria-label="t('JRC_SERVICE_DESK.R3.waiting_note')"
                class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
              />
            </template>
          </template>
          <Button
            type="submit"
            :disabled="
              busy ||
              !approvalTitle.trim() ||
              !(approvalTarget === 'person'
                ? approver
                : approvalTarget === 'team'
                  ? approvalTeam
                  : approvalRole) ||
              !approvalDue ||
              (waitingRule && !waitingReason)
            "
            :label="t('JRC_SERVICE_DESK.COCKPIT.request_approval')"
          />
        </form>
      </section>
      <section v-if="mode === 'all' && permissions.view_sla" class="grid gap-3">
        <h3 class="font-semibold">{{ t('JRC_SERVICE_DESK.R3.ola_title') }}</h3>
        <article
          v-for="clock in data.ola"
          :key="clock.id"
          class="rounded-lg border p-3 text-sm"
          :class="
            clock.breached
              ? 'border-n-ruby-7 bg-n-ruby-2 text-n-ruby-11'
              : 'border-n-weak bg-n-solid-1'
          "
        >
          <p>
            {{ t(`JRC_SERVICE_DESK.R3.clock_states.${clock.state}`) }}
            {{ separator }} {{ Math.round(clock.consumed_percent) }}%
          </p>
          <p>
            {{
              t('JRC_SERVICE_DESK.R3.remaining_minutes', {
                minutes: Math.ceil(clock.remaining_seconds / 60),
              })
            }}
          </p>
          <time>{{ formatTimestamp(clock.due_at, locale) }}</time>
        </article>
        <Button
          v-if="permissions.update"
          size="xs"
          variant="outline"
          :disabled="busy"
          :label="t('JRC_SERVICE_DESK.R3.evaluate_clocks')"
          @click="evaluateClocks"
        />
      </section>
      <p v-if="feedback" role="status" class="text-sm">
        {{ labels.feedback[feedback] }}
      </p>
    </template>
  </div>
</template>
