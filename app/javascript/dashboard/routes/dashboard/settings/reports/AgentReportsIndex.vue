<script setup>
import { ref } from 'vue';
import ReportHeader from './components/ReportHeader.vue';
import SummaryReports from './components/SummaryReports.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';

defineProps({ embedded: { type: Boolean, default: false } });

const summarReportsRef = ref(null);
const TEXT = Object.freeze({
  breadcrumb: 'Relatórios / Equipe',
  title: 'Desempenho da equipe',
  description:
    'Selecione um agente para abrir o desempenho individual no mesmo padrão da visão geral.',
  agents: 'Agentes',
  agentsDescription:
    'Dados reais de conversas, respostas e resoluções por agente.',
  back: 'Voltar à visão geral',
});

const onDownloadClick = () => {
  summarReportsRef.value.downloadReports();
};
</script>

<template>
  <div
    class="mt-6 rounded-3xl border border-n-blue-5 bg-gradient-to-br from-n-blue-3 via-n-solid-1 to-n-violet-3 px-6 py-7 shadow-sm"
  >
    <p class="text-xs font-semibold uppercase tracking-[0.16em] text-n-brand">
      {{ TEXT.breadcrumb }}
    </p>
    <div
      class="mt-2 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between"
    >
      <div>
        <h1 class="text-3xl font-semibold tracking-tight text-n-slate-12">
          {{ TEXT.title }}
        </h1>
        <p class="mt-2 text-sm text-n-slate-10">
          {{ TEXT.description }}
        </p>
      </div>
      <V4Button
        :label="$t('AGENT_REPORTS.DOWNLOAD_AGENT_REPORTS')"
        icon="i-ph-download-simple"
        size="sm"
        @click="onDownloadClick"
      />
    </div>
  </div>

  <ReportHeader
    :header-title="TEXT.agents"
    :header-description="TEXT.agentsDescription"
  >
    <V4Button
      v-if="!embedded"
      :label="TEXT.back"
      icon="i-ph-arrow-left"
      size="sm"
      variant="outline"
      @click="$router.push({ name: 'account_overview_reports' })"
    />
  </ReportHeader>

  <SummaryReports
    ref="summarReportsRef"
    action-key="summaryReports/fetchAgentSummaryReports"
    getter-key="agents/getAgents"
    fetch-items-key="agents/get"
    summary-key="summaryReports/getAgentSummaryReports"
    type="agent"
  />
</template>
