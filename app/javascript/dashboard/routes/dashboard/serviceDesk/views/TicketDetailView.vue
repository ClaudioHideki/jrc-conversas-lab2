<script setup>
import CloseTicketForm from '../components/CloseTicketForm.vue';
import TicketAssetLinks from '../components/TicketAssetLinks.vue';
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import OperationsLinks from '../../jrcOperations/components/OperationsLinks.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import API from 'dashboard/api/serviceDeskCockpit';
import ServiceDeskDialog from '../components/ServiceDeskDialog.vue';
import TicketDetailsPanel from '../components/TicketDetailsPanel.vue';
import TicketTimeline from '../components/TicketTimeline.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import WriteFeedback from '../components/WriteFeedback.vue';
import TicketCockpit from '../components/TicketCockpit.vue';
import LifecyclePanel from '../components/LifecyclePanel.vue';
import SlaSnapshotEditor from '../components/SlaSnapshotEditor.vue';
import TicketOperations from '../components/TicketOperations.vue';
import TicketActivity from '../components/TicketActivity.vue';
import CustomerContextPanel from '../components/CustomerContextPanel.vue';
import TicketSummary from '../components/TicketSummary.vue';
import TicketHeader from '../components/TicketHeader.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { usePublicationConfirmation } from '../composables/usePublicationConfirmation';
import { communicationLabels } from '../helpers/communicationLabels';
import { canAct, canonicalId } from '../helpers/access';
import { serviceDeskRouteName } from '../routeDefinitions';
import {
  ticketListReturn,
  ticketNavigationContext,
} from '../helpers/ticketNavigation';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const session = useServiceDesk();
const key = 'ticket:detail';
const tab = ref('details');
const action = ref('');
const lifecycleBusy = ref(false);
const sidebarOpen = ref(true);
const createTaskOnOpen = ref(false);
const deletionReason = ref('');
const deleteStatus = ref('idle');
const deleteMessage = ref('');
let alive = true;
let deletionEpoch = 0;
let deletionController = new AbortController();
const deleting = computed(() => deleteStatus.value === 'saving');
const result = computed(() => session.resource(key));
const ticket = computed(() => result.value.record);
const editConfirmed = computed(() => {
  const mutation = session.operations?.mutation?.('ticket:form:write');
  const saved = mutation?.ticket;
  return (
    result.value.status === 'ready' &&
    mutation?.status === 'confirmed' &&
    saved?.id === ticket.value?.id &&
    saved?.account_id === session.accountId.value &&
    saved?.unit_id === ticket.value?.unit_id &&
    saved?.lock_version === ticket.value?.lock_version
  );
});
const { confirmation, accept } = usePublicationConfirmation(
  session,
  route,
  result
);
const publicationLabels = computed(() => communicationLabels(t));
const snapshotReceipt = ref(null);
const snapshotAuthorized = receipt => {
  const context = session.state.context;
  const current = ticket.value;
  return (
    session.state.status === 'ready' &&
    context?.available === true &&
    receipt.account_id === context.account_id &&
    receipt.account_id === canonicalId(route.params.accountId) &&
    receipt.account_id === session.accountId.value &&
    receipt.user_id === canonicalId(context.user_id) &&
    receipt.user_id === session.userId.value &&
    receipt.ticket_id === canonicalId(route.params.ticketId) &&
    current?.id === receipt.ticket_id &&
    current.account_id === receipt.account_id &&
    current.unit_id === receipt.unit_id &&
    context.units.some(unit => unit.id === receipt.unit_id) &&
    current.permissions?.record_sla_snapshot === true &&
    (!receipt.snapshot.permissions.show ||
      current.permissions.view_contract_conditions === true)
  );
};
const confirmedSnapshot = computed(() =>
  snapshotReceipt.value &&
  result.value.status === 'ready' &&
  snapshotAuthorized(snapshotReceipt.value)
    ? snapshotReceipt.value.snapshot
    : null
);
const tabKeys = [
  'details',
  'conversation',
  'notes',
  'tasks',
  'files',
  'sla',
  'history',
  'solution',
];
const visibleTabKeys = computed(() =>
  tabKeys.filter(value => {
    const permission = {
      notes: 'view_notes',
      files: 'view_notes',
      tasks: 'tasks_view',
      history: 'view_history',
      conversation: 'view_conversations',
      sla: 'view_sla',
      solution: 'lifecycle_inspect',
    }[value];
    return !permission || ticket.value?.permissions?.[permission] === true;
  })
);
const tabTheme = {
  details: ['blue', 'i-lucide-ticket'],
  conversation: ['teal', 'i-lucide-messages-square'],
  notes: ['iris', 'i-lucide-sticky-note'],
  tasks: ['blue', 'i-lucide-list-checks'],
  files: ['iris', 'i-lucide-paperclip'],
  sla: ['amber', 'i-lucide-timer'],
  history: ['blue', 'i-lucide-history'],
  solution: ['teal', 'i-lucide-circle-check'],
};
const tabs = computed(() =>
  visibleTabKeys.value.map(value => ({
    value,
    label: t(`JRC_SERVICE_DESK.TICKET.tabs.${value}`),
  }))
);
watch(visibleTabKeys, keys => {
  if (result.value.status !== 'ready' || !ticket.value) return;
  if (!keys.includes(tab.value)) tab.value = 'details';
});
const load = () => {
  action.value = '';
  tab.value = tabKeys.includes(route.query?.tab) ? route.query.tab : 'details';
  if (!canonicalId(route.params.ticketId)) return session.resetResource(key);
  return session.load(key, 'tickets', {}, route.params.ticketId);
};
watch([() => route.params.ticketId, () => session.state.status], load, {
  immediate: true,
});
watch(
  [
    () => route.params.accountId,
    () => route.params.ticketId,
    () => session.state.context,
    () => session.state.status,
  ],
  () => {
    deletionEpoch += 1;
    deletionController.abort();
    deletionController = new AbortController();
    deleteStatus.value = 'idle';
    deleteMessage.value = '';
  },
  { flush: 'sync' }
);
onBeforeUnmount(() => {
  alive = false;
  deletionEpoch += 1;
  deletionController.abort();
  session.resetResource(key);
});
const go = (name, section = 0) =>
  router.push({
    name: serviceDeskRouteName(
      name === 'tickets' ? ticketListReturn(route.query).screen : name
    ),
    params: {
      accountId: session.accountId.value,
      ...(name === 'tickets' ? {} : { ticketId: route.params.ticketId }),
    },
    query:
      name === 'tickets'
        ? ticketListReturn(route.query).query
        : {
            ...ticketNavigationContext(route.query),
            ...(name === 'edit'
              ? { edit_section: String(section), tab: tab.value }
              : {}),
          },
  });
