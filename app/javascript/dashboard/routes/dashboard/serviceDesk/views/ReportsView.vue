<script setup>
import { computed, ref, watch } from 'vue';
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
import OperationalReportPanel from '../components/OperationalReportPanel.vue';
import LiveKpis from '../components/LiveKpis.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
import { v2Labels } from '../helpers/v2Labels';
const props = defineProps({ screen: { type: String, default: 'reports' } });
const route = useRoute();
const router = useRouter();
const session = useServiceDesk();
const { t } = useI18n();
const labels = computed(() => v2Labels(t));
const mode = ref(
  session.state.context?.capabilities?.operational_reports?.index
    ? 'operational'
    : 'supervision'
);
watch(
  () => session.state.context,
  () => {
    if (!session.state.context?.capabilities?.operational_reports?.index)
      mode.value = 'supervision';
  },
  { flush: 'sync' }
);
const { result, status, load } = useSupervisionReport(
  session,
  () => route.query,
  () => mode.value === 'supervision'
);
const open = ticketId =>
  router.push({
    name: serviceDeskRouteName('detail'),
    params: { accountId: route.params.accountId, ticketId },
  });
</script>

<template>
  <section class="grid gap-4">
    <h2 class="text-xl font-semibold">
      {{ labels.screen[props.screen] }}
    </h2>
    <div
      class="flex flex-wrap gap-2"
      role="group"
      :aria-label="t('JRC_SERVICE_DESK.SCREENS.reports')"
    >
      <Button
        v-for="value in ['operational', 'supervision'].filter(
          key =>
            key === 'supervision' ||
            session.state.context?.capabilities?.operational_reports?.index
        )"
        :key="value"
        :variant="mode === value ? 'solid' : 'outline'"
        :aria-pressed="mode === value"
        :label="t(`JRC_SERVICE_DESK.EXPERIENCE.report_modes.${value}`)"
        @click="mode = value"
      />
    </div>
    <OperationalReportPanel v-if="mode === 'operational'" @open="open" />
    <template v-else>
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
  </section>
</template>
