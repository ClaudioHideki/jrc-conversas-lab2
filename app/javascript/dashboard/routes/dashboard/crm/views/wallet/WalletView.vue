<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, reactive, ref } from 'vue';
import { useRouter } from 'vue-router';
import { walletAPI } from 'dashboard/api/crm';
import { useCrmMetrics } from '../../composables/useCrmMetrics';
import { formatCrmDateTime } from '../../utils/dateTime';
import CrmPageHeader from '../../components/shared/CrmPageHeader.vue';
import CrmPanel from '../../components/shared/CrmPanel.vue';
import CrmStatCard from '../../components/shared/CrmStatCard.vue';

const router = useRouter();
const { formatBRL } = useCrmMetrics();
const loading = ref(true);
const error = ref('');
const wallet = reactive({
  active_deals: [],
  active_leads: [],
  todays_activities: [],
  hot_deals: [],
  totals: {},
});
const portfolioValue = computed(() => wallet.active_deals.reduce((sum, deal) => sum + Number(deal.value_cents || 0), 0));
const summaries = computed(() => [
  { label: 'Negócios ativos', value: wallet.totals.active_deals_count ?? wallet.active_deals.length, detail: 'Sob sua responsabilidade', icon: 'i-lucide-briefcase-business', tone: 'blue' },
  { label: 'Valor da carteira', value: formatBRL(portfolioValue.value), detail: 'Pipeline sob sua gestão', icon: 'i-lucide-circle-dollar-sign', tone: 'iris' },
  { label: 'Leads novos', value: wallet.totals.active_leads_count ?? wallet.active_leads.length, detail: 'Aguardando acompanhamento', icon: 'i-lucide-user-round-plus', tone: 'teal' },
  { label: 'Atividades hoje', value: wallet.totals.todays_activities_count ?? wallet.todays_activities.length, detail: 'Compromissos do dia', icon: 'i-lucide-calendar-check-2', tone: 'amber' },
  { label: 'Fechamentos próximos', value: wallet.hot_deals.length, detail: 'Previsão para sete dias', icon: 'i-lucide-target', tone: 'teal' },
  { label: 'Pendências', value: wallet.todays_activities.filter(item => item.overdue).length, detail: 'Exigem atenção', icon: 'i-lucide-triangle-alert', tone: 'ruby' },
]);
const openDeals = dealId =>
  router.push({ name: 'crm_deals', query: { dealId } });

