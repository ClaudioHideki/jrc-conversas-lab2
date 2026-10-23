<script setup>
import { computed, onBeforeUnmount, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LiveKpis from '../components/LiveKpis.vue';
import OverviewSignals from '../components/OverviewSignals.vue';
import TicketFilters from '../components/TicketFilters.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import TicketTable from '../components/TicketTable.vue';
import OverviewOperations from '../components/OverviewOperations.vue';
import { ticketListContext } from '../helpers/ticketNavigation';
import { useSupervisionReport } from '../composables/useSupervisionReport.js';
import { metricQuery } from '../helpers/screenExperience.js';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const session = useServiceDesk();
const key = 'overview:recent';
const recent = computed(() => session.resource(key));
const {
  result: supervision,
  status: reportStatus,
  load: reloadReport,
} = useSupervisionReport(session, () => ({
  ...route.query,
  per_page: 5,
  page: 1,
}));
const load = () =>
  session.load(key, 'tickets', {
    ...route.query,
    page: 1,
    per_page: 5,
    sort: 'updated_at_desc',
  });
watch(
  [
    () => session.state.status,
    () => route.query,
    () => session.operations?.state.revision,
  ],
  load,
  { immediate: true }
);
onBeforeUnmount(() => session.resetResource(key));
const go = (name, ticketId, filters = {}) => {
  let query;
  if (['tickets', 'mine', 'sla'].includes(name)) {
    query = {
      ...route.query,
      ...filters,
      ...(name === 'mine' ? { mine: 'true', assignment: undefined } : {}),
    };
  } else if (['queues', 'tasks', 'approvals'].includes(name)) {
    query = {
      unit_id: route.query.unit_id,
      operator_company_id: route.query.operator_company_id,
      ...(filters.status ? { status: filters.status } : {}),
    };
  } else if (name === 'detail') {
    query = ticketListContext('tickets', route.query);
  }
  return router.push({
    name: serviceDeskRouteName(name),
    params: {
      accountId: session.accountId.value,
      ...(ticketId ? { ticketId } : {}),
    },
    ...(query ? { query } : {}),
  });
};
const filterStatus = statusId =>
  router.push({
    name: serviceDeskRouteName('tickets'),
    params: { accountId: session.accountId.value },
    query: { ...route.query, phase: undefined, status_id: statusId, page: '1' },
  });
</script>

<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t('JRC_SERVICE_DESK.MODULE') }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.SUBTITLE') }}
        </p>
      </div>
      <Button
        v-if="
          session.state.context?.units.some(
            unit => unit.permissions.create_ticket === true
          )
        "
        :label="t('JRC_SERVICE_DESK.COMMON.open_structure')"
        icon="i-lucide-plus"
        size="sm"
        @click="go('new')"
      />
    </header>
    <TicketFilters
      compact
      :query="route.query"
      @apply="router.push({ query: $event })"
    />
    <LiveKpis
      reference-layout
      :supervision="reportStatus === 'ready' ? supervision?.supervision : null"
      :query="route.query"
      @status-filter="filterStatus"
      @metric-filter="
        router.push({
          name: serviceDeskRouteName('tickets'),
          params: { accountId: session.accountId.value },
          query: metricQuery(route.query, $event),
        })
      "
    />
    <div class="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_17rem]">
      <div class="min-w-0">
        <template v-if="session.state.context?.capabilities?.reports?.index">
          <OverviewOperations
            v-if="reportStatus === 'ready'"
            section="charts"
            :data="supervision.supervision"
            @navigate="go($event.name, null, $event.query || {})"
          />
          <State
            v-else
            :status="reportStatus"
            compact
            retry
            @retry="reloadReport"
          />
        </template>
        <Panel
          :title="t('JRC_SERVICE_DESK.OVERVIEW.recent')"
          icon="i-lucide-ticket"
        >
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
            compact
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
      </div>
      <div class="grid content-start gap-4">
        <OverviewSignals
          kind="risk"
          :data="reportStatus === 'ready' ? supervision?.supervision : null"
          :can-view-sla="
            session.state.context?.effective_permissions?.includes(
              'jrc_service_desk_sla_view'
            ) === true
          "
          @sla="go('sla')"
        />
        <OverviewSignals
          kind="team"
          :data="reportStatus === 'ready' ? supervision?.supervision : null"
        />
        <OverviewSignals
          kind="activity"
          :tickets="recent.status === 'ready' ? recent.items : []"
          :loading="recent.status === 'loading'"
          @open="go('detail', $event)"
        />
        <details class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <summary class="cursor-pointer text-sm font-medium">
            {{ t('JRC_SERVICE_DESK.REFINEMENT.overview.more') }}
          </summary>
          <OverviewOperations
            v-if="reportStatus === 'ready'"
            section="summary"
            :data="supervision.supervision"
            @navigate="go($event.name, null, $event.query || {})"
          />
        </details>
        <Panel :title="t('JRC_SERVICE_DESK.OVERVIEW.shortcuts')">
          <div class="grid gap-2">
            <Button
              variant="outline"
              color="slate"
              :label="t('JRC_SERVICE_DESK.SCREENS.mine')"
              @click="go('mine')"
            />
            <Button
              variant="outline"
              color="slate"
              :label="t('JRC_SERVICE_DESK.SCREENS.queues')"
              @click="go('queues')"
            />
          </div>
        </Panel>
      </div>
    </div>
  </section>
</template>
