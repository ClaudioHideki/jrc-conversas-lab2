<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import API from 'dashboard/api/serviceDeskOperationsV2';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import TicketFilters from '../components/TicketFilters.vue';
import TicketTable from '../components/TicketTable.vue';
import SupervisorPanel from '../components/SupervisorPanel.vue';
import OperationalReportPanel from '../components/OperationalReportPanel.vue';
import LiveKpis from '../components/LiveKpis.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { normalizeQuery } from '../helpers/query';
import { decodeReport } from '../helpers/v2Projection';
import { errorStatus } from '../helpers/session';
import { serviceDeskRouteName } from '../routeDefinitions';
import { v2Labels } from '../helpers/v2Labels';
const props = defineProps({ screen: { type: String, default: 'reports' } });
const route = useRoute();
const router = useRouter();
const session = useServiceDesk();
const { t } = useI18n();
const labels = computed(() => v2Labels(t));
const result = ref(null);
const status = ref('idle');
let epoch = 0;
let controller;
const load = async () => {
  epoch += 1;
  const turn = epoch;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  const context = session.state.context;
  if (
    session.state.status !== 'ready' ||
    context?.capabilities?.reports?.index !== true
  ) {
    status.value = 'denied';
    return;
  }
  status.value = 'loading';
  try {
    const query = normalizeQuery(route.query);
    const payload = await API.report(
      context.account_id,
      query,
      controller.signal
    );
    if (turn !== epoch || context !== session.state.context) return;
    result.value = decodeReport(payload, context, query);
    status.value = 'ready';
  } catch (error) {
    if (turn === epoch) status.value = errorStatus(error);
  }
};
watch(
  [() => route.query, () => session.state.context, () => session.state.status],
  load,
  { immediate: true }
);
onBeforeUnmount(() => {
  epoch += 1;
  controller?.abort();
  result.value = null;
});
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
    <OperationalReportPanel @open="open" />
    <TicketFilters
      :query="route.query"
      @apply="router.push({ query: $event })"
    />
    <LiveKpis :query="route.query" />
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
  </section>
</template>
