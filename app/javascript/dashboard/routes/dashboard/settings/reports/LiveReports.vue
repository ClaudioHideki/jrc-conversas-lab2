<script setup>
import { computed, defineAsyncComponent, ref, shallowRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useOperations } from '../../jrcOperations/useOperations';
import ReportDialog from '../../serviceDesk/components/ReportDialog.vue';

const { t } = useI18n({
  useScope: 'local',
  messages: {
    pt_BR: {
      title: 'Central de Relatórios',
      subtitle: 'Indicadores e consultas por módulo',
      modules: 'Módulos de relatórios',
      service: 'Atendimento',
      crm: 'CRM',
      projects: 'Projetos',
      desk: 'Service Desk',
      management: 'Gerencial',
      executive: 'Dashboard executivo',
      realtime: 'Operação em tempo real',
      performance: 'Desempenho',
      agents: 'Relatório por analista',
      teams: 'Relatório por equipe',
      operation: 'Operação e SLA',
      conversations: 'Relatório de conversas',
      sla: 'Prazos e cumprimento de SLA',
      labels: 'Resumo por etiqueta',
      quality: 'Qualidade e automação',
      csat: 'Satisfação do cliente (CSAT)',
      bots: 'Relatório de robôs',
      channels: 'Canais de atendimento',
      inboxes: 'Relatório por caixa de entrada',
      history: 'Histórico de ligações',
      sales: 'Desempenho comercial',
      indicators: 'Indicadores do CRM',
      portfolio: 'Carteira de projetos',
      projectReport: 'Indicadores e exportação de projetos',
    },
    en: {
      title: 'Report Center',
      subtitle: 'Metrics and reports by module',
      modules: 'Report modules',
      service: 'Customer service',
      crm: 'CRM',
      projects: 'Projects',
      desk: 'Service Desk',
      management: 'Management',
      executive: 'Executive dashboard',
      realtime: 'Live operations',
      performance: 'Performance',
      agents: 'Agent report',
      teams: 'Team report',
      operation: 'Operations and SLA',
      conversations: 'Conversation report',
      sla: 'SLA deadlines and compliance',
      labels: 'Summary by label',
      quality: 'Quality and automation',
      csat: 'Customer satisfaction (CSAT)',
      bots: 'Bot report',
      channels: 'Service channels',
      inboxes: 'Inbox report',
      history: 'Call history',
      sales: 'Sales performance',
      indicators: 'CRM metrics',
      portfolio: 'Project portfolio',
      projectReport: 'Project metrics and export',
    },
  },
});
const policy = usePolicy();
const store = useStore();
const { accountId, userId, status } = useOperations();
const currentAccount = computed(() =>
  store.getters.getCurrentUser?.accounts?.find(
    account => Number(account.id) === Number(accountId.value)
  )
);
const tab = ref('service');
const selected = shallowRef(null);
const ServiceDeskReportsTab = defineAsyncComponent(
  () => import('./components/ServiceDeskReportsTab.vue')
);

const tabs = computed(() =>
  [
    { key: 'service', icon: 'i-lucide-headphones' },
    {
      key: 'crm',
      icon: 'i-lucide-target',
      available:
        policy.isFeatureFlagEnabled(FEATURE_FLAGS.JRC_CRM) === true &&
        currentAccount.value?.permissions?.includes('jrc_crm'),
    },
    {
      key: 'desk',
      icon: 'i-lucide-headset',
      available: policy.isFeatureFlagEnabled(FEATURE_FLAGS.JRC_SERVICE_DESK),
    },
    {
      key: 'projects',
      icon: 'i-lucide-folder-kanban',
      available:
        status.value?.projects_enabled === true &&
        status.value?.can_view_project_reports === true,
    },
  ].filter(item => item.key === 'service' || item.available)
);

