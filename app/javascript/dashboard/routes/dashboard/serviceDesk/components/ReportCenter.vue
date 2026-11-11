<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
const emit = defineEmits(['select']);
const route = useRoute();
const router = useRouter();
const session = useServiceDesk();
const { t } = useI18n({
  useScope: 'local',
  messages: {
    pt_BR: {
      title: 'Central de Relatórios',
      subtitle: 'Indicadores, consultas e exportações do Service Desk',
      all: 'Todos',
      executive: 'Executivo',
      operational: 'Operacional',
      assets: 'Patrimônio',
      exports: 'Exportações',
      management: 'Gerencial',
      control: 'Contratos e controle',
      activity: 'Atividades e atendimento',
      analytics: 'Análises do atendimento',
      models: 'Modelos prontos',
      modelHelp:
        'Escolha uma visão e consulte os dados no seu escopo autorizado.',
      overview: 'Dashboard executivo',
      report: 'Relatório operacional detalhado',
      supervision: 'Supervisão da equipe',
      sla: 'Prazos e cumprimento de SLA',
      categories: 'Chamados por categoria',
      clients: 'Resumo por empresa',
      services: 'Resumo por serviço',
      contracts: 'Contratos de atendimento',
      inventory: 'Relação de patrimônio',
      tasks: 'Atividades e tarefas',
      team: 'Responsáveis e filas',
      export: 'Exportar solicitações em CSV',
      use: 'Usar modelo',
      filters:
        'Configure unidade, período e demais filtros na consulta selecionada.',
      available: 'Consultas disponíveis',
      notice:
        'Os relatórios usam dados reais. Custos, satisfação e BI personalizado dependem de fontes e funcionalidades disponíveis; não são estimados neste painel.',
    },
    en: {
      title: 'Report Center',
      subtitle: 'Service Desk metrics, queries and exports',
      all: 'All',
      executive: 'Executive',
      operational: 'Operational',
      assets: 'Assets',
      exports: 'Exports',
      management: 'Management',
      control: 'Contracts and controls',
      activity: 'Activities and service',
      analytics: 'Service analytics',
      models: 'Ready-made views',
      modelHelp: 'Choose a view to query data within your authorized scope.',
      overview: 'Executive dashboard',
      report: 'Detailed operational report',
      supervision: 'Team supervision',
      sla: 'SLA deadlines and compliance',
      categories: 'Tickets by category',
      clients: 'Summary by company',
      services: 'Summary by service',
      contracts: 'Service contracts',
      inventory: 'Asset inventory',
      tasks: 'Activities and tasks',
      team: 'Assignees and queues',
      export: 'Export tickets as CSV',
      use: 'Use template',
      filters: 'Set unit, period and other filters in the selected query.',
      available: 'Available queries',
      notice:
        'Reports use real data. Costs, satisfaction and custom BI depend on available sources and features; this panel does not estimate them.',
    },
  },
});
const tab = ref('all');
const groups = [
  {
    key: 'executive',
    title: 'management',
    icon: 'i-lucide-chart-no-axes-combined',
    links: [
      ['overview', 'overview'],
      ['clients', 'operational'],
      ['services', 'operational'],
      ['supervision', 'supervision'],
    ],
  },
  {
    key: 'operational',
    title: 'analytics',
    icon: 'i-lucide-headset',
    links: [
      ['report', 'operational'],
      ['sla', 'sla'],
      ['categories', 'operational'],
    ],
  },
  {
    key: 'assets',
    title: 'assets',
    icon: 'i-lucide-box',
    links: [['inventory', 'assets']],
  },
  {
    key: 'operational',
    title: 'activity',
    icon: 'i-lucide-clipboard-check',
    links: [
      ['tasks', 'tasks'],
      ['team', 'assignees'],
    ],
  },
  {
    key: 'exports',
    title: 'exports',
    icon: 'i-lucide-download',
    links: [['export', 'operational']],
  },
  {
    key: 'executive',
    title: 'control',
    icon: 'i-lucide-files',
    links: [['contracts', 'contracts']],
  },
];
const allowed = target => {
  const caps = session.state.context?.capabilities || {};
  return (
    caps[
      {
        operational: 'operational_reports',
        supervision: 'reports',
        overview: 'dashboard',
        sla: 'reports',
      }[target] || target
    ]?.index === true
  );
};
const visible = computed(() =>
  groups
    .filter(group => tab.value === 'all' || group.key === tab.value)
    .map(group => ({
      ...group,
      links: group.links.filter(([, target]) => allowed(target)),
    }))
    .filter(group => group.links.length)
);
const open = target => {
  if (['operational', 'supervision'].includes(target)) emit('select', target);
  else
    router.push({
      name: serviceDeskRouteName(target),
      params: { accountId: route.params.accountId },
    });
};
</script>

