<script setup>
import { computed, onBeforeUnmount, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LiveKpis from '../components/LiveKpis.vue';
import TicketFilters from '../components/TicketFilters.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import TicketTable from '../components/TicketTable.vue';
import PendingAction from '../components/PendingAction.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const session = useServiceDesk();
const key = 'overview:recent';
const recent = computed(() => session.resource(key));
const load = () => session.load(key, 'tickets', { ...route.query, page: 1, per_page: 5, sort: 'updated_at_desc' });
watch([() => session.state.status, () => route.query, () => session.operations?.state.revision], load, { immediate: true });
onBeforeUnmount(() => session.resetResource(key));
const go = (name, ticketId) => router.push({ name: serviceDeskRouteName(name), params: { accountId: session.accountId.value, ...(ticketId ? { ticketId } : {}) } });
const filterStatus = statusId => router.push({ name: serviceDeskRouteName('tickets'), params: { accountId: session.accountId.value }, query: { ...route.query, status_id: statusId, page: '1' } });
</script>
<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t('JRC_SERVICE_DESK.SCREENS.overview') }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.SUBTITLE') }}
        </p>
      </div>
      <Button
        v-if="session.state.context?.units.some(unit => unit.permissions.create_ticket === true)"
        :label="t('JRC_SERVICE_DESK.COMMON.open_structure')"
        icon="i-lucide-plus"
        size="sm"
        @click="go('new')"
      />
    </header>
    <TicketFilters :query="route.query" @apply="router.push({ query: $event })" />
    <LiveKpis :query="route.query" breakdown @status-filter="filterStatus" />
    <div class="sd-three-columns mb-4">
      <Panel
        v-for="chart in ['evolution', 'top_categories']"
        :key="chart"
        :title="t(`JRC_SERVICE_DESK.OVERVIEW.${chart}`)"
      >
        <State status="pending" compact :description="t('JRC_SERVICE_DESK.OVERVIEW.chart_help')" />
      </Panel>
    </div>
    <div class="sd-two-columns">
      <Panel :title="t('JRC_SERVICE_DESK.OVERVIEW.recent')" icon="i-lucide-ticket">
        <template #actions>
          <Button
            size="xs"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.OVERVIEW.recent_link')"
            @click="go('tickets')"
          />
        </template>
        <TicketTable
          v-if="recent.status === 'ready'"
          :items="recent.items"
          @open="go('detail', $event)"
          @preview="go('detail', $event)"
        />
        <State
          v-else
          :status="recent.status"
          retry
          @retry="session.state.status === 'ready' ? load() : session.retry()"
        />
      </Panel>
      <div class="grid gap-4">
        <Panel :title="t('JRC_SERVICE_DESK.OVERVIEW.shortcuts')">
          <div class="grid gap-2">
            <Button variant="outline" color="slate" :label="t('JRC_SERVICE_DESK.SCREENS.mine')" @click="go('mine')" />
            <Button variant="outline" color="slate" :label="t('JRC_SERVICE_DESK.SCREENS.queues')" @click="go('queues')" />
          </div>
        </Panel>
        <Panel :title="t('JRC_SERVICE_DESK.OVERVIEW.tasks')">
          <State status="pending" compact :description="t('JRC_SERVICE_DESK.OVERVIEW.tasks_help')" />
        </Panel>
        <Panel :title="t('JRC_SERVICE_DESK.OVERVIEW.copilot')">
          <p class="text-sm text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.OVERVIEW.copilot_help') }}
          </p>
          <PendingAction :label="t('JRC_SERVICE_DESK.COMMON.open')" />
        </Panel>
      </div>
    </div>
  </section>
</template>
