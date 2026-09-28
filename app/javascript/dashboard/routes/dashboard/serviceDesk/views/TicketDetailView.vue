<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import PendingAction from '../components/PendingAction.vue';
import LifecyclePanel from '../components/LifecyclePanel.vue';
import TicketOperations from '../components/TicketOperations.vue';
import TicketActivity from '../components/TicketActivity.vue';
import CustomerContextPanel from '../components/CustomerContextPanel.vue';
import TicketSummary from '../components/TicketSummary.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canAct } from '../helpers/access';
import { serviceDeskRouteName } from '../routeDefinitions';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const session = useServiceDesk();
const key = 'ticket:detail';
const tab = ref('details');
const result = computed(() => session.resource(key));
const ticket = computed(() => result.value.record);
const tabKeys = ['details', 'conversation', 'notes', 'tasks', 'files', 'sla', 'related', 'history', 'solution'];
const visibleTabKeys = computed(() => tabKeys.filter(value => {
  const permission = { notes: 'view_notes', history: 'view_history', related: 'view_conversations', conversation: 'view_conversations', sla: 'view_sla', solution: 'lifecycle_inspect' }[value];
  return !permission || ticket.value?.permissions?.[permission] === true;
}));
const tabs = computed(() => visibleTabKeys.value.map(value => ({ value, label: t(`JRC_SERVICE_DESK.TICKET.tabs.${value}`) })));
watch(visibleTabKeys, keys => { if (!keys.includes(tab.value)) tab.value = 'details'; });
const load = () => { tab.value = 'details'; return session.load(key, 'tickets', {}, route.params.ticketId); };
watch([() => route.params.ticketId, () => session.state.status], load, { immediate: true });
onBeforeUnmount(() => session.resetResource(key));
const go = name => router.push({ name: serviceDeskRouteName(name), params: { accountId: session.accountId.value, ...(name === 'tickets' ? {} : { ticketId: route.params.ticketId }) } });
const refresh = () => session.load(key, 'tickets', {}, route.params.ticketId);
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
        <h2 class="sd-page-title">
          {{ ticket?.title || t('JRC_SERVICE_DESK.SCREENS.detail') }}
        </h2>
        <p v-if="ticket" class="sd-page-subtitle">
          {{ ticket.number || ticket.id }}
        </p>
      </div>
      <Button
        v-if="ticket && canAct(ticket, 'update')"
        :label="t('JRC_SERVICE_DESK.COMMON.edit')"
        icon="i-lucide-pencil"
        size="sm"
        @click="go('edit')"
      />
    </header>
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
            <TicketSummary :ticket="ticket" />
            <CustomerContextPanel v-if="ticket.permissions.view_customer" :ticket="ticket" />
          </div>
        </template>
        <LifecyclePanel v-else-if="['solution', 'sla'].includes(tab) && ticket.permissions.lifecycle_inspect" :ticket="ticket" @updated="refresh" />
        <TicketActivity v-else-if="['sla', 'notes', 'history', 'related'].includes(tab)" :key="`${ticket.id}:${tab}`" :ticket="ticket" :kind="({ history: 'events', related: 'conversations' })[tab] || tab" @updated="refresh" />
        <template v-else>
          <State status="pending" />
          <PendingAction v-if="tab === 'conversation'" :label="t('JRC_SERVICE_DESK.TICKET.send')" />
          <PendingAction v-if="tab === 'files'" :label="t('JRC_SERVICE_DESK.TICKET.upload')" />
        </template>
      </Panel>
      <div class="grid gap-4 sd-sticky">
        <Panel :title="t('JRC_SERVICE_DESK.FORM.summary')">
          <TicketSummary v-if="ticket" :ticket="ticket" />
          <State v-else :status="result.status" compact />
        </Panel>
        <LifecyclePanel v-if="ticket?.permissions.lifecycle_inspect && !['solution', 'sla'].includes(tab)" :key="`${ticket.id}:lifecycle`" :ticket="ticket" @updated="refresh" />
        <Panel :title="t('JRC_SERVICE_DESK.COMMON.actions')">
          <TicketOperations v-if="ticket" :key="ticket.id" :ticket="ticket" @updated="refresh" />
        </Panel>
      </div>
    </div>
  </section>
</template>
