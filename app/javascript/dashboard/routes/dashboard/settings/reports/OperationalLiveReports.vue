<script setup>
import AgentLiveReportContainer from './components/AgentLiveReportContainer.vue';
import TeamLiveReportContainer from './components/TeamLiveReportContainer.vue';
import StatsLiveReportsContainer from './components/StatsLiveReportsContainer.vue';

defineProps({ embedded: { type: Boolean, default: false } });

const TEXT = Object.freeze({
  breadcrumb: 'Relatórios / Tempo real',
  title: 'Indicadores operacionais em tempo real',
  description:
    'Acompanhe conversas abertas, disponibilidade e distribuição atual da equipe.',
  back: 'Voltar à visão geral',
});
</script>

<template>
  <div class="flex flex-col gap-5 pb-10 pt-6">
    <header
      class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between"
    >
      <div>
        <p
          class="text-xs font-semibold uppercase tracking-[0.16em] text-n-brand"
        >
          {{ TEXT.breadcrumb }}
        </p>
        <h1 class="mt-2 text-3xl font-semibold tracking-tight text-n-slate-12">
          {{ TEXT.title }}
        </h1>
        <p class="mt-2 text-sm text-n-slate-10">
          {{ TEXT.description }}
        </p>
      </div>
      <RouterLink
        v-if="!embedded"
        :to="{ name: 'account_overview_reports' }"
        class="inline-flex h-9 items-center gap-2 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm font-semibold text-n-brand hover:border-n-blue-6"
      >
        <span class="i-lucide-arrow-left size-4" />
        {{ TEXT.back }}
      </RouterLink>
    </header>
    <StatsLiveReportsContainer />
    <AgentLiveReportContainer />
    <TeamLiveReportContainer />
  </div>
</template>
