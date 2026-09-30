<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { pipelinesAPI, reportsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useCrmMetrics } from '../../composables/useCrmMetrics';

const store = useStore();
const { isAdmin } = useAdmin();
const { formatBRL } = useCrmMetrics();

const loading = ref(true);
const period = ref('30');
const ownerId = ref('');
const pipelineId = ref('');
const pipelines = ref([]);
const agents = computed(() => store.getters['agents/getAgents'] || []);
const report = ref({
  summary: {},
  leads_by_status: [],
  leads_by_source: [],
  deals_by_status: [],
  proposals_by_status: [],
  revenue_by_owner: [],
  activities: {},
});

const dateParameters = computed(() => {
  const end = new Date();
  const start = new Date();
  if (period.value === 'year') {
    start.setMonth(0, 1);
  } else {
    start.setDate(start.getDate() - Number(period.value));
  }
  const format = value => value.toISOString().slice(0, 10);
  return { start_date: format(start), end_date: format(end) };
});

const metricCards = computed(() => [
  {
    label: 'Leads criados',
    value: report.value.summary.total_leads || 0,
    helper: 'No período selecionado',
    icon: 'i-lucide-users-round',
    accent: 'border-blue-200 bg-blue-50 text-blue-600',
  },
  {
    label: 'Negócios abertos',
    value: report.value.summary.open_deals || 0,
    helper: 'Oportunidades em andamento',
    icon: 'i-lucide-briefcase-business',
    accent: 'border-violet-200 bg-violet-50 text-violet-600',
  },
  {
    label: 'Valor no pipeline',
    value: formatBRL(report.value.summary.pipeline_value_cents || 0),
    helper: 'Soma dos negócios abertos',
    icon: 'i-lucide-circle-dollar-sign',
    accent: 'border-amber-200 bg-amber-50 text-amber-600',
  },
  {
    label: 'Receita ganha',
    value: formatBRL(report.value.summary.won_revenue_cents || 0),
    helper: 'Negócios ganhos no período',
    icon: 'i-lucide-trophy',
    accent: 'border-emerald-200 bg-emerald-50 text-emerald-700',
  },
  {
    label: 'Conversão',
    value: `${report.value.summary.conversion_rate || 0}%`,
    helper: 'Ganhos sobre negócios encerrados',
    icon: 'i-lucide-percent',
    accent: 'border-teal-200 bg-teal-50 text-teal-700',
  },
  {
    label: 'Ticket médio',
    value: formatBRL(report.value.summary.avg_ticket_cents || 0),
    helper: 'Valor médio dos ganhos',
    icon: 'i-lucide-receipt-text',
    accent: 'border-rose-200 bg-rose-50 text-rose-600',
  },
]);

const sourceTotal = computed(() =>
  report.value.leads_by_source.reduce((sum, item) => sum + Number(item.count || 0), 0)
);
const sourcePalette = ['#087cf0', '#0f9f95', '#59b83f', '#f59e0b', '#e83b6a', '#7c3aed'];
const funnelPalette = [
  'from-blue-600 to-blue-500',
  'from-sky-500 to-cyan-400',
  'from-cyan-500 to-teal-400',
  'from-teal-500 to-emerald-400',
  'from-emerald-500 to-green-400',
  'from-green-500 to-lime-400',
  'from-rose-500 to-red-400',
];

const sourceGradient = computed(() => {
  if (!sourceTotal.value) return 'conic-gradient(#e9edf3 0 100%)';
  let cursor = 0;
  const stops = report.value.leads_by_source.map((item, index) => {
    const start = cursor;
    cursor += (Number(item.count || 0) / sourceTotal.value) * 100;
    return `${sourcePalette[index % sourcePalette.length]} ${start}% ${cursor}%`;
  });
  return `conic-gradient(${stops.join(',')})`;
});

const maxFunnelCount = computed(() =>
  Math.max(...(report.value.summary.funnel_stages || []).map(item => Number(item.deals_count || 0)), 1)
);
const maxOwnerRevenue = computed(() =>
  Math.max(...report.value.revenue_by_owner.map(item => Number(item.revenue_cents || item.value_cents || 0)), 1)
);

const funnelWidth = stage => `${Math.max(12, (Number(stage.deals_count || 0) / maxFunnelCount.value) * 100)}%`;

const sourceLabel = value =>
  String(value || 'Não informado')
    .replaceAll('_', ' ')
    .replace(/^./, character => character.toUpperCase());

