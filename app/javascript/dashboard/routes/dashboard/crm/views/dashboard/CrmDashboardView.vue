<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useCrmMetrics } from '../../composables/useCrmMetrics';

const store = useStore();
const { formatBRL } = useCrmMetrics();

const metrics = computed(() => store.getters['jrcCrm/dashboard/metrics'] || {});
const isLoading = computed(() => store.getters['jrcCrm/dashboard/isLoading']);
const stages = computed(() => metrics.value.funnel_stages || []);
const pipelineValue = computed(() =>
  Number(metrics.value.pipeline_value_cents || 0) ||
  stages.value.reduce((sum, stage) => sum + Number(stage.value_cents || 0), 0)
);
const weightedValue = computed(() => Number(metrics.value.weighted_value_cents || 0));
const wonRevenue = computed(() => Number(metrics.value.won_revenue_cents || 0));
const conversion = computed(() => Number(metrics.value.conversion_rate || 0));
const maxStageCount = computed(() =>
  Math.max(...stages.value.map(stage => Number(stage.deals_count || 0)), 1)
);
const totalFunnelDeals = computed(() =>
  stages.value.reduce((sum, stage) => sum + Number(stage.deals_count || 0), 0)
);

const cards = computed(() => [
  {
    label: 'Leads novos',
    value: metrics.value.new_leads_count ?? metrics.value.leads_count ?? 0,
    helper: 'Base comercial atual',
    icon: 'i-lucide-users-round',
    accent: 'border-blue-200 bg-blue-50 text-blue-600',
  },
  {
    label: 'Pipeline aberto',
    value: formatBRL(pipelineValue.value),
    helper: `${metrics.value.open_deals_count || 0} negócios em andamento`,
    icon: 'i-lucide-circle-dollar-sign',
    accent: 'border-violet-200 bg-violet-50 text-violet-600',
  },
  {
    label: 'Receita prevista',
    value: formatBRL(weightedValue.value),
    helper: 'Valor ponderado por probabilidade',
    icon: 'i-lucide-crosshair',
    accent: 'border-cyan-200 bg-cyan-50 text-cyan-700',
  },
  {
    label: 'Receita ganha',
    value: formatBRL(wonRevenue.value),
    helper: `${metrics.value.closed_won_count || 0} negócios ganhos`,
    icon: 'i-lucide-trophy',
    accent: 'border-emerald-200 bg-emerald-50 text-emerald-700',
  },
  {
    label: 'Conversão',
    value: `${conversion.value.toLocaleString('pt-BR')}%`,
    helper: 'Taxa de negócios encerrados',
    icon: 'i-lucide-chart-no-axes-combined',
    accent: 'border-orange-200 bg-orange-50 text-orange-600',
  },
  {
    label: 'Ticket médio',
    value: formatBRL(metrics.value.average_ticket_cents || 0),
    helper: 'Valor médio dos negócios ganhos',
    icon: 'i-lucide-receipt-text',
    accent: 'border-rose-200 bg-rose-50 text-rose-600',
  },
]);

const stagePalette = [
  'from-blue-600 to-blue-500',
  'from-sky-500 to-cyan-400',
  'from-cyan-500 to-teal-400',
  'from-teal-500 to-emerald-400',
  'from-emerald-500 to-green-400',
  'from-green-500 to-lime-400',
  'from-rose-500 to-red-400',
];

const stageWidth = stage => {
  const count = Number(stage.deals_count || 0);
  return `${Math.max(10, (count / maxStageCount.value) * 100)}%`;
};

onMounted(() => store.dispatch('jrcCrm/dashboard/fetchMetrics'));
</script>

