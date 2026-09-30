<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, ref } from 'vue';
import jrcAiAPI from 'dashboard/api/jrcAi';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';

const { openWithPrompt } = useJrcCopilot();
const loading = ref(false);
const error = ref('');
const data = ref({ summary: {}, attention: [], ai_agents: [], channel_distribution: [] });

const load = async () => {
  loading.value = true;
  try {
    const response = await jrcAiAPI.cockpit('7_days');
    data.value = response.data;
    error.value = '';
  } catch (requestError) {
    error.value = requestError?.response?.data?.error || 'Nao foi possivel gerar os insights.';
  } finally {
    loading.value = false;
  }
};
const insights = computed(() => [
  { title: 'Fila e prioridade', text: `${data.value.summary.conversations_waiting || 0} conversa(s) aguardando e ${data.value.summary.sla_risk_count || 0} em risco operacional.`, icon: 'i-lucide-clock-alert', tone: 'rose' },
  { title: 'Disciplina de retorno', text: `${data.value.summary.overdue_returns || 0} retorno(s) vencido(s) e ${data.value.summary.appointments_today || 0} compromisso(s) hoje.`, icon: 'i-lucide-calendar-clock', tone: 'amber' },
  { title: 'Oportunidade comercial', text: `${data.value.summary.active_leads || 0} lead(s) ativo(s) e ${data.value.summary.open_deals || 0} negocio(s) em aberto.`, icon: 'i-lucide-target', tone: 'violet' },
  { title: 'Qualidade percebida', text: data.value.summary.csat_percent == null ? 'Ainda nao ha respostas suficientes de CSAT no periodo.' : `CSAT atual de ${data.value.summary.csat_percent}%.`, icon: 'i-lucide-smile', tone: 'teal' },
]);
const tone = value => ({ rose: 'bg-rose-50 text-rose-700', amber: 'bg-amber-50 text-amber-700', violet: 'bg-violet-50 text-violet-700', teal: 'bg-teal-50 text-teal-700' }[value]);

onMounted(load);
</script>

<template>
  <main class="h-full overflow-auto bg-n-surface-1 p-4 sm:p-5"><div class="mx-auto max-w-[1450px] space-y-4"><header class="rounded-3xl bg-gradient-to-r from-[#062f57] via-[#075a87] to-[#00a6a6] p-6 text-white shadow-lg"><span class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-[11px] font-bold uppercase"><i class="i-lucide-lightbulb size-4" /> Inteligencia operacional</span><h1 class="mt-3 text-3xl font-bold text-inherit">Insights de IA</h1><p class="mt-2 text-sm text-blue-50/90">Leituras objetivas, recomendacoes e oportunidades baseadas nos dados que o usuario pode acessar.</p></header>
  <div v-if="error" class="rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">{{ error }}</div>
  <section class="grid gap-4 md:grid-cols-2 xl:grid-cols-4"><article v-for="item in insights" :key="item.title" class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"><span class="grid size-11 place-content-center rounded-xl" :class="tone(item.tone)"><i class="size-5" :class="item.icon" /></span><h2 class="mt-4 font-bold text-n-slate-12">{{ item.title }}</h2><p class="mt-2 text-sm leading-6 text-n-slate-11">{{ item.text }}</p></article></section>
  <section class="grid gap-4 xl:grid-cols-2"><article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"><div class="flex items-center justify-between"><h2 class="text-lg font-bold text-n-slate-12">Recomendacoes</h2><button class="text-xs font-semibold text-blue-600" @click="openWithPrompt('Analise os insights atuais e organize as recomendacoes por impacto e urgencia.')">Aprofundar com o Copiloto</button></div><div class="mt-4 space-y-3"><button v-for="item in data.attention" :key="item.key" class="flex w-full items-start gap-3 rounded-xl bg-n-surface-1 p-4 text-left" @click="openWithPrompt(`Ajude a resolver: ${item.title}. ${item.description}`)"><span class="grid size-9 place-content-center rounded-xl bg-n-solid-2"><i class="i-lucide-arrow-up-right size-4 text-blue-600" /></span><span><b class="text-sm text-n-slate-12">{{ item.title }} ({{ item.count }})</b><small class="mt-1 block text-n-slate-11">{{ item.description }}</small></span></button></div></article>
  <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"><h2 class="text-lg font-bold text-n-slate-12">Especialistas consultados</h2><div class="mt-4 space-y-3"><div v-for="agent in data.ai_agents" :key="agent.key" class="flex items-center gap-3 rounded-xl border border-n-weak p-3"><span class="grid size-9 place-content-center rounded-xl bg-violet-50 text-violet-700"><i class="i-lucide-bot size-4" /></span><div class="min-w-0 flex-1"><b class="text-sm text-n-slate-12">{{ agent.name }}</b><p class="truncate text-xs text-n-slate-11">{{ agent.last_result }}</p></div><button class="text-xs font-semibold text-blue-600" @click="openWithPrompt(agent.prompt)">Consultar</button></div></div></article></section>
  <button class="fixed bottom-24 right-5 grid size-10 place-content-center rounded-xl bg-n-solid-2 text-blue-700 shadow" :disabled="loading" @click="load"><i class="i-lucide-refresh-cw size-4" :class="{ 'animate-spin': loading }" /></button></div></main>
</template>