const refresh = () => session.load(key, 'tickets', {}, route.params.ticketId);
const published = publication => {
  accept(publication);
  return refresh();
};
const snapshotRecorded = receipt => {
  const record = receipt?.snapshot;
  if (
    !canonicalId(record?.id) ||
    !Number.isSafeInteger(record.version) ||
    record.version <= 0 ||
    typeof record.permissions?.show !== 'boolean' ||
    (record.permissions.show &&
      !/^[a-f0-9]{64}$/.test(record.payload_digest)) ||
    !snapshotAuthorized(receipt)
  )
    return undefined;
  snapshotReceipt.value = {
    account_id: receipt.account_id,
    user_id: receipt.user_id,
    unit_id: receipt.unit_id,
    ticket_id: receipt.ticket_id,
    snapshot: {
      id: canonicalId(record.id),
      version: record.version,
      permissions: { show: record.permissions.show },
      ...(record.permissions.show
        ? { payload_digest: record.payload_digest }
        : {}),
    },
  };
  return refresh();
};
watch(
  [
    () => route.params.accountId,
    () => route.params.ticketId,
    () => session.accountId.value,
    () => session.state.context,
    () => session.state.context?.user_id,
    () => session.userId.value,
    () => session.state.context?.available,
    () => session.state.context?.units.map(unit => unit.id).join(','),
    () => session.state.status,
  ],
  () => {
    snapshotReceipt.value = null;
  },
  { flush: 'sync' }
);
watch(
  [
    () => result.value.status,
    () => ticket.value,
    () => ticket.value?.unit_id,
    () => ticket.value?.permissions?.record_sla_snapshot,
    () => ticket.value?.permissions?.view_contract_conditions,
  ],
  () => {
    if (!snapshotReceipt.value || result.value.status === 'loading') return;
    if (
      result.value.status !== 'ready' ||
      !snapshotAuthorized(snapshotReceipt.value)
    )
      snapshotReceipt.value = null;
  }
);
watch(
  () => session.operations?.state.revision,
  () => {
    // The active form closes after its verified write; refreshing now would unmount it first.
    if (!action.value) refresh();
  }
);
watch(
  () => route.query?.tab,
  value => {
    if (visibleTabKeys.value.includes(value)) tab.value = value;
  }
);
const selectTab = value => {
  if (!visibleTabKeys.value.includes(value)) return;
  createTaskOnOpen.value = false;
  tab.value = value;
  router.replace({ query: { ...route.query, tab: value } });
};
const navigateTabs = event => {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  event.preventDefault();
  const keys = visibleTabKeys.value;
  const index = keys.indexOf(tab.value);
  const offset = event.key === 'ArrowRight' ? 1 : -1;
  const next =
    { Home: 0, End: keys.length - 1 }[event.key] ??
    (index + offset + keys.length) % keys.length;
  selectTab(keys[next]);
  event.currentTarget.querySelector(`[data-tab="${keys[next]}"]`)?.focus();
};
const addTask = () => {
  selectTab('tasks');
  createTaskOnOpen.value = true;
};
const actionUpdated = async () => {
  action.value = '';
  await refresh();
};
const actionTitle = computed(() =>
  action.value === 'closure'
    ? t('JRC_SERVICE_DESK.REFINEMENT.closure.title')
    : t(`JRC_SERVICE_DESK.REDESIGN_DETAIL.actions.${action.value || 'status'}`)
);
const deleteTicket = async () => {
  if (
    deleting.value ||
    !ticket.value?.permissions.destroy ||
    deletionReason.value.trim().length < 3
  )
    return;
  const context = session.state.context;
  const record = ticket.value;
  const turn = deletionEpoch;
  const current = () =>
    alive &&
    turn === deletionEpoch &&
    context === session.state.context &&
    session.state.status === 'ready' &&
    record.id === ticket.value?.id &&
    record.id === canonicalId(route.params.ticketId);
  deleteStatus.value = 'saving';
  deleteMessage.value = '';
  try {
    const ack = await API.deleteTicket(
      record.account_id,
      record,
      deletionReason.value.trim(),
      deletionController.signal
    );
    if (!current()) return;
    if (
      ack.applied !== true ||
      ack.operation !== 'delete' ||
      String(ack.ticket_id) !== record.id ||
      String(ack.account_id) !== record.account_id
    )
      throw new Error('Invalid delete acknowledgement');
    action.value = '';
    await go('tickets');
  } catch (error) {
    if (!current()) return;
    if (error.response?.data?.code === 'deletion_blocked')
      deleteMessage.value = error.response.data.error || '';
    deleteStatus.value =
      { 403: 'denied', 404: 'not_found', 409: 'conflict', 422: 'dependency' }[
        error.response?.status
      ] || 'error';
  }
};
</script>

