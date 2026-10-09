<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import OperationsLinks from '../../jrcOperations/components/OperationsLinks.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
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
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const session = useServiceDesk();
const key = 'ticket:detail';
const tab = ref('details');
const result = computed(() => session.resource(key));
const ticket = computed(() => result.value.record);
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
const tabs = computed(() =>
  visibleTabKeys.value.map(value => ({
    value,
    label: t(`JRC_SERVICE_DESK.TICKET.tabs.${value}`),
  }))
);
watch(visibleTabKeys, keys => {
  if (snapshotReceipt.value && result.value.status === 'loading') return;
  if (!keys.includes(tab.value)) tab.value = 'details';
});
const load = () => {
  tab.value = 'details';
  return session.load(key, 'tickets', {}, route.params.ticketId);
};
watch([() => route.params.ticketId, () => session.state.status], load, {
  immediate: true,
});
onBeforeUnmount(() => session.resetResource(key));
const go = name =>
  router.push({
    name: serviceDeskRouteName(name),
    params: {
      accountId: session.accountId.value,
      ...(name === 'tickets' ? {} : { ticketId: route.params.ticketId }),
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
watch(() => session.operations?.state.revision, refresh);
</script>

<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <Button
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-arrow-left"
          :label="t('JRC_SERVICE_DESK.SCREENS.tickets')"
          @click="go('tickets')"
        />
        <h2 v-if="!ticket" class="sd-page-title">
          {{ ticket?.title || t('JRC_SERVICE_DESK.SCREENS.detail') }}
        </h2>
      </div>
      <Button
        v-if="ticket && canAct(ticket, 'update')"
        :label="t('JRC_SERVICE_DESK.COMMON.edit')"
        icon="i-lucide-pencil"
        size="sm"
        @click="go('edit')"
      />
    </header>
    <TicketHeader v-if="ticket" :ticket="ticket" />
    <p v-if="confirmation" role="status" class="mb-4 text-sm">
      {{ publicationLabels[confirmation.outcome] }}
    </p>
    <div
      v-if="confirmedSnapshot"
      data-testid="snapshot-confirmed"
      role="status"
      class="mb-4 grid gap-1 text-xs break-words"
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
    <div class="overflow-x-auto mb-4">
      <TabBar
        :tabs="tabs"
        :initial-active-tab="visibleTabKeys.indexOf(tab)"
        @tab-changed="tab = $event.value"
      />
    </div>
    <div class="sd-two-columns">
      <Panel :title="t(`JRC_SERVICE_DESK.TICKET.tabs.${tab}`)">
        <State
          v-if="result.status !== 'ready'"
          :status="result.status"
          retry
          @retry="session.state.status === 'ready' ? load() : session.retry()"
        />
        <template v-else-if="tab === 'details'">
          <p class="text-sm text-n-slate-12 whitespace-pre-wrap break-words">
            {{ ticket.description || t('JRC_SERVICE_DESK.COMMON.no_value') }}
          </p>
          <div class="mt-6">
            <OperationsLinks :ticket-id="ticket.id" :title="ticket.title" />
            <CustomerContextPanel
              v-if="ticket.permissions.view_customer"
              :ticket="ticket"
            />
            <TicketCockpit
              :key="`${ticket.id}:cockpit`"
              :ticket="ticket"
              @updated="published"
            />
          </div>
        </template>
        <TicketCockpit
          v-else-if="['notes', 'tasks', 'files'].includes(tab)"
          :key="`${ticket.id}:${tab}`"
          :ticket="ticket"
          :mode="tab"
          @updated="published"
        />
        <div v-else-if="tab === 'conversation'" class="grid gap-4">
          <p class="text-sm text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.EXPERIENCE.communication_help') }}
          </p>
          <TicketCockpit
            v-if="ticket.permissions.view_notes"
            :key="`${ticket.id}:communication`"
            :ticket="ticket"
            mode="communication"
            @updated="published"
          />
          <details class="rounded-xl border border-n-weak p-3">
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
        </div>
        <LifecyclePanel
          v-else-if="
            ['solution', 'sla'].includes(tab) &&
            ticket.permissions.lifecycle_inspect
          "
          :ticket="ticket"
          @updated="refresh"
          @snapshot-recorded="snapshotRecorded"
        />
        <TicketActivity
          v-else-if="['sla', 'history'].includes(tab)"
          :key="`${ticket.id}:${tab}`"
          :ticket="ticket"
          :kind="
            {
              history: 'events',
            }[tab] || tab
          "
          @updated="refresh"
        />
        <template v-else>
          <State status="pending" />
        </template>
        <SlaSnapshotEditor
          v-if="
            result.status === 'ready' &&
            tab === 'sla' &&
            !ticket.permissions.lifecycle_inspect &&
            ticket.permissions.record_sla_snapshot
          "
          :ticket="ticket"
          @snapshot-recorded="snapshotRecorded"
        />
      </Panel>
      <div class="grid gap-4 sd-sticky">
        <Panel :title="t('JRC_SERVICE_DESK.FORM.summary')">
          <TicketSummary v-if="ticket" :ticket="ticket" />
          <State v-else :status="result.status" compact />
        </Panel>
        <LifecyclePanel
          v-if="
            ticket?.permissions.lifecycle_inspect &&
            !['solution', 'sla'].includes(tab)
          "
          :key="`${ticket.id}:lifecycle`"
          :ticket="ticket"
          @updated="refresh"
          @snapshot-recorded="snapshotRecorded"
        />
        <Panel :title="t('JRC_SERVICE_DESK.COMMON.actions')">
          <TicketOperations
            v-if="ticket"
            :key="ticket.id"
            :ticket="ticket"
            @updated="refresh"
          />
        </Panel>
      </div>
    </div>
  </section>
</template>