const statusLabel = value => {
  const labels = {
    new: 'Novo',
    in_contact: 'Em contato',
    qualified: 'Qualificado',
    converted: 'Convertido',
    discarded: 'Descartado',
    open: 'Aberto',
    won: 'Ganho',
    lost: 'Perdido',
    draft: 'Rascunho',
    sent: 'Enviada',
    accepted: 'Aceita',
    rejected: 'Recusada',
  };
  return labels[value] || sourceLabel(value);
};

const exportReport = () => {
  const rows = [['Indicador', 'Valor'], ...metricCards.value.map(item => [item.label, item.value])];
  const csv = rows
    .map(row => row.map(value => `"${String(value).replaceAll('"', '""')}"`).join(';'))
    .join('\n');
  const blob = new Blob([`\ufeff${csv}`], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `indicadores-crm-${new Date().toISOString().slice(0, 10)}.csv`;
  anchor.click();
  URL.revokeObjectURL(url);
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await reportsAPI.list({
      ...dateParameters.value,
      owner_id: isAdmin.value ? ownerId.value || undefined : undefined,
      pipeline_id: pipelineId.value || undefined,
    });
    report.value = data;
  } catch (error) {
    useAlert(error.response?.data?.error || 'Não foi possível carregar os indicadores do CRM.');
  } finally {
    loading.value = false;
  }
};

onMounted(async () => {
  const tasks = [pipelinesAPI.list()];
  if (isAdmin.value) tasks.push(store.dispatch('agents/get'));
  const [pipelineResponse] = await Promise.all(tasks);
  pipelines.value = pipelineResponse.data;
  await load();
});
</script>

