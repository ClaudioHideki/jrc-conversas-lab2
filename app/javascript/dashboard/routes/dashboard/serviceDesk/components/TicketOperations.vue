<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import State from './ServiceDeskState.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Lookup from './LookupSelect.vue';
import Feedback from './WriteFeedback.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { selfAssignment } from '../helpers/selfAssignment';
const props = defineProps({
  ticket: { type: Object, required: true },
  initialAction: { type: String, default: '' },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const session = useServiceDesk();
const key = `ticket:actions:${props.ticket.id}`;
const selfAssignee = computed(() =>
  selfAssignment(session.state.context, props.ticket)
);
const optionsKey = `${key}:statuses`;
const mode = ref(props.initialAction);
const optionsPage = ref(1);
const fields = reactive({
  assignee_account_user_id: '',
  team_id: '',
  queue_id: '',
  status_id: '',
  priority_id: '',
});
const queueSelected = queue => {
  const teamId = queue?.team?.id || '';
  if (teamId !== fields.team_id) fields.assignee_account_user_id = '';
  fields.team_id = teamId;
};
const mutation = computed(
  () => session.operations?.mutation(key) || { status: 'idle' }
);
const busy = computed(() => mutation.value.status === 'saving');
const optionsResult = computed(
  () =>
    session.operations?.resource(optionsKey) || { status: 'idle', data: null }
);
const options = computed(() => optionsResult.value.data?.items || []);
watch(
  () => props.ticket,
  ticket => {
    fields.assignee_account_user_id = ticket.assignee?.id || '';
    fields.team_id = ticket.team?.id || '';
    fields.priority_id = ticket.priority?.id || '';
    fields.queue_id = ticket.queue?.id || '';
    fields.status_id = ticket.status?.id || '';
  },
  { immediate: true }
);
const loadOptions = () =>
  session.operations?.read(optionsKey, 'status_options', {
    ticket: props.ticket,
    query: { page: optionsPage.value, per_page: 20 },
  });
watch(
  [mode, optionsPage],
  ([value]) => {
    if (value === 'work_status') loadOptions();
  },
  { immediate: true }
);
const submit = async () => {
  if (!session.operations || busy.value) return;
  const payload = {
    ticketId: props.ticket.id,
    expected_lock_version: props.ticket.lock_version,
  };
  if (mode.value === 'assume') {
    if (!selfAssignee.value) return;
    payload.assignment = { assignee_account_user_id: selfAssignee.value.id };
  } else if (mode.value === 'priority')
    payload.ticket = { priority_id: fields.priority_id };
  else if (mode.value === 'work_status') payload.status_id = fields.status_id;
  else {
    payload.assignment = {
      assignee_account_user_id: fields.assignee_account_user_id || null,
      queue_id: fields.queue_id || null,
    };
    // Blank team delegates to the selected queue rather than forcing an inconsistent null.
    if (fields.team_id) payload.assignment.team_id = fields.team_id;
  }
  const operation = mode.value === 'priority' ? 'update' : mode.value;
  const result = await session.operations.write(
    key,
    mode.value === 'assume' ? 'assign' : operation,
    payload,
    props.ticket
  );
  if (result) {
    mode.value = '';
    emit('updated', result);
  }
};
onBeforeUnmount(() => {
  session.operations?.cancel(key);
  session.operations?.cancel(optionsKey);
});
</script>

<template>
  <div class="grid gap-3">
    <div v-if="!initialAction" class="flex flex-wrap gap-2">
      <Button
        v-if="ticket.permissions.assign"
        :disabled="busy || !session.operations"
        size="sm"
        variant="outline"
        :label="t('JRC_SERVICE_DESK.OPS.assignment')"
        @click="mode = mode === 'assign' ? '' : 'assign'"
      />
      <Button
        v-if="ticket.permissions.transfer"
        :disabled="busy || !session.operations"
        size="sm"
        variant="outline"
        :label="t('JRC_SERVICE_DESK.NATIVE.transfer')"
        @click="mode = mode === 'transfer' ? '' : 'transfer'"
      />
      <Button
        v-if="ticket.permissions.change_priority"
        :disabled="busy || !session.operations"
        size="sm"
        variant="outline"
        :label="t('JRC_SERVICE_DESK.NATIVE.change_priority')"
        @click="mode = mode === 'priority' ? '' : 'priority'"
      />
      <Button
        v-if="ticket.permissions.change_work_status"
        :disabled="busy || !session.operations"
        size="sm"
        variant="outline"
        :label="t('JRC_SERVICE_DESK.OPS.work_status')"
        @click="mode = mode === 'work_status' ? '' : 'work_status'"
      />
    </div>
    <form v-if="mode" class="grid gap-3" @submit.prevent="submit">
      <dl
        v-if="mode === 'assume' && selfAssignee"
        class="rounded-xl border border-n-weak bg-n-alpha-1 p-4"
      >
        <dt class="text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.FIELDS.assignee') }}
        </dt>
        <dd class="mt-1 text-base font-semibold">{{ selfAssignee.name }}</dd>
      </dl>
      <template v-else-if="['assign', 'transfer'].includes(mode)">
        <p class="text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.OPS.same_unit') }}
        </p>
        <Lookup
          v-model="fields.assignee_account_user_id"
          resource="assignees"
          :team-id="fields.team_id"
          :queue-id="fields.queue_id"
          :unit-id="ticket.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.assignee')"
          :current-name="
            fields.assignee_account_user_id === ticket.assignee?.id
              ? ticket.assignee?.name || ''
              : ''
          "
          :disabled="busy"
        />
        <Lookup
          v-model="fields.queue_id"
          resource="queues"
          :unit-id="ticket.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.queue')"
          :current-name="ticket.queue?.name || ''"
          :disabled="busy"
          @selected="queueSelected"
        />
        <Lookup
          v-model="fields.team_id"
          resource="teams"
          :unit-id="ticket.unit_id"
          :label="t('JRC_SERVICE_DESK.FIELDS.team')"
          :current-name="
            fields.team_id === ticket.team?.id ? ticket.team?.name || '' : ''
          "
          :disabled="busy"
          @update:model-value="fields.assignee_account_user_id = ''"
        />
      </template>
      <Lookup
        v-else-if="mode === 'priority'"
        v-model="fields.priority_id"
        resource="priorities"
        :unit-id="ticket.unit_id"
        :label="t('JRC_SERVICE_DESK.FIELDS.priority')"
        :current-name="ticket.priority?.name || ''"
        :disabled="busy"
      />
      <template v-else-if="mode === 'work_status'">
        <p class="text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.OPS.work_status_help') }}
        </p>
        <State
          v-if="optionsResult.status !== 'ready'"
          :status="optionsResult.status"
          compact
          retry
          @retry="loadOptions"
        />
        <Pagination
          v-if="optionsResult.data?.meta?.total > 20"
          :current-page="optionsPage"
          :items-per-page="20"
          :total-items="optionsResult.data.meta.total"
          @update:current-page="optionsPage = $event"
        />
        <Select
          v-model="fields.status_id"
          :disabled="busy || !options.length"
          :options="options.map(row => ({ value: row.id, label: row.name }))"
        />
      </template>
      <Button
        type="submit"
        :disabled="
          busy ||
          (mode === 'assume' && !selfAssignee) ||
          (mode === 'work_status' &&
            !options.some(row => row.id === fields.status_id))
        "
        :label="
          mode === 'assume'
            ? t('CONVERSATION.ASSIGN_TO_ME')
            : t('JRC_SERVICE_DESK.COMMON.save')
        "
      />
    </form>
    <Feedback :status="mutation.status" />
  </div>
</template>
