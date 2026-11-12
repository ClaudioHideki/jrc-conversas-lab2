<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useServiceDesk } from '../composables/useServiceDesk';
const emit = defineEmits(['select']);
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
      managementHelp: 'Visão consolidada da operação e resultados.',
      analyticsHelp: 'Desempenho, SLA e volume de atendimentos.',
      assetsHelp: 'Controle de ativos e atendimentos relacionados.',
      activityHelp: 'Tarefas, responsáveis e filas de atendimento.',
      exportsHelp: 'Consultas e exportação de dados.',
      controlHelp: 'Contratos, SLAs e controles operacionais.',
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
      managementHelp: 'Consolidated operations and results.',
      analyticsHelp: 'Service performance, SLA and volume.',
      assetsHelp: 'Assets and related service requests.',
      activityHelp: 'Tasks, assignees and service queues.',
      exportsHelp: 'Queries and data exports.',
      controlHelp: 'Contracts, SLAs and operational controls.',
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
        sla: 'sla',
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
const accents = {
  management: {
    surface:
      'from-sky-100 via-blue-50 to-white dark:from-n-blue-3 dark:via-n-solid-2 dark:to-n-solid-1',
    icon: 'from-sky-400 to-blue-700',
    help: 'managementHelp',
  },
  analytics: {
    surface:
      'from-violet-100 via-violet-50 to-white dark:from-n-iris-3 dark:via-n-solid-2 dark:to-n-solid-1',
    icon: 'from-violet-400 to-violet-800',
    help: 'analyticsHelp',
  },
  assets: {
    surface:
      'from-emerald-100 via-emerald-50 to-white dark:from-n-teal-3 dark:via-n-solid-2 dark:to-n-solid-1',
    icon: 'from-emerald-400 to-teal-700',
    help: 'assetsHelp',
  },
  activity: {
    surface:
      'from-amber-100 via-amber-50 to-white dark:from-n-amber-3 dark:via-n-solid-2 dark:to-n-solid-1',
    icon: 'from-amber-400 to-orange-600',
    help: 'activityHelp',
  },
  exports: {
    surface:
      'from-sky-100 via-blue-50 to-white dark:from-n-blue-3 dark:via-n-solid-2 dark:to-n-solid-1',
    icon: 'from-sky-400 to-blue-700',
    help: 'exportsHelp',
  },
  control: {
    surface:
      'from-pink-100 via-pink-50 to-white dark:from-n-ruby-3 dark:via-n-solid-2 dark:to-n-solid-1',
    icon: 'from-pink-400 to-rose-700',
    help: 'controlHelp',
  },
};
const open = (target, label) => {
  if (allowed(target))
    emit('select', {
      target,
      title: t(
        label ||
          {
            operational: 'report',
            overview: 'overview',
            supervision: 'supervision',
          }[target] ||
          target
      ),
      dimension:
        {
          clients: 'by_customer',
          services: 'by_service',
          categories: 'by_category',
        }[label] || null,
    });
};
</script>