<template>
  <div class="h-full overflow-y-auto bg-gradient-to-br from-n-blue-2 via-n-background to-n-violet-2 p-4 sm:p-6">
    <div class="mx-auto max-w-[1720px] space-y-5">
      <section class="flex flex-wrap items-end justify-between gap-4 rounded-2xl border border-white/70 bg-n-solid-2/80 p-5 shadow-sm backdrop-blur">
        <div>
          <div class="mb-2 flex items-center gap-2">
            <span class="grid size-9 place-content-center rounded-xl bg-[#087cf0] text-white shadow-[0_8px_20px_rgba(8,124,240,.20)]">
              <i class="i-lucide-chart-no-axes-combined size-5" />
            </span>
            <div>
              <h2 class="text-2xl font-bold text-n-slate-12">Central de vendas</h2>
              <p class="text-sm text-n-slate-11">Acompanhe o desempenho comercial e avance nas oportunidades.</p>
            </div>
          </div>
          <span class="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700">
            <i class="i-lucide-database size-3.5" /> Dados reais do CRM
          </span>
        </div>

        <div class="flex flex-wrap gap-2">
          <RouterLink :to="{ name: 'crm_wallet' }" class="rounded-xl bg-[#17345f] px-4 py-2.5 text-sm font-semibold text-white shadow-[0_8px_18px_rgba(23,52,95,.20)]">
            <i class="i-lucide-briefcase-business mr-1 size-4" /> Minha carteira
          </RouterLink>
          <RouterLink :to="{ name: 'crm_funnel' }" class="rounded-xl bg-[#087cf0] px-4 py-2.5 text-sm font-semibold text-white shadow-[0_8px_20px_rgba(8,124,240,.24)]">
            <i class="i-lucide-filter mr-1 size-4" /> Abrir funil
          </RouterLink>
        </div>
      </section>

      <div v-if="isLoading" class="grid min-h-72 place-content-center rounded-2xl border border-n-weak bg-n-solid-2 text-sm text-n-slate-11">
        <span class="i-lucide-loader-circle mr-2 inline-block size-5 animate-spin" /> Carregando visão geral…
      </div>

      <template v-else>
        <section class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
          <article v-for="card in cards" :key="card.label" class="group rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
            <div class="flex items-start justify-between gap-3">
              <span class="text-xs font-semibold text-n-slate-11">{{ card.label }}</span>
              <span class="grid size-10 place-content-center rounded-xl border" :class="card.accent">
                <i class="size-4" :class="card.icon" />
              </span>
            </div>
            <strong class="mt-3 block truncate text-2xl font-bold text-n-slate-12">{{ card.value }}</strong>
            <small class="mt-1 block min-h-8 text-n-slate-11">{{ card.helper }}</small>
          </article>
        </section>

        <section class="grid gap-5 xl:grid-cols-[1.12fr_.88fr]">
          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <div class="mb-4 flex items-center justify-between gap-3">
              <div>
                <h3 class="text-lg font-bold text-n-slate-12">Funil de vendas</h3>
                <p class="mt-1 text-xs text-n-slate-11">Quantidade e valor por etapa do pipeline.</p>
              </div>
              <RouterLink :to="{ name: 'crm_funnel' }" class="text-sm font-semibold text-[#087cf0]">Ver Kanban →</RouterLink>
            </div>

            <div v-if="stages.length" class="space-y-2.5">
              <div v-for="(stage, index) in stages" :key="stage.id" class="grid grid-cols-[minmax(170px,1fr)_72px_130px] items-center gap-3 rounded-xl border border-n-weak bg-n-slate-2 p-3">
                <div class="min-w-0">
                  <div class="mb-1.5 flex items-center gap-2">
                    <span class="grid size-7 place-content-center rounded-lg bg-gradient-to-br text-white" :class="stagePalette[index % stagePalette.length]">
                      <i class="i-lucide-sparkles size-3.5" />
                    </span>
                    <strong class="truncate text-sm text-n-slate-12">{{ stage.name }}</strong>
                  </div>
                  <div class="h-2 overflow-hidden rounded-full bg-n-slate-4">
                    <div class="h-full rounded-full bg-gradient-to-r" :class="stagePalette[index % stagePalette.length]" :style="{ width: stageWidth(stage) }" />
                  </div>
                </div>
                <span class="text-right text-sm font-semibold text-n-slate-12">{{ stage.deals_count }}</span>
                <span class="text-right text-sm font-semibold text-n-slate-12">{{ formatBRL(stage.value_cents || 0) }}</span>
              </div>
              <div class="flex items-center justify-between border-t border-n-weak pt-3 text-sm">
                <span class="font-semibold text-n-slate-11">Total nas etapas</span>
                <span class="font-bold text-n-slate-12">{{ totalFunnelDeals }} oportunidades · {{ formatBRL(pipelineValue) }}</span>
              </div>
            </div>
            <p v-else class="py-12 text-center text-sm text-n-slate-11">Nenhum dado de funil disponível.</p>
          </article>

          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <div class="flex items-start justify-between gap-3">
              <div>
                <h3 class="text-lg font-bold text-n-slate-12">Prioridades de hoje</h3>
                <p class="mt-1 text-xs text-n-slate-11">Pontos que merecem atenção imediata.</p>
              </div>
              <span class="rounded-lg bg-n-slate-2 px-2.5 py-1 text-xs font-semibold text-n-slate-11">Operacional</span>
            </div>

            <div class="mt-4 space-y-3">
              <div class="grid grid-cols-[1fr_auto_auto] items-center gap-3 rounded-xl border border-n-ruby-6 bg-n-ruby-2 p-3">
                <div><strong class="text-sm text-n-slate-12">Atividades vencidas</strong><p class="text-xs text-n-slate-11">Exigem atenção imediata</p></div>
                <b class="text-n-ruby-11">{{ metrics.overdue_activities_count || 0 }}</b>
                <div class="flex gap-1">
                  <RouterLink :to="{ name: 'crm_activities' }" class="grid size-9 place-content-center rounded-lg bg-[#087cf0] text-white" title="Abrir atividades"><i class="i-lucide-list-checks size-4" /></RouterLink>
                  <RouterLink :to="{ name: 'crm_calendar' }" class="grid size-9 place-content-center rounded-lg bg-[#7c3aed] text-white" title="Abrir agenda"><i class="i-lucide-calendar-days size-4" /></RouterLink>
                </div>
              </div>

              <div class="grid grid-cols-[1fr_auto_auto] items-center gap-3 rounded-xl border border-orange-200 dark:border-orange-800 bg-orange-50 dark:bg-orange-950 p-3">
                <div><strong class="text-sm text-n-slate-12">Negócios estagnados</strong><p class="text-xs text-n-slate-11">Sem atualização há mais de 7 dias</p></div>
                <b class="text-orange-700 dark:text-orange-300">{{ metrics.stalled_deals_count || 0 }}</b>
                <div class="flex gap-1">
                  <RouterLink :to="{ name: 'crm_deals' }" class="grid size-9 place-content-center rounded-lg bg-[#16a76b] text-white" title="Abrir negócios"><i class="i-lucide-handshake size-4" /></RouterLink>
                  <RouterLink :to="{ name: 'crm_calendar' }" class="grid size-9 place-content-center rounded-lg bg-[#7c3aed] text-white" title="Agendar retorno"><i class="i-lucide-calendar-days size-4" /></RouterLink>
                </div>
              </div>
            </div>

            <div class="mt-5 grid grid-cols-2 gap-3 border-t border-n-weak pt-4">
              <div class="rounded-xl bg-n-slate-2 p-3">
                <span class="text-xs text-n-slate-11">Ganhos</span>
                <strong class="mt-1 block text-xl text-emerald-700">{{ metrics.closed_won_count || 0 }}</strong>
              </div>
              <div class="rounded-xl bg-n-slate-2 p-3">
                <span class="text-xs text-n-slate-11">Perdidos</span>
                <strong class="mt-1 block text-xl text-rose-600">{{ metrics.closed_lost_count || 0 }}</strong>
              </div>
            </div>
          </article>
        </section>

        <section class="grid gap-5 xl:grid-cols-[1fr_.8fr]">
          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <div class="flex items-center justify-between gap-3">
              <div>
                <h3 class="font-bold text-n-slate-12">Pipeline comercial</h3>
                <p class="mt-1 text-xs text-n-slate-11">Valor aberto, ponderado e realizado com dados do CRM.</p>
              </div>
              <RouterLink :to="{ name: 'crm_indicators' }" class="text-sm font-semibold text-[#087cf0]">Ver indicadores →</RouterLink>
            </div>
            <div class="mt-4 grid gap-3 sm:grid-cols-3">
              <div class="rounded-xl border border-blue-100 bg-blue-50/70 p-4"><span class="text-xs font-semibold text-blue-700">Pipeline aberto</span><strong class="mt-2 block text-xl text-n-slate-12">{{ formatBRL(pipelineValue) }}</strong></div>
              <div class="rounded-xl border border-cyan-100 bg-cyan-50/70 p-4"><span class="text-xs font-semibold text-cyan-700">Valor ponderado</span><strong class="mt-2 block text-xl text-n-slate-12">{{ formatBRL(weightedValue) }}</strong></div>
              <div class="rounded-xl border border-emerald-100 bg-emerald-50/70 p-4"><span class="text-xs font-semibold text-emerald-700">Receita ganha</span><strong class="mt-2 block text-xl text-n-slate-12">{{ formatBRL(wonRevenue) }}</strong></div>
            </div>
          </article>

          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm">
            <h3 class="font-bold text-n-slate-12">Ações rápidas</h3>
            <p class="mt-1 text-xs text-n-slate-11">Atalhos para continuar o trabalho comercial.</p>
            <div class="mt-4 grid grid-cols-2 gap-2">
              <RouterLink :to="{ name: 'crm_leads' }" class="rounded-xl bg-blue-50 px-3 py-3 text-sm font-semibold text-blue-700"><i class="i-lucide-user-plus mr-1 size-4" /> Leads</RouterLink>
              <RouterLink :to="{ name: 'crm_deals' }" class="rounded-xl bg-emerald-50 px-3 py-3 text-sm font-semibold text-emerald-700"><i class="i-lucide-handshake mr-1 size-4" /> Negócios</RouterLink>
              <RouterLink :to="{ name: 'crm_activities' }" class="rounded-xl bg-orange-50 px-3 py-3 text-sm font-semibold text-orange-700"><i class="i-lucide-list-checks mr-1 size-4" /> Atividades</RouterLink>
              <RouterLink :to="{ name: 'crm_calendar' }" class="rounded-xl bg-violet-50 px-3 py-3 text-sm font-semibold text-violet-700"><i class="i-lucide-calendar-days mr-1 size-4" /> Agenda</RouterLink>
            </div>
          </article>
        </section>
      </template>
    </div>
  </div>
</template>
