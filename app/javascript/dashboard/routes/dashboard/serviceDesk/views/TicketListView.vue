<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import ClaimNext from '../components/ClaimNext.vue';
import TicketFilters from '../components/TicketFilters.vue';
import TicketTable from '../components/TicketTable.vue';
import LiveKpis from '../components/LiveKpis.vue';
import TicketSummary from '../components/TicketSummary.vue';
import TicketProtocol from '../components/TicketProtocol.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
import { routeQuery } from '../helpers/query';
import { metricQuery, ticketListQuery } from '../helpers/screenExperience.js';
const props = defineProps({ screen: { type: String, default: 'tickets' } });
const { t } = useI18n();
const session = useServiceDesk();
const route = useRoute();
const router = useRouter();
const key = 'tickets:list';
const previewKey = 'tickets:preview';
const selection = ref('');
const filterError = ref(false);
const result = computed(() => session.resource(key));
const preview = computed(() => session.resource(previewKey));
const query = computed(() => ticketListQuery(props.screen, route.query));
const status = computed(() => filterError.value ? 'invalid_request' : result.value.status);
const tabs = computed(() => ['tickets', 'mine'].map(value => ({ value, label: t(`JRC_SERVICE_DESK.SCREENS.${value}`) })));
const go = (name, ticketId) =>
  router.push({
    name: serviceDeskRouteName(name),
    params: {
      accountId: session.accountId.value,
      ...(ticketId ? { ticketId } : {}),
    },
    ...(['tickets', 'mine'].includes(name)
      ? {
          query: {
            ...route.query,
            mine:
              name === 'mine' && route.query.assignment !== 'unassigned'
                ? 'true'
                : undefined,
          },
        }
      : {}),
  });
const load = () => { selection.value = ''; filterError.value = false; session.resetResource(previewKey); return session.load(key, 'tickets', query.value); };
watch([query, () => session.state.status, () => session.operations?.state.revision], load, { immediate: true });
const apply = filters => {
  selection.value = '';
  session.resetResource(previewKey);
  try {
    const next = routeQuery(
      ticketListQuery(props.screen, { ...filters, page: 1 })
    );
    filterError.value = false;
    router.push({ query: next });
  }
  catch {
    filterError.value = true;
    session.resetResource(key, 'invalid_request');
  }
};
const page = value => router.push({ query: { ...route.query, page: String(value) } });
const showPreview = id => { selection.value = id; return session.load(previewKey, 'tickets', {}, id); };
onBeforeUnmount(() => { session.resetResource(key); session.resetResource(previewKey); });
</script>
<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t(`JRC_SERVICE_DESK.SCREENS.${screen}`) }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.TICKET.subtitle') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-3">
        <Button
          :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          size="sm"
          :disabled="result.status === 'loading'"
          @click="load"
        />
        <Button
          v-if="session.state.context?.capabilities?.reports?.index"
          :label="t('JRC_SERVICE_DESK.SCREENS.reports')"
          icon="i-lucide-chart-no-axes-combined"
          variant="outline"
          size="sm"
          @click="go('reports')"
        />
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
      </div>
    </header>
    <div class="overflow-x-auto mb-4">
      <TabBar :tabs="tabs" :initial-active-tab="screen === 'mine' ? 1 : 0" @tab-changed="go($event.value)" />
    </div>
    <p v-if="screen === 'mine'" class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.FILTERS.mine_hint') }}
    </p>
    <div v-if="screen === 'mine'" class="mb-4 grid gap-3">
      <div
        class="flex flex-wrap gap-2"
        :aria-label="t('JRC_SERVICE_DESK.SCREENS.mine')"
      >
        <Button
          size="sm"
          :variant="query.assignment ? 'outline' : 'solid'"
          :label="t('JRC_SERVICE_DESK.EXPERIENCE.my_assignments')"
          @click="
            router.push({
              query: {
                ...route.query,
                assignment: undefined,
                mine: 'true',
                page: '1',
              },
            })
          "
        />
        <Button
          size="sm"
          :variant="query.assignment ? 'solid' : 'outline'"
          :label="t('JRC_SERVICE_DESK.EXPERIENCE.unassigned_visible')"
          @click="
            router.push({
              query: {
                ...route.query,
                mine: undefined,
                assignment: 'unassigned',
                page: '1',
              },
            })
          "
        />
      </div>
      <p v-if="query.assignment" class="text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.EXPERIENCE.claim_authority') }}
      </p>
      <ClaimNext />
    </div>
    <TicketFilters :query="route.query" @apply="apply" />
    <LiveKpis
      :query="query"
      @metric-filter="router.push({ query: metricQuery(query, $event) })"
    />
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.FILTERS.local_hint') }}
    </p>
    <div :class="selection ? 'sd-two-columns' : ''">
      <Panel :title="t('JRC_SERVICE_DESK.SCREENS.tickets')">
        <TicketTable
          v-if="status === 'ready'"
          :items="result.items"
          @open="go('detail', $event)"
          @preview="showPreview"
        />
        <template v-else>
          <div class="sd-column-hints">
            <span v-for="field in ['number', 'title', 'requester', 'priority', 'status', 'sla']" :key="field">
              {{ t(`JRC_SERVICE_DESK.FIELDS.${field}`) }}
            </span>
          </div>
          <State :status="status" retry @retry="session.state.status === 'ready' ? load() : session.retry()" />
        </template>
        <PaginationFooter
          v-if="result.meta && result.meta.total > 0"
          :current-page="result.meta.page"
          :total-items="result.meta.total"
          :items-per-page="result.meta.per_page"
          @update:current-page="page"
        />
      </Panel>
      <Panel v-if="selection" :title="t('JRC_SERVICE_DESK.TICKET.preview')" class="sd-sticky">
        <template #actions>
          <Button
            size="xs"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.COMMON.close')"
            @click="selection = ''; session.resetResource(previewKey)"
          />
        </template>
        <template v-if="preview.status === 'ready'">
          <TicketProtocol :ticket="preview.record" />
          <h3 class="text-base mb-4 break-words">
            {{ preview.record.title }}
          </h3>
          <TicketSummary :ticket="preview.record" />
          <Button class="mt-4" :label="t('JRC_SERVICE_DESK.COMMON.open')" size="sm" @click="go('detail', selection)" />
        </template>
        <State v-else :status="preview.status" compact retry @retry="showPreview(selection)" />
      </Panel>
    </div>
  </section>
</template>
