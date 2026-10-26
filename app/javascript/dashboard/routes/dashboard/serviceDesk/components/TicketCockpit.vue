<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import API from 'dashboard/api/serviceDeskCockpit';
import LifecycleAPI from 'dashboard/api/serviceDeskLifecycle';
import Button from 'dashboard/components-next/button/Button.vue';
import State from './ServiceDeskState.vue';
import ServiceDeskDialog from './ServiceDeskDialog.vue';
import InteractionComposer from './InteractionComposer.vue';
import RecipientPreferences from './RecipientPreferences.vue';
import Lookup from './LookupSelect.vue';
import TicketTimeline from './TicketTimeline.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeCockpit } from '../helpers/cockpitContract';
import { newRequestKey } from '../helpers/drafts';
import { dueState } from '../helpers/screenExperience.js';
import { formatTimestamp } from '../helpers/presentation';
import { serviceDeskRouteName } from '../routeDefinitions';
import { v2Labels } from '../helpers/v2Labels';
import { errorStatus } from '../helpers/session';
import { decodeLifecycle } from '../helpers/lifecycle';
const props = defineProps({
  ticket: { type: Object, required: true },
  mode: { type: String, default: 'all' },
  createTaskOnOpen: Boolean,
  hideAttachments: Boolean,
});
const emit = defineEmits(['updated', 'taskEditorOpened']);
const communicationDirty = ref(false);
const communicationBusy = ref(false);
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
const observedAt = ref(new Date().toISOString());
const status = ref('loading');
const feedback = ref(null);
const failureReason = ref('');
const busy = ref(false);
const visibility = ref('internal');
const previous = ref(null);
const revision = ref(0);
const taskTitle = ref('');
const taskDescription = ref('');
const taskDialog = ref(false);
const editingTask = ref(null);
const deletingTask = ref(null);
const taskDeleteReason = ref('');
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
  ['all', 'notes', 'files', 'communication'].includes(props.mode)
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
    observedAt.value = new Date().toISOString();
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
  failureReason.value = '';
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
      if (error?.response?.data?.code === 'deletion_blocked')
        failureReason.value = error.response.data.error || '';
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
    description: taskDescription.value,
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
    taskDialog.value = false;
    taskTitle.value = '';
    taskDescription.value = '';
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
const localDateTime = value => {
  if (!value) return '';
  const date = new Date(value);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
};
const openTaskEditor = (row = null) => {
  editingTask.value = row;
  taskTitle.value = row?.title || '';
  taskDescription.value = row?.description || '';
  taskDue.value = localDateTime(row?.due_at);
  taskPriority.value = row?.priority || 'normal';
  taskAssignee.value = row?.assignee_account_user_id || '';
  parentTask.value = row?.parent_task_id || '';
  checklistText.value = row?.checklist.map(item => item.title).join('\n') || '';
  visibility.value = row?.visibility || 'internal';
  progressionEnabled.value = false;
  nextTaskTitle.value = '';
  taskDialog.value = true;
};
watch(
  () => props.createTaskOnOpen,
  value => {
    if (value && props.mode === 'tasks') {
      openTaskEditor();
      emit('taskEditorOpened');
    }
  },
  { immediate: true }
);
const terminalTask = computed(() =>
  ['completed', 'cancelled'].includes(editingTask.value?.status)
);
const saveTask = async () => {
  if (!editingTask.value) return createTask();
  const row = editingTask.value;
  const changes = {
    title: taskTitle.value,
    description: taskDescription.value,
  };
  if (!terminalTask.value)
    Object.assign(changes, {
      due_at: taskDue.value ? new Date(taskDue.value).toISOString() : null,
      priority: taskPriority.value,
      assignee_account_user_id: taskAssignee.value || null,
      checklist: checklistText.value
        .split('\n')
        .filter(line => line.trim())
        .map((line, index) => ({
          title: line.trim(),
          done:
            row.checklist[index]?.title === line.trim() &&
            row.checklist[index]?.done === true,
        })),
    });
  const saved = await write(
    'update_task',
    { id: row.id, changes, version: row.lock_version },
    (account, ticket, _key, signal) =>
      API.updateTask(account, ticket, row, changes, signal),
    result =>
      result.tasks.some(
        item =>
          item.id === row.id &&
          item.title === changes.title &&
          (item.description || '') === (changes.description || '')
      )
  );
  if (saved) taskDialog.value = false;
  return saved;
};
const removeTask = async () => {
  const row = deletingTask.value;
  if (
    !row ||
    !row.permissions.destroy ||
    taskDeleteReason.value.trim().length < 3
  )
    return;
  const saved = await write(
    'delete_task',
    { id: row.id, version: row.lock_version, reason: taskDeleteReason.value },
    (account, ticket, _key, signal) =>
      API.deleteTask(
        account,
        ticket,
        row,
        taskDeleteReason.value.trim(),
        signal
      ),
    result => !result.tasks.some(item => item.id === row.id)
  );
  if (saved) deletingTask.value = null;
};
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
      v-if="
        mode === 'all' && session.state.context?.capabilities?.knowledge?.index
      "
      size="xs"
      variant="outline"
      :label="t('JRC_SERVICE_DESK.SCREENS.knowledge')"
      @click="knowledge"
    />
    <State
      v-if="status !== 'ready'"
      :status="status"
      retry
      @retry="load"
    />
    <template v-else>
      <div
        v-if="data.incident && mode === 'all'"
        class="rounded-lg border border-n-weak p-3 text-sm"
      >
        {{ t('JRC_SERVICE_DESK.COCKPIT.incident') }} {{ numberPrefix
        }}{{ data.incident.id }} {{ separator }} {{ data.incident.title }}
        {{ separator }} {{ data.incident.severity }}
      </div>
      <div
        v-if="
          data.relatedIncidents?.length && ['all', 'history'].includes(mode)
        "
        class="flex flex-wrap gap-2 rounded-xl border border-n-weak p-3"
      >
        <button
          v-for="item in data.relatedIncidents"
          :key="item.id"
          type="button"
          class="rounded-lg bg-n-blue-2 px-3 py-2 text-xs text-n-blue-11"
          @click="
            router.push({
              name: serviceDeskRouteName(
                item.resource_kind === 'problem' ? 'problems' : 'incidents'
              ),
              params: { accountId: ticket.account_id },
              query: { unit_id: ticket.unit_id, case_id: item.id },
            })
          "
        >
          {{ t(`JRC_SERVICE_DESK.CASES.${item.resource_kind}`) }} #{{
            item.id
          }}: {{ item.title }}
        </button>
      </div>
      <div
        v-if="showInteractions"
        class="grid gap-3"
      >
        <TicketTimeline
          :ticket="ticket"
          :revision="revision"
          :conversations="data.conversations"
          :selection-locked="communicationDirty || communicationBusy"
          :hide-attachments="hideAttachments"
          :only-files="mode === 'files'"
          :view="
            mode === 'notes'
              ? 'notes'
              : mode === 'communication'
                ? 'conversations'
                : mode === 'files'
                  ? 'files'
                  : 'all'
          "
          @republish="republish"
          @updated="refreshed"
        >
          <template
            v-if="mode === 'communication'"
            #composer="{ conversation }"
          >
            <InteractionComposer
              v-if="permissions.add_note"
              :ticket="ticket"
              :previous="previous"
              :conversation="conversation"
              mode="conversation"
              @draft-change="communicationDirty = $event"
              @busy-change="communicationBusy = $event"
              @updated="refreshed"
            />
          </template>
        </TicketTimeline>
        <InteractionComposer
          v-if="permissions.add_note && mode !== 'communication'"
          :ticket="ticket"
          :previous="previous"
          :mode="
            mode === 'notes'
              ? 'internal'
              : mode === 'communication'
                ? 'conversation'
                : mode === 'files'
                  ? 'files'
                  : 'all'
          "
          @updated="refreshed"
        />
        <RecipientPreferences
          v-if="['communication', 'all'].includes(mode)"
          :ticket="ticket"
          @updated="refreshed"
        />
      </div>
      <section
        v-if="showTasks && permissions.tasks_view"
        class="grid gap-3"
      >
        <div class="flex items-center justify-between gap-3">
          <p class="text-sm text-n-slate-11">
            {{
              t('JRC_SERVICE_DESK.REDESIGN_DETAIL.task_count', {
                count: data.tasks.length,
              })
            }}
          </p>
          <Button
            v-if="permissions.tasks_manage"
            size="sm"
            icon="i-lucide-plus"
            :label="t('JRC_SERVICE_DESK.COCKPIT.create_task')"
            @click="openTaskEditor()"
          />
        </div>
        <p
          v-if="!data.tasks.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
        </p>
        <article
          v-for="row in data.tasks"
          :key="row.id"
          class="rounded-lg border border-n-weak p-3 grid gap-2"
        >
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div class="min-w-0 flex-1">
              <p class="break-words font-medium text-sm">{{ row.title }}</p>
              <p class="mt-1 text-xs text-n-slate-11">
                {{ labels.task[row.status] }} ·
                {{
                  t(`JRC_SERVICE_DESK.R3.priority.${row.priority || 'normal'}`)
                }}
                ·
                {{
                  data.approvers.find(
                    person => person.id === row.assignee_account_user_id
                  )?.name ||
                  t(
                    row.assignee_account_user_id
                      ? 'JRC_SERVICE_DESK.COMMON.selected_identifier'
                      : 'JRC_SERVICE_DESK.REDESIGN_DETAIL.unassigned',
                    { id: row.assignee_account_user_id }
                  )
                }}
              </p>
            </div>
            <div class="flex gap-1">
              <Button
                v-if="row.permissions.update"
                size="xs"
                color="slate"
                variant="ghost"
                icon="i-lucide-pencil"
                :label="t('JRC_SERVICE_DESK.COMMON.edit')"
                :disabled="busy"
                @click="openTaskEditor(row)"
              />
              <Button
                v-if="row.permissions.destroy"
                size="xs"
                color="ruby"
                variant="ghost"
                icon="i-lucide-trash-2"
                :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delete')"
                :disabled="busy"
                @click="
                  deletingTask = row;
                  taskDeleteReason = '';
                "
              />
            </div>
          </div>
          <p
            v-if="row.description"
            class="whitespace-pre-wrap break-words text-sm text-n-slate-11"
          >
            {{ row.description }}
          </p>
          <p class="text-xs">
            {{ labels.visibility[row.visibility] }} {{ separator }}
            {{ formatTimestamp(row.due_at, locale) }}
          </p>
          <p
            v-if="dueState(row, observedAt) === 'overdue'"
            class="text-xs text-n-ruby-11"
          >
            {{ t('JRC_SERVICE_DESK.EXPERIENCE.overdue') }}
          </p>
          <div
            v-if="row.checklist.length"
            class="flex items-center gap-3"
          >
            <progress
              class="min-w-0 flex-1"
              :value="row.checklist.filter(item => item.done).length"
              :max="row.checklist.length"
              :aria-label="t('JRC_SERVICE_DESK.EXPERIENCE.checklist_progress')"
            />
            <span class="text-xs tabular-nums">
              {{
                t('JRC_SERVICE_DESK.EXPERIENCE.checklist_count', {
                  done: row.checklist.filter(item => item.done).length,
                  total: row.checklist.length,
                })
              }}
            </span>
          </div>
          <p
            v-if="row.parent_task_id"
            class="text-xs"
          >
            {{ t('JRC_SERVICE_DESK.R3.parent_task') }}:
            {{
              data.tasks.find(parent => parent.id === row.parent_task_id)
                ?.title || numberPrefix + row.parent_task_id
            }}
          </p>
          <p
            v-if="row.pending_children"
            class="text-xs"
          >
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
            />
            {{ item.title }}
          </label>
          <Button
            v-if="row.permissions.update && row.status === 'open'"
            size="xs"
            variant="outline"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.EXPERIENCE.start_task')"
            @click="updateTask(row, { status: 'in_progress' })"
          />
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
        <ServiceDeskDialog
          :open="taskDialog"
          :title="
            t(
              editingTask
                ? 'JRC_SERVICE_DESK.REDESIGN_DETAIL.edit_task'
                : 'JRC_SERVICE_DESK.COCKPIT.create_task'
            )
          "
          :busy="busy"
          @close="taskDialog = false"
        >
          <form
            v-if="permissions.tasks_manage"
            class="grid gap-3"
            @submit.prevent="saveTask"
          >
            <label class="text-sm">
              {{ t('JRC_SERVICE_DESK.COCKPIT.audience') }}
              <select
                v-model="visibility"
                :disabled="busy || !!editingTask"
                class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option
                  v-for="value in audiences"
                  :key="value"
                  :value="value"
                >
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
              v-model="taskDescription"
              :aria-label="t('JRC_SERVICE_DESK.FIELDS.description')"
              :placeholder="t('JRC_SERVICE_DESK.FIELDS.description')"
              rows="3"
              maxlength="20000"
              :disabled="busy"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
            />
            <textarea
              v-model="checklistText"
              :disabled="busy || terminalTask"
              :aria-label="t('JRC_SERVICE_DESK.COCKPIT.checklist')"
              :placeholder="t('JRC_SERVICE_DESK.COCKPIT.checklist')"
              class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
            />
            <input
              v-model="taskDue"
              :disabled="busy || terminalTask"
              type="datetime-local"
              :aria-label="t('JRC_SERVICE_DESK.COCKPIT.deadline')"
              class="border border-n-weak rounded-lg bg-n-solid-1 p-2"
            />
            <Lookup
              v-model="taskAssignee"
              resource="assignees"
              :unit-id="ticket.unit_id"
              :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
              :disabled="busy || terminalTask"
            />
            <label>
              {{ t('JRC_SERVICE_DESK.FIELDS.priority') }}
              <select
                v-model="taskPriority"
                :disabled="busy || terminalTask"
                class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option
                  v-for="value in ['low', 'normal', 'high', 'urgent']"
                  :key="value"
                  :value="value"
                >
                  {{ t(`JRC_SERVICE_DESK.R3.priority.${value}`) }}
                </option>
              </select>
            </label>
            <details class="rounded-lg border border-n-weak p-3">
              <summary class="cursor-pointer text-sm font-medium">
                {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.advanced_task') }}
              </summary>
              <div class="mt-3 grid gap-3">
                <label>
                  {{ t('JRC_SERVICE_DESK.R3.parent_task') }}
                  <select
                    v-model="parentTask"
                    :disabled="busy || !!editingTask"
                    class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
                  >
                    <option value="">
                      {{ t('JRC_SERVICE_DESK.COMMON.none') }}
                    </option>
                    <option
                      v-for="row in data.tasks.filter(
                        task =>
                          !['completed', 'cancelled'].includes(task.status)
                      )"
                      :key="row.id"
                      :value="row.id"
                    >
                      {{ row.title }}
                    </option>
                  </select>
                </label>
                <template
                  v-if="
                    !editingTask &&
                    canPublishProgression &&
                    permissions.lifecycle_inspect
                  "
                >
                  <label class="flex gap-2 text-sm">
                    <input
                      v-model="progressionEnabled"
                      type="checkbox"
                      @change="progressionEnabled && loadLifecycle()"
                    />
                    {{ t('JRC_SERVICE_DESK.R3.task_progression') }}
                  </label>
                  <template v-if="progressionEnabled">
                    <State
                      v-if="lifecycleStatus !== 'ready'"
                      :status="lifecycleStatus"
                      compact
                      retry
                      @retry="loadLifecycle"
                    />
                    <input
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
              </div>
            </details>
            <Button
              type="submit"
              :disabled="
                busy ||
                !taskTitle.trim() ||
                (progressionEnabled &&
                  (!lifecycle?.policy || !nextTaskTitle.trim()))
              "
              :label="
                t(
                  editingTask
                    ? 'JRC_SERVICE_DESK.COMMON.save'
                    : 'JRC_SERVICE_DESK.COCKPIT.create_task'
                )
              "
            />
            <p
              v-if="feedback"
              role="status"
              class="text-sm"
            >
              {{ labels.feedback[feedback] }}
            </p>
            <p
              v-if="failureReason"
              role="alert"
              class="text-sm text-n-ruby-11"
            >
              {{ failureReason }}
            </p>
          </form>
        </ServiceDeskDialog>
        <ServiceDeskDialog
          :open="!!deletingTask"
          :title="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delete_task')"
          :busy="busy"
          @close="deletingTask = null"
        >
          <form
            class="grid gap-4"
            @submit.prevent="removeTask"
          >
            <p class="text-sm">
              {{
                t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delete_task_help', {
                  title: deletingTask?.title,
                })
              }}
            </p>
            <label class="grid gap-2 text-sm">
              {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.reason') }}
              <textarea
                v-model="taskDeleteReason"
                required
                minlength="3"
                maxlength="1000"
                rows="3"
                :disabled="busy"
                class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
              />
            </label>
            <p
              v-if="feedback"
              role="status"
              class="text-sm"
            >
              {{ labels.feedback[feedback] }}
            </p>
            <p
              v-if="failureReason"
              role="alert"
              class="text-sm text-n-ruby-11"
            >
              {{ failureReason }}
            </p>
            <Button
              type="submit"
              color="ruby"
              :disabled="busy || taskDeleteReason.trim().length < 3"
              :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.confirm_delete')"
            />
          </form>
        </ServiceDeskDialog>
      </section>
      <section
        v-if="showTasks && permissions.approvals_view"
        class="grid gap-3"
      >
        <h3 class="font-semibold">
          {{ t('JRC_SERVICE_DESK.COCKPIT.approvals') }}
        </h3>
        <p
          v-if="!data.approvals.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
        </p>
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
          <p
            v-if="dueState(row, observedAt) === 'overdue'"
            class="text-xs text-n-ruby-11"
          >
            {{ t('JRC_SERVICE_DESK.EXPERIENCE.overdue') }}
          </p>
          <p
            v-if="row.comment"
            class="text-sm whitespace-pre-wrap"
          >
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
              />
              <Button
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
        <details
          v-if="permissions.approvals_request"
          class="rounded-lg border border-n-weak p-3"
        >
          <summary class="cursor-pointer text-sm font-medium">
            {{ t('JRC_SERVICE_DESK.COCKPIT.request_approval') }}
          </summary>
          <form
            class="grid gap-3 mt-3"
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
                  </option>
                </select>
                <select
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
                  </option>
                </select>
                <textarea
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
        </details>
      </section>
      <section
        v-if="mode === 'all' && permissions.view_sla"
        class="grid gap-3"
      >
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
      <p
        v-if="feedback"
        role="status"
        class="text-sm"
      >
        {{ labels.feedback[feedback] }}
      </p>
    </template>
  </div>
</template>
