<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import CrmContactActions from '../../components/shared/CrmContactActions.vue';
import { useCommercialLabels } from '../../composables/useCommercialLabels';
import { customersAPI } from 'dashboard/api/crm/commercialCycle';
import { useAlert } from 'dashboard/composables';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';

const { statusLabel } = useCommercialLabels();
const route = useRoute();
const router = useRouter();
const { openWithPrompt } = useJrcCopilot();
const loading = ref(true);
const data = ref(null);
const activeTab = ref('overview');
const tabs = [
  ['overview', 'Visão Geral'], ['deals', 'Negócios'], ['proposals', 'Propostas'],
  ['orders', 'Pedidos'], ['contracts', 'Contratos'], ['timeline', 'Atividades'],
];
const profile = computed(() => data.value?.profile || {});
const metrics = computed(() => data.value?.metrics || {});
const deals = computed(() => data.value?.deals || []);
const allProposals = computed(() => deals.value.flatMap(deal => (deal.proposals || []).map(item => ({ ...item, deal }))));
const allOrders = computed(() => data.value?.orders || deals.value.flatMap(deal => (deal.orders || []).map(item => ({ ...item, deal }))));
const allContracts = computed(() => data.value?.contracts || deals.value.flatMap(deal => (deal.contracts || []).map(item => ({ ...item, deal }))));
const money = cents => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format((Number(cents) || 0) / 100);
const dateTime = value => value ? new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value)) : '—';
const initials = computed(() => (profile.value.name || 'C').split(/\s+/).slice(0, 2).map(part => part[0]).join('').toUpperCase());

const load = async () => {
  loading.value = true;
  try {
    const { data: response } = await customersAPI.show(route.params.customerId);
    data.value = response;
  } catch (error) {
    useAlert(error.response?.data?.error || 'Não foi possível carregar o Cliente 360°.');
  } finally {
    loading.value = false;
  }
};
const newDeal = () => router.push({ name: 'crm_deals', params: { accountId: route.params.accountId }, query: { new: '1', contactId: profile.value.id } });
const newProposal = () => router.push({ name: 'crm_proposals', params: { accountId: route.params.accountId }, query: { new: '1', contactId: profile.value.id } });
const openDeal = id => router.push({ name: 'crm_deals', params: { accountId: route.params.accountId }, query: { dealId: id } });
const openProposals = item => router.push({ name: 'crm_proposals', params: { accountId: route.params.accountId }, query: { proposalId: item.id } });

onMounted(load);
</script>