onMounted(async () => {
  try {
    const { data } = await walletAPI.get();
    Object.assign(wallet, data);
    error.value = '';
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      'Não foi possível carregar sua carteira agora.';
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="h-full overflow-auto bg-n-surface-1">
    <div class="mx-auto flex w-full max-w-[1600px] flex-col gap-5 p-4 sm:p-6">
      <CrmPageHeader
        eyebrow="Comercial"
        title="Minha carteira"
        description="Negócios, leads e atividades sob sua responsabilidade."
        icon="i-lucide-briefcase-business"
      >
        <template #meta>
          <span
            class="inline-flex items-center gap-1.5 rounded-full border border-n-teal-6 bg-n-teal-3 px-3 py-1 text-xs font-medium text-n-teal-11"
          >
            <span class="size-1.5 rounded-full bg-n-teal-9" /> Atualizado agora
          </span>
        </template>
        <template #actions>
          <RouterLink
            :to="{ name: 'crm_leads', query: { new: '1' } }"
            class="rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white shadow-md"
          >
            <i class="i-lucide-plus mr-1 size-4" /> Novo lead
          </RouterLink>
          <RouterLink
            :to="{ name: 'crm_deals', query: { new: '1' } }"
            class="rounded-xl bg-n-teal-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md"
          >
            <i class="i-lucide-plus mr-1 size-4" /> Novo negócio
          </RouterLink>
          <RouterLink
            :to="{ name: 'crm_calendar' }"
            class="rounded-xl bg-n-iris-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md"
          >
            <i class="i-lucide-calendar-plus mr-1 size-4" /> Abrir agenda
          </RouterLink>
        </template>
      </CrmPageHeader>

      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
        <CrmStatCard
          v-for="item in summaries"
          :key="item.label"
          :label="item.label"
          :value="item.value"
          :detail="item.detail"
          :icon="item.icon"
          :tone="item.tone"
        />
      </div>

      <div
        v-if="loading"
        class="rounded-2xl border border-n-weak bg-n-solid-2 p-10 text-center text-sm text-n-slate-11 shadow-sm"
      >
        <span
          class="i-lucide-loader-circle mr-2 inline-block size-4 animate-spin"
        />
        Carregando carteira…
      </div>
      <div
        v-else-if="error"
        class="rounded-2xl border border-n-ruby-6 bg-n-ruby-3 p-8 text-center text-n-ruby-11"
      >
        {{ error }}
      </div>
      <div v-else class="grid gap-5 xl:grid-cols-2">
        <CrmPanel
          title="Meus negócios ativos"
          description="Oportunidades que estão em andamento."
          icon="i-lucide-briefcase-business"
          flush
        >
          <template #actions>
            <RouterLink
              :to="{ name: 'crm_deals' }"
              class="text-xs font-semibold text-n-brand"
            >
              Ver todos
            </RouterLink>
          </template>
          <div v-if="wallet.active_deals.length" class="divide-y divide-n-weak">
            <button
              v-for="deal in wallet.active_deals"
              :key="deal.id"
              type="button"
              class="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-4 px-5 py-4 text-left transition hover:bg-n-alpha-2"
              @click="openDeals(deal.id)"
            >
              <span class="min-w-0">
                <span class="block truncate font-medium text-n-slate-12">{{
                  deal.title
                }}</span>
                <span class="mt-1 block text-xs text-n-slate-11"
                  >Abrir detalhes do negócio</span
                >
              </span>
              <span class="flex items-center gap-2"><span class="text-sm font-semibold text-n-blue-11">{{ formatBRL(deal.value_cents) }}</span><span class="grid size-8 place-content-center rounded-lg bg-[#087cf0] text-white"><i class="i-lucide-phone size-3.5" /></span><span class="grid size-8 place-content-center rounded-lg bg-[#16a76b] text-white"><i class="i-ri-whatsapp-fill size-3.5" /></span><span class="grid size-8 place-content-center rounded-lg bg-[#7c3aed] text-white"><i class="i-lucide-calendar-days size-3.5" /></span></span>
            </button>
          </div>
          <p v-else class="p-5 text-sm text-n-slate-11">
            Nenhum negócio ativo.
          </p>
        </CrmPanel>

        <CrmPanel
          title="Minha agenda de hoje"
          description="Atividades organizadas por horário."
          icon="i-lucide-calendar-days"
          flush
        >
          <template #actions>
            <RouterLink
              :to="{ name: 'crm_calendar' }"
              class="text-xs font-semibold text-n-brand"
            >
              Ver agenda
            </RouterLink>
          </template>
          <div
            v-if="wallet.todays_activities.length"
            class="divide-y divide-n-weak"
          >
            <div
              v-for="activity in wallet.todays_activities"
              :key="activity.id"
              class="flex items-start gap-3 px-5 py-4"
            >
              <span
                class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-amber-3 text-n-amber-11"
              >
                <i class="i-lucide-calendar-check-2 size-4" />
              </span>
              <div class="min-w-0">
                <p class="truncate font-medium text-n-slate-12">
                  {{ activity.title }}
                </p>
                <p class="mt-1 text-xs text-n-slate-11">
                  {{
                    activity.due_at_display ||
                    formatCrmDateTime(activity.due_at)
                  }}
                </p>
              </div>
            </div>
          </div>
          <p v-else class="p-5 text-sm text-n-slate-11">
            Nenhuma atividade para hoje.
          </p>
        </CrmPanel>

        <CrmPanel
          title="Leads que precisam de atenção"
          icon="i-lucide-user-round-plus"
          flush
        >
          <template #actions>
            <RouterLink
              :to="{ name: 'crm_leads' }"
              class="text-xs font-semibold text-n-brand"
            >
              Ver leads
            </RouterLink>
          </template>
          <div v-if="wallet.active_leads.length" class="divide-y divide-n-weak">
            <div
              v-for="lead in wallet.active_leads"
              :key="lead.id"
              class="px-5 py-4"
            >
              <p class="font-medium text-n-slate-12">{{ lead.name }}</p>
              <p class="mt-1 text-xs text-n-slate-11">
                {{
                  lead.company_name ||
                  lead.email ||
                  lead.phone ||
                  'Sem contato informado'
                }}
              </p>
            </div>
          </div>
          <p v-else class="p-5 text-sm text-n-slate-11">Nenhum lead novo.</p>
        </CrmPanel>

        <CrmPanel title="Fechamentos próximos" icon="i-lucide-target" flush>
          <template #actions>
            <RouterLink
              :to="{ name: 'crm_funnel' }"
              class="text-xs font-semibold text-n-brand"
            >
              Abrir funil
            </RouterLink>
          </template>
          <div v-if="wallet.hot_deals.length" class="divide-y divide-n-weak">
            <button
              v-for="deal in wallet.hot_deals"
              :key="deal.id"
              type="button"
              class="flex w-full items-center justify-between gap-3 px-5 py-4 text-left transition hover:bg-n-alpha-2"
              @click="openDeals(deal.id)"
            >
              <span class="truncate font-medium text-n-slate-12">{{
                deal.title
              }}</span>
              <span
                class="rounded-full bg-n-teal-3 px-2.5 py-1 text-xs font-semibold text-n-teal-11"
                >Próximo</span
              >
            </button>
          </div>
          <p v-else class="p-5 text-sm text-n-slate-11">
            Nenhum fechamento previsto para os próximos sete dias.
          </p>
        </CrmPanel>
      </div>
      <section v-if="!loading && !error" class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"><div class="flex items-center gap-2"><i class="i-lucide-sparkles size-5 text-[#7c3aed]" /><h3 class="font-semibold text-n-slate-12">Prioridades recomendadas</h3></div><div class="mt-3 grid gap-3 lg:grid-cols-3"><RouterLink :to="{name:'crm_activities'}" class="rounded-xl border border-orange-200 bg-orange-50 p-3 text-sm font-semibold text-orange-800">Revisar atividades pendentes →</RouterLink><RouterLink :to="{name:'crm_leads'}" class="rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm font-semibold text-blue-800">Contatar leads sem retorno →</RouterLink><RouterLink :to="{name:'crm_funnel'}" class="rounded-xl border border-violet-200 bg-violet-50 p-3 text-sm font-semibold text-violet-800">Atualizar negócios sem atividade →</RouterLink></div></section>
    </div>
  </div>
</template>