<template>
  <section class="grid gap-5">
    <header
      class="relative flex items-center gap-4 overflow-hidden rounded-2xl border border-blue-800 bg-gradient-to-br from-[#031a3a] via-[#073f82] to-blue-700 p-5 text-white shadow-lg shadow-blue-900/15 sm:p-6"
    >
      <span
        class="i-lucide-chart-no-axes-combined size-14 shrink-0 rounded-2xl bg-sky-400/30 p-3 text-sky-100"
      />
      <div>
        <h2 class="m-0 text-2xl font-bold !text-white">{{ t('title') }}</h2>
        <p class="mb-0 mt-1 text-sm text-blue-100">{{ t('subtitle') }}</p>
      </div>
    </header>
    <nav class="flex flex-wrap gap-2" :aria-label="t('title')">
      <button
        v-for="key in ['all', 'executive', 'operational', 'assets', 'exports']"
        :key="key"
        type="button"
        class="flex items-center gap-2 rounded-xl border px-5 py-3 text-sm font-semibold shadow-sm transition hover:shadow-md focus-visible:ring-2 focus-visible:ring-blue-500"
        :class="
          tab === key
            ? 'border-blue-600 bg-gradient-to-b from-sky-500 to-blue-700 text-white'
            : 'border-n-weak bg-n-solid-1 text-n-slate-12'
        "
        :aria-pressed="tab === key"
        @click="tab = key"
      >
        <span
          aria-hidden="true"
          class="size-4"
          :class="
            {
              all: 'i-lucide-layout-grid',
              executive: 'i-lucide-chart-column',
              operational: 'i-lucide-layers',
              assets: 'i-lucide-box',
              exports: 'i-lucide-download',
            }[key]
          "
        />
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
    <div class="grid items-stretch gap-5 md:grid-cols-2 xl:grid-cols-3">
      <article
        v-for="group in visible"
        :key="group.title"
        class="overflow-hidden rounded-2xl border border-blue-200/70 bg-n-solid-1 shadow-md shadow-blue-900/10 dark:border-n-weak"
      >
        <header
          class="flex items-center gap-3 border-b border-n-weak bg-gradient-to-br p-4"
          :class="accents[group.title].surface"
        >
          <div
            class="grid size-12 shrink-0 place-items-center rounded-xl bg-gradient-to-br text-white shadow-sm"
            :class="accents[group.title].icon"
          >
            <span class="size-6" :class="group.icon" aria-hidden="true" />
          </div>
          <div>
            <h3 class="m-0 text-base font-bold">{{ t(group.title) }}</h3>
            <p class="mb-0 mt-1 text-xs text-n-slate-11">
              {{ t(accents[group.title].help) }}
            </p>
          </div>
        </header>
        <div class="grid p-3">
          <button
            v-for="[label, target] in group.links"
            :key="label"
            type="button"
            class="flex items-center justify-between gap-3 rounded-lg border-b border-n-weak px-3 py-3 text-start text-sm font-medium text-n-blue-11 hover:bg-n-blue-2 focus-visible:ring-2 focus-visible:ring-blue-500"
            @click="open(target, label)"
          >
            <span>{{ t(label) }}</span
            ><span aria-hidden="true" class="i-lucide-chevron-right size-4" />
          </button>
        </div>
      </article>
    </div>
    <section
      class="flex flex-col gap-4 rounded-2xl border border-blue-200 bg-n-solid-1 p-4 shadow-sm xl:flex-row xl:items-center"
    >
      <div class="flex items-start gap-3 xl:w-64 xl:shrink-0">
        <span
          aria-hidden="true"
          class="i-lucide-star size-7 shrink-0 text-blue-600"
        />
        <div>
          <h3 class="m-0 text-base font-bold">{{ t('models') }}</h3>
          <p class="mb-0 mt-1 text-xs text-n-slate-11">{{ t('modelHelp') }}</p>
        </div>
      </div>
      <div class="grid flex-1 gap-3 sm:grid-cols-2 2xl:grid-cols-4">
        <button
          v-for="target in [
            'overview',
            'operational',
            'sla',
            'supervision',
          ].filter(allowed)"
          :key="target"
          type="button"
          class="flex items-center gap-3 rounded-xl border border-blue-200 bg-gradient-to-br from-blue-50 to-n-solid-1 p-3 text-start text-sm font-semibold shadow-sm hover:border-blue-500 focus-visible:ring-2 focus-visible:ring-blue-500"
          @click="open(target)"
        >
          <span
            aria-hidden="true"
            class="size-5 shrink-0 text-blue-600"
            :class="
              {
                overview: 'i-lucide-chart-column',
                operational: 'i-lucide-layers',
                sla: 'i-lucide-headset',
                supervision: 'i-lucide-users',
              }[target]
            "
          />
          {{
            t(
              {
                overview: 'overview',
                operational: 'report',
                sla: 'sla',
                supervision: 'supervision',
              }[target]
            )
          }}
        </button>
      </div>
    </section>
  </section>
</template>
