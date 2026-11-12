<script setup>
import { computed, defineAsyncComponent, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useSupervisionReport } from '../composables/useSupervisionReport.js';
import { metricQuery } from '../helpers/screenExperience.js';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import TicketFilters from '../components/TicketFilters.vue';
import TicketTable from '../components/TicketTable.vue';
import SupervisorPanel from '../components/SupervisorPanel.vue';
import ReportCenter from '../components/ReportCenter.vue';
import OperationalReportPanel from '../components/OperationalReportPanel.vue';
import ReportDialog from '../components/ReportDialog.vue';
import { downloadCsv, metricRows } from '../helpers/csvExport';
import LiveKpis from '../components/LiveKpis.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
const route = useRoute();
const router = useRouter();
const session = useServiceDesk();
const { t } = useI18n();
const mode = ref('library');
const selection = ref(null);
const reportView = ref(null);
const views = {
  overview: defineAsyncComponent(() => import('./OverviewView.vue')),
  sla: defineAsyncComponent(() => import('./SlaView.vue')),
  assets: defineAsyncComponent(() => import('./ResourcesView.vue')),
  tasks: defineAsyncComponent(() => import('./OperationsBoardView.vue')),
  assignees: defineAsyncComponent(() => import('./CatalogView.vue')),
  contracts: defineAsyncComponent(() => import('./CatalogView.vue')),
};
const selectReport = value => {
  selection.value =
    typeof value === 'string'
      ? {
          target: value,
          title: t(`JRC_SERVICE_DESK.EXPERIENCE.report_modes.${value}`),
        }
      : value;
  mode.value = selection.value.target;
};
const closeReport = () => {
  mode.value = 'library';
  selection.value = null;
};
watch(
  () => session.state.context,
  context => {
    const target = selection.value?.target;
    const capability =
      {
        operational: 'operational_reports',
        supervision: 'reports',
        overview: 'dashboard',
        sla: 'sla',
      }[target] || target;
    if (target && context?.capabilities?.[capability]?.index !== true)
      closeReport();
  },
  { flush: 'sync' }
);
const { result, status, load } = useSupervisionReport(
  session,
  () => route.query,
  () => mode.value === 'supervision'
);
const exportReady = computed(() =>
  mode.value === 'supervision'
    ? status.value === 'ready'
    : reportView.value?.canExport === true
);
const exportReport = () => {
  if (!exportReady.value) return;
  if (mode.value === 'supervision')
    downloadCsv(
      [
        [
          t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.field'),
          t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.value'),
        ],
        ...metricRows(result.value),
      ],
      'supervisao-pagina.csv'
    );
  else reportView.value.exportCsv();
};
const open = ticketId =>
  router.push({
    name: serviceDeskRouteName('detail'),
    params: { accountId: route.params.accountId, ticketId },
  });
</script>

<template>
  <section class="grid gap-4">
    <ReportCenter @select="selectReport" />
    <div
      class="flex flex-wrap gap-2"
      role="group"
      :aria-label="t('JRC_SERVICE_DESK.SCREENS.reports')"
    >
      <Button
        v-for="value in ['library', 'operational', 'supervision'].filter(
          key =>
            ['library', 'supervision'].includes(key) ||
            session.state.context?.capabilities?.operational_reports?.index
        )"
        :key="value"
        :variant="mode === value ? 'solid' : 'outline'"
        :aria-pressed="mode === value"
        :label="
          value === 'library'
            ? t('JRC_SERVICE_DESK.SCREENS.reports')
            : t(`JRC_SERVICE_DESK.EXPERIENCE.report_modes.${value}`)
        "
        @click="value === 'library' ? closeReport() : selectReport(value)"
      />
    </div>
    <ReportDialog
      v-if="selection"
      :title="selection.title"
      :can-export="exportReady"
      @close="closeReport"
      @export="exportReport"
    >
      <OperationalReportPanel
        v-if="mode === 'operational'"
        ref="reportView"
        :initial-dimension="selection.dimension"
        @open="open"
      />
      <component
        :is="views[mode]"
        v-else-if="views[mode]"
        ref="reportView"
        :screen="mode"
        :resource="mode"
        v-bind="
          ['assignees', 'contracts'].includes(mode) ? { reportOnly: true } : {}
        "
      />
      <template v-else-if="mode === 'supervision'">
        <TicketFilters
          :query="route.query"
          @apply="router.push({ query: $event })"
        />
        <LiveKpis
          :query="route.query"
          @metric-filter="
            router.push({ query: metricQuery(route.query, $event) })
          "
        />
        <template v-if="status === 'ready'">
          <SupervisorPanel :data="result.supervision" />
          <p class="text-xs">
            {{
              t('JRC_SERVICE_DESK.V2.generated', {
                time: result.dashboard.generated_at,
              })
            }}
          </p>
          <Panel :title="t('JRC_SERVICE_DESK.SCREENS.tickets')">
            <TicketTable :items="result.items" @open="open" @preview="open" />
            <Pagination
              v-if="result.meta.total"
              :current-page="result.meta.page"
              :total-items="result.meta.total"
              :items-per-page="result.meta.per_page"
              @update:current-page="
                router.push({ query: { ...route.query, page: String($event) } })
              "
            />
          </Panel>
        </template>
        <State v-else :status="status" retry @retry="load" />
      </template>
    </ReportDialog>
  </section>
</template>
