<template>
  <div class="deal-detail h-full flex flex-col bg-n-alpha-2">
    <div
      class="bg-n-solid-2 border-b border-n-weak p-6 flex flex-col md:flex-row justify-between items-start md:items-center gap-4"
    >
      <div>
        <div class="flex items-center gap-2 mb-1">
          <router-link
            :to="{ name: 'crm_deals' }"
            class="text-sm text-n-slate-10 hover:text-n-blue-11"
            >Negócios</router-link
          >
          <span class="text-n-slate-10">/</span>
          <span class="text-sm text-n-slate-11">Detalhes</span>
        </div>
        <h2 class="text-2xl font-bold text-n-slate-12 flex items-center gap-3">
          {{ deal?.title || 'Carregando...' }}
          <CrmStatusBadge v-if="deal" :value="deal.status" />
        </h2>
          <ApprovalGateBadge v-if="deal" resource-key="crm.deal_price" :resource-id="deal.id" />
        <div
          class="text-sm text-n-slate-10 mt-1 flex items-center gap-4"
          v-if="deal"
        >
          <span class="flex items-center gap-1"
            ><i class="i-lucide-dollar-sign w-4 h-4"></i>
            <CrmValueDisplay
              :cents="deal.value_cents"
              class="font-medium text-n-slate-11"
          /></span>
          <span class="flex items-center gap-1"
            ><i class="i-lucide-user w-4 h-4"></i>
            {{ deal.owner?.name || 'Sem responsável' }}</span
          >
          <span class="flex items-center gap-1"
            ><i class="i-lucide-building w-4 h-4"></i>
            {{ deal.company?.name || 'Sem empresa' }}</span
          >
        </div>
      </div>

      <div class="flex gap-2" v-if="deal && deal.status === 'open'">
        <button
          class="bg-n-ruby-3 text-n-ruby-11 border border-n-ruby-6 hover:bg-n-ruby-4 px-4 py-2 rounded text-sm font-medium"
        >
          Perdido
        </button>
        <button
          class="bg-n-teal-10 hover:bg-n-teal-11 text-white px-4 py-2 rounded text-sm font-medium shadow-sm"
        >
          Ganho
        </button>
      </div>
    </div>

    <div class="flex-1 overflow-auto p-6">
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 space-y-6">
          <div class="bg-n-solid-2 border border-n-weak rounded-lg shadow-sm p-5">
            <h3 class="text-lg font-semibold text-n-slate-12 mb-4 border-b pb-2">
              Etapa do Funil
            </h3>
            <div class="text-n-slate-11">{{ deal?.stage?.name || '-' }}</div>
          </div>

          <div class="bg-n-solid-2 border border-n-weak rounded-lg shadow-sm p-5">
            <div class="flex items-center justify-between border-b pb-2 mb-4">
              <h3 class="text-lg font-semibold text-n-slate-12">Timeline</h3>
              <button class="text-sm text-n-blue-11 font-medium hover:underline">
                + Atividade
              </button>
            </div>
            <ActivityTimeline :events="timelineEvents" />
          </div>
        </div>

        <div class="space-y-6">
          <Customer360Panel
            :contact="deal?.main_contact"
            :company="deal?.company"
            :metrics="{ open_deals: 1, won_deals: 0 }"
            v-if="deal"
          />

          <div class="bg-n-solid-2 border border-n-weak rounded-lg shadow-sm p-5">
            <div class="flex items-center justify-between border-b pb-2 mb-4">
              <h3 class="font-semibold text-n-slate-12">Propostas</h3>
              <button class="text-sm text-n-blue-11">+</button>
            </div>
            <div class="text-sm text-n-slate-10 text-center py-4">
              Nenhuma proposta vinculada
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import ApprovalGateBadge from 'dashboard/routes/dashboard/approvals/ApprovalGateBadge.vue';
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import CrmValueDisplay from '../../components/shared/CrmValueDisplay.vue';
import ActivityTimeline from '../../components/shared/ActivityTimeline.vue';
import Customer360Panel from '../../components/shared/Customer360Panel.vue';

const store = useStore();
const route = useRoute();

const deal = computed(() => store.state.jrcCrm?.deals?.currentDeal);
const timelineEvents = ref([]);

onMounted(async () => {
  const dealId = route.params.dealId;
  if (dealId) {
    await store.dispatch('jrcCrm/deals/fetchDeal', dealId);
    // Placeholder for timeline fetch
    timelineEvents.value = [
      { id: 1, title: 'Negócio criado', created_at: new Date().toISOString() },
    ];
  }
});
</script>