const groups = {
  service: [
    {
      key: 'management',
      icon: 'i-lucide-chart-no-axes-combined',
      color: 'bg-n-blue-3 text-n-blue-11',
      reports: [
        {
          key: 'executive',
          view: defineAsyncComponent(
            () => import('./components/performance/PerformanceDashboard.vue')
          ),
          props: { scope: 'account' },
        },
        {
          key: 'realtime',
          view: defineAsyncComponent(
            () => import('./OperationalLiveReports.vue')
          ),
          props: { embedded: true },
        },
      ],
    },
    {
      key: 'performance',
      icon: 'i-lucide-users-round',
      color: 'bg-n-violet-3 text-n-violet-11',
      reports: [
        {
          key: 'agents',
          view: defineAsyncComponent(() => import('./AgentReportsIndex.vue')),
          props: { embedded: true },
        },
        {
          key: 'teams',
          view: defineAsyncComponent(() => import('./TeamReportsIndex.vue')),
        },
      ],
    },
    {
      key: 'quality',
      icon: 'i-lucide-star',
      color: 'bg-n-teal-3 text-n-teal-11',
      reports: [
        {
          key: 'csat',
          view: defineAsyncComponent(() => import('./CsatResponses.vue')),
        },
        {
          key: 'bots',
          view: defineAsyncComponent(() => import('./BotReports.vue')),
        },
      ],
    },
    {
      key: 'operation',
      icon: 'i-lucide-timer',
      color: 'bg-n-amber-3 text-n-amber-11',
      reports: [
        {
          key: 'conversations',
          view: defineAsyncComponent(() => import('./Index.vue')),
          props: { embedded: true },
        },
        {
          key: 'sla',
          view: defineAsyncComponent(() => import('./SLAReports.vue')),
        },
        {
          key: 'labels',
          view: defineAsyncComponent(() => import('./LabelReportsIndex.vue')),
        },
      ],
    },
    {
      key: 'channels',
      icon: 'i-lucide-messages-square',
      color: 'bg-n-cyan-3 text-n-cyan-11',
      reports: [
        {
          key: 'inboxes',
          view: defineAsyncComponent(() => import('./InboxReportsIndex.vue')),
        },
        {
          key: 'history',
          view: defineAsyncComponent(
            () => import('../../webphone/CallHistoryPanel.vue')
          ),
        },
      ],
    },
  ],
  crm: [
    {
      key: 'sales',
      icon: 'i-lucide-chart-column-increasing',
      color: 'bg-n-violet-3 text-n-violet-11',
      reports: [
        {
          key: 'indicators',
          view: defineAsyncComponent(
            () => import('../../crm/views/reports/ReportsView.vue')
          ),
        },
      ],
    },
  ],
  projects: [
    {
      key: 'portfolio',
      icon: 'i-lucide-folders',
      color: 'bg-n-teal-3 text-n-teal-11',
      reports: [
        {
          key: 'projectReport',
          view: defineAsyncComponent(
            () => import('../../jrcOperations/views/ProjectList.vue')
          ),
          props: { reportOnly: true },
        },
      ],
    },
  ],
};
const selectTab = key => {
  selected.value = null;
  tab.value = key;
};
watch([accountId, userId], () => selectTab('service'), { flush: 'sync' });
watch(
  tabs,
  allowed => {
    if (!allowed.some(item => item.key === tab.value)) selectTab('service');
  },
  { flush: 'sync' }
);
</script>

<template>
  <div class="space-y-5 py-5">
    <header
      class="flex items-center gap-4 rounded-2xl bg-gradient-to-br from-[#08264a] via-[#103c88] to-blue-800 p-5 text-white shadow-sm sm:p-6"
    >
      <Icon
        icon="i-lucide-chart-no-axes-combined"
        class="size-9 shrink-0 text-sky-200"
      />
      <div>
        <h1 class="m-0 text-2xl font-bold text-white">{{ t('title') }}</h1>
        <p class="mb-0 mt-1 text-sm text-blue-100">{{ t('subtitle') }}</p>
      </div>
    </header>
    <nav class="flex flex-wrap gap-2" :aria-label="t('modules')">
      <button
        v-for="item in tabs"
        :key="item.key"
        type="button"
        :aria-pressed="tab === item.key"
        class="flex min-h-11 items-center gap-2 rounded-xl border px-4 py-2 text-sm font-semibold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-9"
        :class="
          tab === item.key
            ? 'border-n-blue-9 bg-n-blue-9 text-white'
            : 'border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-blue-2'
        "
        @click="selectTab(item.key)"
      >
        <Icon :icon="item.icon" class="size-4 shrink-0" />
        {{ t(item.key) }}
      </button>
    </nav>
    <ServiceDeskReportsTab v-if="tab === 'desk'" />
    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <section
        v-for="group in groups[tab]"
        :key="group.key"
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
      >
        <header
          class="flex items-center gap-3 border-b border-n-weak p-4"
          :class="group.color"
        >
          <Icon :icon="group.icon" class="size-6 shrink-0" />
          <h2 class="m-0 text-base font-bold">{{ t(group.key) }}</h2>
        </header>
        <ul class="m-0 list-none space-y-1 p-2">
          <li v-for="report in group.reports" :key="report.key">
            <button
              type="button"
              aria-haspopup="dialog"
              class="flex min-h-10 w-full items-center justify-between gap-3 rounded-lg px-3 py-2 text-start text-sm font-medium text-n-blue-11 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
              @click="selected = report"
            >
              {{ t(report.key) }}
              <Icon icon="i-lucide-chevron-right" class="size-4 shrink-0" />
            </button>
          </li>
        </ul>
      </section>
    </div>
    <ReportDialog
      v-if="selected"
      :title="t(selected.key)"
      :show-export="false"
      @close="selected = null"
    >
      <component :is="selected.view" v-bind="selected.props" />
    </ReportDialog>
  </div>
</template>