<template>
  <div class="h-full overflow-auto break-words bg-n-surface-1 p-4 sm:p-6">
    <div v-if="loading" class="grid min-h-96 place-content-center text-sm text-n-slate-11">Carregando Cliente 360°…</div>
    <template v-else-if="data">
      <header
        class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="flex min-w-0 items-center gap-4">
            <span class="grid size-16 place-content-center rounded-2xl bg-emerald-700 text-xl font-bold text-white">{{ initials }}</span>
            <div>
              <div class="flex flex-wrap items-center gap-2"><h1 class="text-2xl font-bold text-n-slate-12">{{ profile.name }}</h1><span class="rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700">Cliente</span></div>
              <p class="mt-1 text-sm text-n-slate-11">{{ profile.company || profile.email || profile.phone_number || 'Cadastro comercial' }}</p>
            </div>
          </div>
          <div class="grid min-w-0 grid-cols-2 gap-x-4 gap-y-3 text-xs min-[1280px]:grid-cols-4 [&_strong]:break-words">
            <div><span class="block text-n-slate-11">Pipeline</span><strong class="text-sm text-n-slate-12">{{ money(metrics.pipeline_cents) }}</strong></div>
            <div><span class="block text-n-slate-11">Negócios</span><strong class="text-sm text-n-slate-12">{{ metrics.deals || 0 }}</strong></div>
            <div><span class="block text-n-slate-11">Último contato</span><strong class="text-sm text-n-slate-12">{{ dateTime(profile.last_activity_at) }}</strong></div>
            <div><span class="block text-n-slate-11">Próxima atividade</span><strong class="text-sm text-n-slate-12">{{ metrics.next_activity?.title || 'Não definida' }}</strong></div>
          </div>
        </div>
        <div class="mt-5 flex flex-wrap gap-2 border-t border-n-weak pt-4">
          <CrmContactActions :contact="profile" />
          <button class="rounded-lg bg-n-brand px-3 py-2 text-xs font-semibold text-white" @click="newDeal"><i class="i-lucide-plus mr-1" />Novo negócio</button>
          <button class="rounded-lg border border-n-brand px-3 py-2 text-xs font-semibold text-n-brand" @click="newProposal"><i class="i-lucide-file-plus-2 mr-1" />Nova proposta</button>
          <button class="rounded-lg border border-violet-300 bg-violet-50 px-3 py-2 text-xs font-semibold text-violet-700" @click="openWithPrompt(`Resuma o histórico comercial de ${profile.name}, os negócios ativos, pendências e recomende o próximo follow-up.`)"><i class="i-lucide-bot mr-1" />Perguntar ao NICO</button>
        </div>
      </header>

      <nav class="mt-4 flex gap-1 overflow-x-auto rounded-xl border border-n-weak bg-n-solid-2 p-1 shadow-sm">
        <button v-for="tab in tabs" :key="tab[0]" class="whitespace-nowrap rounded-lg px-3 py-2 text-xs font-semibold" :class="activeTab === tab[0] ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-2'" @click="activeTab = tab[0]">{{ tab[1] }}</button>
      </nav>

      <section v-if="activeTab === 'overview'" class="mt-4 grid gap-4 xl:grid-cols-[320px_1fr]">
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-1">
          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><p class="text-xs font-semibold uppercase text-n-slate-11">Resumo</p><dl class="mt-3 grid grid-cols-2 gap-3 text-sm"><div><dt class="text-xs text-n-slate-11">Negócios abertos</dt><dd class="text-xl font-bold">{{ metrics.open_deals || 0 }}</dd></div><div><dt class="text-xs text-n-slate-11">Ganhos</dt><dd class="text-xl font-bold">{{ metrics.won_deals || 0 }}</dd></div><div><dt class="text-xs text-n-slate-11">Propostas</dt><dd class="text-xl font-bold">{{ metrics.proposals || 0 }}</dd></div><div><dt class="text-xs text-n-slate-11">Pedidos</dt><dd class="text-xl font-bold">{{ metrics.orders || 0 }}</dd></div></dl></article>
          <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><p class="text-xs font-semibold uppercase text-n-slate-11">Contato</p><p class="mt-3 break-words text-sm"><strong>E-mail</strong><br>{{ profile.email || '—' }}</p><p class="mt-3 break-words text-sm"><strong>Telefone</strong><br>{{ profile.phone_number || '—' }}</p></article>
        </div>
        <article class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><div class="flex items-center justify-between"><h2 class="font-semibold text-n-slate-12">Negócios do cliente</h2><button class="text-xs font-semibold text-n-brand" @click="newDeal">+ Novo Negócio</button></div><div class="mt-3 grid gap-3 md:grid-cols-2"><button v-for="deal in deals" :key="deal.id" class="rounded-xl border border-n-weak p-3 text-left transition hover:border-n-brand/50 hover:bg-n-alpha-2" @click="openDeal(deal.id)"><div class="flex items-start justify-between gap-2"><strong class="truncate">{{ deal.title }}</strong><span class="rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-semibold text-blue-700">{{ deal.stage || statusLabel(deal.status) }}</span></div><p class="mt-2 text-lg font-bold">{{ money(deal.value_cents) }}</p><p class="mt-1 text-xs text-n-slate-11">Responsável: {{ deal.owner || '—' }}</p></button><p v-if="!deals.length" class="text-sm text-n-slate-11">Nenhum negócio vinculado.</p></div></article>
      </section>

      <section v-else-if="activeTab === 'deals'" class="mt-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><div class="flex items-center justify-between"><h2 class="font-semibold">Negócios</h2><button class="rounded-lg bg-n-brand px-3 py-2 text-xs font-semibold text-white" @click="newDeal">+ Novo Negócio</button></div><div class="mt-3 divide-y divide-n-weak"><button v-for="deal in deals" :key="deal.id" class="flex w-full items-center justify-between gap-3 py-3 text-left" @click="openDeal(deal.id)"><div><strong>{{ deal.title }}</strong><p class="text-xs text-n-slate-11">{{ deal.stage }} · {{ deal.owner || 'Sem responsável' }}</p></div><div class="text-right"><strong>{{ money(deal.value_cents) }}</strong><p class="text-xs text-n-slate-11">{{ statusLabel(deal.status) }}</p></div></button></div></section>
      <section v-else-if="activeTab === 'proposals'" class="mt-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><h2 class="font-semibold">Propostas</h2><div class="mt-3 divide-y divide-n-weak"><button v-for="proposal in allProposals" :key="proposal.id" class="flex w-full items-center justify-between py-3 text-left" @click="openProposals(proposal)"><div><strong>{{ proposal.number }}</strong><p class="text-xs text-n-slate-11">{{ proposal.deal.title }}</p></div><span class="rounded-full bg-amber-50 px-2 py-1 text-xs font-semibold text-amber-700">{{ statusLabel(proposal.status) }}</span></button><p v-if="!allProposals.length" class="py-6 text-sm text-n-slate-11">Nenhuma proposta.</p></div></section>
      <section v-else-if="activeTab === 'orders'" class="mt-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><h2 class="font-semibold">Pedidos / Vendas</h2><div class="mt-3 divide-y divide-n-weak"><div v-for="order in allOrders" :key="order.id" class="flex items-center justify-between py-3"><div><strong>{{ order.number }}</strong><p class="text-xs text-n-slate-11">{{ order.deal?.title || 'Pedido direto' }}</p></div><div class="text-right"><strong>{{ money(order.total_cents) }}</strong><p class="text-xs text-n-slate-11">{{ statusLabel(order.status) }}</p></div></div><p v-if="!allOrders.length" class="py-6 text-sm text-n-slate-11">Nenhum pedido.</p></div></section>
      <section v-else-if="activeTab === 'contracts'" class="mt-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><h2 class="font-semibold">Contratos</h2><div class="mt-3 divide-y divide-n-weak"><div v-for="contract in allContracts" :key="contract.id" class="flex items-center justify-between py-3"><div><strong>{{ contract.number }}</strong><p class="text-xs text-n-slate-11">{{ contract.deal?.title || 'Contrato direto' }}</p></div><div class="text-right"><strong>{{ money(contract.monthly_cents) }}/mês</strong><p class="text-xs text-n-slate-11">{{ statusLabel(contract.status) }}</p></div></div><p v-if="!allContracts.length" class="py-6 text-sm text-n-slate-11">Nenhum contrato.</p></div></section>
      <section v-else class="mt-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><h2 class="font-semibold">Timeline comercial</h2><div class="mt-4 space-y-4"><div v-for="item in data.timeline" :key="item.id" class="relative border-l-2 border-blue-100 pl-5"><span class="absolute -left-[7px] top-1 size-3 rounded-full bg-blue-500" /><strong class="text-sm">{{ item.title }}</strong><p class="text-xs text-n-slate-11">{{ item.deal?.title || 'Relacionamento' }} · {{ dateTime(item.created_at) }}</p><p v-if="item.description" class="mt-1 text-sm text-n-slate-11">{{ item.description }}</p></div><p v-if="!data.timeline?.length" class="text-sm text-n-slate-11">Ainda não há atividades comerciais registradas.</p></div></section>
    </template>
  </div>
</template>