<template>
  <section class="min-w-0">
    <div class="mb-3 flex items-center justify-between gap-3">
      <Button
        size="xs"
        variant="ghost"
        color="slate"
        icon="i-lucide-arrow-left"
        :label="t('JRC_SERVICE_DESK.SCREENS.tickets')"
        @click="go('tickets')"
      />
      <Button
        v-if="ticket"
        size="xs"
        color="slate"
        variant="ghost"
        :icon="
          sidebarOpen
            ? 'i-lucide-panel-right-close'
            : 'i-lucide-panel-right-open'
        "
        :label="
          t(
            sidebarOpen
              ? 'JRC_SERVICE_DESK.REDESIGN_DETAIL.hide_summary'
              : 'JRC_SERVICE_DESK.REDESIGN_DETAIL.show_summary'
          )
        "
        @click="sidebarOpen = !sidebarOpen"
      />
    </div>
    <TicketHeader v-if="ticket" :ticket="ticket">
      <template #actions>
        <Button
          v-if="ticket.permissions.lifecycle_inspect"
          data-testid="close-ticket-shortcut"
          size="sm"
          color="teal"
          icon="i-lucide-circle-check"
          :label="t('JRC_SERVICE_DESK.REFINEMENT.closure.title')"
          @click="action = 'closure'"
        />
        <Button
          v-if="ticket.permissions.view_conversations"
          size="xs"
          color="slate"
          variant="outline"
          icon="i-lucide-reply"
          :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.reply')"
          @click="selectTab('conversation')"
        />
        <Button
          v-if="ticket.permissions.lifecycle_inspect"
          size="xs"
          color="slate"
          variant="outline"
          icon="i-lucide-refresh-cw"
          :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.actions.status')"
          @click="action = 'status'"
        />
        <Button
          v-if="ticket.permissions.transfer"
          size="xs"
          color="slate"
          variant="outline"
          icon="i-lucide-user-round-cog"
          :label="t('JRC_SERVICE_DESK.TICKET.transfer')"
          @click="action = 'transfer'"
        />
        <Button
          v-if="
            ticket.permissions.tasks_manage && ticket.permissions.tasks_view
          "
          size="xs"
          color="slate"
          variant="outline"
          icon="i-lucide-list-plus"
          :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.add_task')"
          @click="addTask"
        />
        <details
          v-if="ticket.permissions.update || ticket.permissions.destroy"
          class="relative"
        >
          <summary
            class="cursor-pointer rounded-lg border border-n-weak px-3 py-1.5 text-xs font-medium"
          >
            {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.more_actions') }}
          </summary>
          <div
            class="absolute right-0 z-20 mt-2 grid min-w-44 gap-1 rounded-xl border border-n-weak bg-n-solid-1 p-2 shadow-lg"
          >
            <Button
              v-if="canAct(ticket, 'update')"
              size="xs"
              color="slate"
              variant="ghost"
              icon="i-lucide-pencil"
              :label="t('JRC_SERVICE_DESK.SCREENS.edit')"
              @click="go('edit')"
            />
            <Button
              v-if="ticket.permissions.destroy"
              size="xs"
              color="ruby"
              variant="ghost"
              icon="i-lucide-trash-2"
              :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delete_ticket')"
              @click="
                action = 'delete';
                deletionReason = '';
                deleteStatus = 'idle';
                deleteMessage = '';
              "
            />
          </div>
        </details>
      </template>
    </TicketHeader>
    <WriteFeedback v-if="editConfirmed" status="confirmed" />
    <p v-if="confirmation" role="status" class="mb-4 text-sm">
      {{ publicationLabels[confirmation.outcome] }}
    </p>
    <div
      v-if="confirmedSnapshot"
      data-testid="snapshot-confirmed"
      role="status"
      class="mb-4 grid gap-1 break-words text-xs"
    >
      <p>
        {{
          t(
            confirmedSnapshot.permissions.show
              ? 'JRC_SERVICE_DESK.SNAPSHOT.feedback.confirmed'
              : 'JRC_SERVICE_DESK.SNAPSHOT.feedback.recorded_restricted'
          )
        }}
      </p>
      <p>
        {{
          t('JRC_SERVICE_DESK.SNAPSHOT.receipt', {
            id: confirmedSnapshot.id,
            version: confirmedSnapshot.version,
          })
        }}
      </p>
      <p v-if="confirmedSnapshot.permissions.show">
        {{ confirmedSnapshot.payload_digest }}
      </p>
    </div>
    <nav
      v-if="ticket"
      class="mb-4 flex flex-wrap gap-1 border-b border-n-weak"
      role="tablist"
      :aria-label="t('JRC_SERVICE_DESK.SCREENS.detail')"
      @keydown="navigateTabs"
    >
      <button
        v-for="item in tabs"
        :id="`sd-tab-${item.value}`"
        :key="item.value"
        :data-tab="item.value"
        type="button"
        role="tab"
        :aria-selected="tab === item.value"
        aria-controls="sd-ticket-content"
        :tabindex="tab === item.value ? 0 : -1"
        class="flex items-center gap-2 border-b-2 px-3 py-3 text-sm font-medium focus-visible:ring-2 focus-visible:ring-n-blue-9"
        :class="
          tab === item.value
            ? 'border-n-blue-9 text-n-blue-11'
            : 'border-transparent text-n-slate-11 hover:bg-n-solid-2'
        "
        @click="selectTab(item.value)"
      >
        <Icon :icon="tabTheme[item.value][1]" class="size-4" />{{ item.label }}
      </button>
    </nav>
    <State
      v-if="result.status !== 'ready' || !ticket"
      :status="result.status"
      retry
      @retry="session.state.status === 'ready' ? load() : session.retry()"
    />
    <div
      v-else
      class="grid items-start gap-4"
      :class="
        sidebarOpen ? 'xl:grid-cols-[minmax(0,1fr)_18rem]' : 'grid-cols-1'
      "
    >
      <div
        id="sd-ticket-content"
        class="min-w-0"
        role="tabpanel"
        :aria-labelledby="`sd-tab-${tab}`"
      >
        <div v-if="tab === 'details'" class="grid gap-4">
          <TicketDetailsPanel
            :ticket="ticket"
            @edit="go('edit', $event)"
            @action="action = $event"
          />
          <Panel :title="t('JRC_SERVICE_DESK.TICKET.tabs.related')">
            <OperationsLinks :ticket-id="ticket.id" :title="ticket.title" />
            <TicketAssetLinks :ticket="ticket" />
            <CustomerContextPanel
              v-if="ticket.permissions.view_customer"
              :ticket="ticket"
            />
          </Panel>
        </div>
        <Panel
          v-else-if="['notes', 'tasks', 'files', 'conversation'].includes(tab)"
          :title="t(`JRC_SERVICE_DESK.TICKET.tabs.${tab}`)"
        >
          <TicketCockpit
            :key="`${ticket.id}:${tab}`"
            :ticket="ticket"
            :mode="tab === 'conversation' ? 'communication' : tab"
            :create-task-on-open="createTaskOnOpen"
            @task-editor-opened="createTaskOnOpen = false"
            @updated="published"
          />
          <details
            v-if="tab === 'conversation'"
            class="mt-4 rounded-lg border border-n-weak p-3"
          >
            <summary class="cursor-pointer text-sm font-medium">
              {{ t('JRC_SERVICE_DESK.EXPERIENCE.linked_conversations') }}
            </summary>
            <TicketActivity
              :key="`${ticket.id}:conversations`"
              :ticket="ticket"
              kind="conversations"
              @updated="refresh"
            />
          </details>
        </Panel>
        <LifecyclePanel
          v-else-if="
            ['solution', 'sla'].includes(tab) &&
            ticket.permissions.lifecycle_inspect
          "
          :key="`${ticket.id}:${tab}`"
          :ticket="ticket"
          :mode="tab"
          @updated="refresh"
          @snapshot-recorded="snapshotRecorded"
        />
        <Panel
          v-else-if="tab === 'history'"
          :title="t('JRC_SERVICE_DESK.TICKET.tabs.history')"
        >
          <TicketTimeline :ticket="ticket" view="history" />
        </Panel>
        <Panel
          v-else-if="tab === 'sla'"
          :title="t('JRC_SERVICE_DESK.TICKET.tabs.sla')"
        >
          <TicketActivity :ticket="ticket" kind="sla" @updated="refresh" />
          <SlaSnapshotEditor
            v-if="ticket.permissions.record_sla_snapshot"
            :ticket="ticket"
            @snapshot-recorded="snapshotRecorded"
          />
        </Panel>
      </div>
      <aside v-if="sidebarOpen" class="min-w-0 xl:sticky xl:top-4">
        <Panel :title="t('JRC_SERVICE_DESK.FORM.summary')">
          <TicketSummary :ticket="ticket" compact />
          <div class="mt-4 flex flex-wrap gap-2">
            <Button
              v-if="ticket.permissions.update"
              size="xs"
              color="slate"
              variant="outline"
              icon="i-lucide-pencil"
              :label="t('JRC_SERVICE_DESK.COMMON.edit')"
              @click="go('edit')"
            />
            <Button
              v-if="ticket.permissions.view_sla"
              size="xs"
              color="slate"
              variant="ghost"
              :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.view_sla')"
              @click="selectTab('sla')"
            />
          </div>
        </Panel>
      </aside>
    </div>
    <ServiceDeskDialog
      :open="!!action && !!ticket"
      :title="actionTitle"
      :compact="action === 'closure'"
      :busy="deleting || lifecycleBusy"
      @close="action = ''"
    >
      <form
        v-if="action === 'delete'"
        class="grid gap-4"
        @submit.prevent="deleteTicket"
      >
        <p class="text-sm">
          {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.delete_ticket_help') }}
        </p>
        <label class="grid gap-2 text-sm"
          >{{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.reason')
          }}<textarea
            v-model="deletionReason"
            required
            minlength="3"
            maxlength="1000"
            rows="3"
            :disabled="deleting"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          />
        </label>
        <WriteFeedback :status="deleteStatus" />
        <p v-if="deleteMessage" role="alert" class="text-sm text-n-ruby-11">
          {{ deleteMessage }}
        </p>
        <Button
          type="submit"
          color="ruby"
          :disabled="deleting || deletionReason.trim().length < 3"
          :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.confirm_delete')"
        />
      </form>
      <CloseTicketForm
        v-else-if="action === 'closure'"
        :ticket="ticket"
        @busy-change="lifecycleBusy = $event"
        @updated="actionUpdated"
        @cancel="action = ''"
        @refresh="refresh"
      />
      <LifecyclePanel
        v-else-if="action === 'status'"
        :key="action"
        :ticket="ticket"
        mode="actions"
        @busy-change="lifecycleBusy = $event"
        @updated="actionUpdated"
        @snapshot-recorded="snapshotRecorded"
      />
      <TicketOperations
        v-else-if="ticket && action"
        :key="action"
        :ticket="ticket"
        :initial-action="action"
        @updated="actionUpdated"
      />
    </ServiceDeskDialog>
  </section>
</template>