<template>
  <div class="h-full overflow-y-auto bg-gradient-to-br from-n-blue-2 via-n-background to-n-violet-2 p-4 sm:p-6">
    <div class="mx-auto max-w-[1720px] space-y-5">
      <header class="rounded-2xl border border-white/70 bg-white/85 p-5 shadow-sm backdrop-blur">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div class="flex items-center gap-2">
              <span class="grid size-9 place-content-center rounded-xl bg-[#087cf0] text-white shadow-[0_8px_18px_rgba(8,124,240,.20)]"><i class="i-lucide-chart-no-axes-combined size-5" /></span>
              <div>
                <h2 class="text-2xl font-bold text-n-slate-12">Indicadores do CRM</h2>
                <p class="text-sm text-n-slate-11">Resultados, conversões e produtividade com os dados reais da operação.</p>
              </div>
            </div>
          </div>
          <button type="button" class="h-10 rounded-xl bg-[#7c3aed] px-4 text-sm font-semibold text-white shadow-md" @click="exportReport">
            <i class="i-lucide-download mr-1 size-4" /> Exportar
          </button>
        </div>

        <div class="mt-5 flex flex-wrap items-end gap-3 rounded-xl border border-n-weak bg-n-slate-2 p-3">
          <label v-if="isAdmin" class="min-w-48 flex-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-11">
            Responsável
            <select v-model="ownerId" class="mt-1 h-10 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 text-sm font-medium normal-case text-n-slate-12" @change="load">
              <option value="">Todos os responsáveis</option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
            </select>
          </label>

          <label class="min-w-48 flex-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-11">
            Funil
            <select v-model="pipelineId" class="mt-1 h-10 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 text-sm font-medium normal-case text-n-slate-12" @change="load">
              <option value="">Todos os funis</option>
              <option v-for="pipeline in pipelines" :key="pipeline.id" :value="pipeline.id">{{ pipeline.name }}</option>
            </select>
          </label>

          <div class="min-w-72 flex-1">
            <span class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-11">Período</span>
            <div class="mt-1 flex h-10 rounded-xl border border-n-weak bg-n-solid-2 p-1">
              <button v-for="option in ['30', '90', 'year']" :key="option" type="button" class="flex-1 rounded-lg px-3 text-xs font-semibold transition" :class="period === option ? 'bg-[#087cf0] text-white shadow-sm' : 'text-n-slate-11 hover:bg-n-slate-2'" @click="period = option; load();">
                {{ option === '30' ? 'Últimos 30 dias' : option === '90' ? 'Últimos 90 dias' : 'Este ano' }}
              </button>
            </div>
          </div>
        </div>
      </header>

      <div v-if="loading" class="flex min-h-80 items-center justify-center rounded-2xl border border-n-weak bg-n-solid-2 text-sm text-n-slate-11">
        <i class="i-lucide-loader-circle mr-2 size-5 animate-spin" /> Carregando indicadores…
      </div>

      <template v-else>
        <section class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
          <article v-for="metric in metricCards" :key="metric.label" class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
            <div class="flex items-start justify-between gap-3">
              <p class="text-xs font-semibold text-n-slate-11">{{ metric.label }}</p>
              <span class="grid size-10 place-content-center rounded-xl border" :class="metric.accent"><i class="size-4" :class="metric.icon" /></span>
            </div>
            <p class="mt-3 truncate text-2xl font-bold text-n-slate-12">{{ metric.value }}</p>
            <small class="mt-1 block min-h-8 text-n-slate-11">{{ metric.helper }}</small>
          </article>
        </section>

        <section class="grid gap-5 xl:grid-cols-[1.1fr_.9fr]">
          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <div class="flex items-center justify-between gap-3">
              <div><h3 class="font-bold text-n-slate-12">Distribuição do funil</h3><p class="mt-1 text-xs text-n-slate-11">Negócios e valores por etapa.</p></div>
              <RouterLink :to="{ name: 'crm_funnel' }" class="text-sm font-semibold text-[#087cf0]">Abrir funil →</RouterLink>
            </div>

            <div v-if="report.summary.funnel_stages?.length" class="mt-5 space-y-3">
              <div v-for="(stage, index) in report.summary.funnel_stages" :key="stage.id" class="grid grid-cols-[minmax(150px,1fr)_88px_135px] items-center gap-3 text-sm">
                <div class="min-w-0">
                  <div class="mb-1.5 flex items-center justify-between gap-2"><span class="truncate font-semibold text-n-slate-12">{{ stage.name }}</span></div>
                  <div class="h-3 overflow-hidden rounded-full bg-n-slate-3"><div class="h-full rounded-full bg-gradient-to-r" :class="funnelPalette[index % funnelPalette.length]" :style="{ width: funnelWidth(stage) }" /></div>
                </div>
                <strong class="text-right text-n-slate-12">{{ stage.deals_count }}</strong>
                <strong class="text-right text-n-slate-12">{{ formatBRL(stage.value_cents || 0) }}</strong>
              </div>
            </div>
            <p v-else class="py-12 text-center text-sm text-n-slate-11">Sem dados de funil no período.</p>
          </article>

          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <div><h3 class="font-bold text-n-slate-12">Origem dos leads</h3><p class="mt-1 text-xs text-n-slate-11">Distribuição dos leads por origem.</p></div>
            <div v-if="report.leads_by_source.length" class="mt-5 flex flex-col items-center gap-5 sm:flex-row">
              <div class="grid size-44 shrink-0 place-content-center rounded-full" :style="{ background: sourceGradient }">
                <div class="grid size-28 place-content-center rounded-full bg-n-solid-2 text-center shadow-inner">
                  <strong class="text-2xl text-n-slate-12">{{ sourceTotal }}</strong>
                  <span class="text-xs text-n-slate-11">Leads totais</span>
                </div>
              </div>
              <div class="w-full space-y-2.5">
                <div v-for="(source, index) in report.leads_by_source" :key="source.name" class="flex items-center justify-between gap-3 text-xs">
                  <span class="flex min-w-0 items-center gap-2 text-n-slate-11"><i class="size-2.5 shrink-0 rounded-full" :style="{ background: sourcePalette[index % sourcePalette.length] }" /><span class="truncate">{{ sourceLabel(source.name) }}</span></span>
                  <strong class="text-n-slate-12">{{ source.count }} · {{ sourceTotal ? Math.round((source.count / sourceTotal) * 100) : 0 }}%</strong>
                </div>
              </div>
            </div>
            <p v-else class="py-12 text-center text-sm text-n-slate-11">Sem origem de leads no período.</p>
          </article>
        </section>

        <section class="grid gap-5 xl:grid-cols-3">
          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <h3 class="font-bold text-n-slate-12">Ciclo dos leads</h3>
            <div v-if="report.leads_by_status.length" class="mt-4 grid grid-cols-2 gap-3">
              <div v-for="(item, index) in report.leads_by_status" :key="item.name" class="rounded-xl border p-3" :class="index % 2 ? 'border-violet-100 bg-violet-50/70' : 'border-blue-100 bg-blue-50/70'">
                <strong class="text-xl text-n-slate-12">{{ item.count }}</strong><span class="mt-1 block text-xs font-medium text-n-slate-11">{{ statusLabel(item.name) }}</span>
              </div>
            </div>
            <p v-else class="py-8 text-center text-sm text-n-slate-11">Sem dados de leads.</p>
          </article>

          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <h3 class="font-bold text-n-slate-12">Produtividade</h3>
            <div class="mt-4 grid grid-cols-3 gap-3 text-center">
              <div class="rounded-xl bg-emerald-50 p-3"><strong class="text-xl text-emerald-700">{{ report.activities.completed || 0 }}</strong><span class="mt-1 block text-xs text-n-slate-11">Concluídas</span></div>
              <div class="rounded-xl bg-amber-50 p-3"><strong class="text-xl text-amber-700">{{ report.activities.pending || 0 }}</strong><span class="mt-1 block text-xs text-n-slate-11">Pendentes</span></div>
              <div class="rounded-xl bg-rose-50 p-3"><strong class="text-xl text-rose-700">{{ report.activities.overdue || 0 }}</strong><span class="mt-1 block text-xs text-n-slate-11">Atrasadas</span></div>
            </div>
            <RouterLink :to="{ name: 'crm_activities' }" class="mt-4 inline-flex text-sm font-semibold text-[#087cf0]">Abrir atividades →</RouterLink>
          </article>

          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <h3 class="font-bold text-n-slate-12">Resultados dos negócios</h3>
            <div v-if="report.deals_by_status.length" class="mt-4 space-y-2">
              <div v-for="item in report.deals_by_status" :key="item.name" class="flex items-center justify-between rounded-xl border border-n-weak bg-n-slate-2 px-3 py-2.5">
                <span class="text-sm font-medium text-n-slate-11">{{ statusLabel(item.name) }}</span><strong class="text-n-slate-12">{{ item.count }}</strong>
              </div>
            </div>
            <p v-else class="py-8 text-center text-sm text-n-slate-11">Sem resultados no período.</p>
          </article>
        </section>

        <section class="grid gap-5 xl:grid-cols-[1.3fr_.7fr]">
          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <div class="flex items-center justify-between gap-3"><div><h3 class="font-bold text-n-slate-12">Desempenho por vendedor</h3><p class="mt-1 text-xs text-n-slate-11">Receita ganha por responsável no período selecionado.</p></div><span class="rounded-lg bg-blue-50 px-3 py-1.5 text-xs font-semibold text-blue-700">Ranking</span></div>
            <div v-if="report.revenue_by_owner.length" class="mt-5 space-y-4">
              <div v-for="(owner, index) in report.revenue_by_owner" :key="owner.id || owner.owner_id || owner.name" class="grid grid-cols-[30px_minmax(120px,1fr)_minmax(140px,2fr)_120px] items-center gap-3 text-sm">
                <strong class="text-[#087cf0]">{{ index + 1 }}</strong>
                <span class="truncate font-medium text-n-slate-12">{{ owner.name || owner.owner_name || 'Responsável' }}</span>
                <div class="h-2 overflow-hidden rounded-full bg-n-slate-3"><div class="h-full rounded-full bg-gradient-to-r from-[#087cf0] to-[#7c3aed]" :style="{ width: `${Math.max(4, (Number(owner.revenue_cents || owner.value_cents || 0) / maxOwnerRevenue) * 100)}%` }" /></div>
                <strong class="text-right text-n-slate-12">{{ formatBRL(owner.revenue_cents || owner.value_cents || 0) }}</strong>
              </div>
            </div>
            <p v-else class="mt-5 text-sm text-n-slate-11">Sem dados de receita por vendedor no período.</p>
          </article>

          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <h3 class="font-bold text-n-slate-12">Propostas</h3>
            <div v-if="report.proposals_by_status.length" class="mt-4 space-y-2">
              <div v-for="item in report.proposals_by_status" :key="item.name" class="flex items-center justify-between rounded-xl border border-n-weak px-3 py-2.5">
                <span class="text-sm font-medium text-n-slate-11">{{ statusLabel(item.name) }}</span><strong class="text-n-slate-12">{{ item.count }}</strong>
              </div>
            </div>
            <p v-else class="py-8 text-center text-sm text-n-slate-11">Sem propostas no período.</p>
            <RouterLink :to="{ name: 'crm_proposals' }" class="mt-3 inline-flex text-sm font-semibold text-[#087cf0]">Abrir propostas →</RouterLink>
          </article>
        </section>
      </template>
    </div>
  </div>
</template>