<template>
  <section class="grid gap-5">
    <header class="flex items-center gap-3">
      <span
        class="i-lucide-chart-no-axes-combined size-11 rounded-xl bg-blue-100 p-2 text-blue-700"
      />
      <div>
        <h2 class="m-0 text-2xl font-bold">{{ t('title') }}</h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">{{ t('subtitle') }}</p>
      </div>
    </header>
    <nav class="flex flex-wrap gap-2" :aria-label="t('title')">
      <button
        v-for="key in ['all', 'executive', 'operational', 'assets', 'exports']"
        :key="key"
        type="button"
        class="rounded-xl border px-4 py-2 text-sm font-semibold focus-visible:ring-2 focus-visible:ring-blue-500"
        :class="
          tab === key
            ? 'border-blue-700 bg-blue-700 text-white'
            : 'border-n-weak bg-n-solid-1 text-n-slate-12'
        "
        :aria-pressed="tab === key"
        @click="tab = key"
      >
        {{ t(key) }}
      </button>
    </nav>
    <div
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm text-blue-900"
    >
      <span>{{ t('filters') }}</span
      ><button
        v-if="allowed('operational')"
        type="button"
        class="rounded-lg bg-blue-700 px-4 py-2 font-semibold text-white"
        @click="open('operational')"
      >
        {{ t('report') }}
      </button>
    </div>
    <div class="grid items-start gap-4 md:grid-cols-2 xl:grid-cols-3">
      <article
        v-for="group in visible"
        :key="group.title"
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
      >
        <header
          class="flex items-center gap-3 border-b border-n-weak bg-n-slate-2 p-4"
        >
          <span class="size-6 text-blue-700" :class="group.icon" />
          <h3 class="m-0 text-base font-bold">{{ t(group.title) }}</h3>
        </header>
        <div class="grid p-3">
          <button
            v-for="[label, target] in group.links"
            :key="label"
            type="button"
            class="flex items-center justify-between gap-3 rounded-lg border-b border-n-weak px-3 py-3 text-start text-sm font-medium text-n-blue-11 hover:bg-n-blue-2 focus-visible:ring-2 focus-visible:ring-blue-500"
            @click="open(target)"
          >
            <span>{{ t(label) }}</span
            ><span aria-hidden="true" class="i-lucide-chevron-right size-4" />
          </button>
        </div>
      </article>
    </div>
    <section class="rounded-2xl border border-n-weak bg-n-solid-1 p-5">
      <h3 class="m-0 text-lg font-bold">{{ t('models') }}</h3>
      <p class="mt-1 text-sm text-n-slate-11">{{ t('modelHelp') }}</p>
      <div class="grid gap-4 md:grid-cols-3">
        <button
          v-for="target in ['overview', 'operational', 'supervision'].filter(
            allowed
          )"
          :key="target"
          type="button"
          class="grid gap-3 rounded-xl border border-blue-200 bg-gradient-to-br from-blue-50 to-n-solid-1 p-5 text-start hover:border-blue-500 focus-visible:ring-2 focus-visible:ring-blue-500"
          @click="open(target)"
        >
          <span class="i-lucide-chart-column size-8 text-blue-600" /><strong>{{
            t(
              {
                overview: 'overview',
                operational: 'report',
                supervision: 'supervision',
              }[target]
            )
          }}</strong
          ><span class="text-sm font-semibold text-blue-700">{{
            t('use')
          }}</span>
        </button>
      </div>
    </section>
    <p class="text-xs text-n-slate-11">{{ t('notice') }}</p>
  </section>
</template>
