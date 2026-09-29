<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, reactive, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import {
  leadsAPI,
  pipelinesAPI,
  productsAPI,
  stagesAPI,
} from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import LeadConversionModal from './LeadConversionModal.vue';
import LeadDetailModal from './LeadDetailModal.vue';
import LeadCreateModal from './LeadCreateModal.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const showForm = ref(false);
const viewMode = ref('list');
const saving = ref(false);
const changingId = ref(null);
const deletingId = ref(null);
const convertingLead = ref(null);
const pipelines = ref([]);
const products = ref([]);
const filters = reactive({ search: '', status: '' });
const leads = computed(() => store.getters['jrcCrm/leads/allLeads'] || []);
const leadSummary = computed(() => ([
  { label: 'Novos', value: leads.value.filter(item => item.status === 'new').length, tone: 'blue', icon: 'i-lucide-user-round-plus' },
  { label: 'Aguardando contato', value: leads.value.filter(item => item.status === 'in_contact').length, tone: 'amber', icon: 'i-lucide-clock-3' },
  { label: 'Em qualificação', value: leads.value.filter(item => item.status === 'qualified').length, tone: 'violet', icon: 'i-lucide-filter' },
  { label: 'Convertidos', value: leads.value.filter(item => item.status === 'converted').length, tone: 'green', icon: 'i-lucide-chart-no-axes-combined' },
]));
const kanbanColumns = computed(() => [
  { status: 'new', label: 'Novo', className: 'border-blue-200 bg-blue-50/60' },
  { status: 'in_contact', label: 'Em contato', className: 'border-amber-200 bg-amber-50/60' },
  { status: 'qualified', label: 'Qualificado', className: 'border-violet-200 bg-violet-50/60' },
  { status: 'converted', label: 'Convertido', className: 'border-emerald-200 bg-emerald-50/60' },
].map(column => ({ ...column, items: leads.value.filter(item => item.status === column.status) })));
const selectedLead = computed(() =>
  leads.value.find(item => String(item.id) === String(route.query.leadId))
);
const load = () => store.dispatch('jrcCrm/leads/fetchLeads', filters);

const openDetails = lead =>
  router.replace({ query: { ...route.query, leadId: lead.id } });
const closeDetails = () => {
  const query = { ...route.query };
  delete query.leadId;
  router.replace({ query });
};
const replaceLead = updated => {
  const lead = leads.value.find(item => item.id === updated.id);
  if (lead) Object.assign(lead, updated);
};

const onLeadCreated = async lead => {
  showForm.value = false;
  filters.search = '';
  filters.status = '';
  await load();
  openDetails(lead);
};

const changeStatus = async (lead, status) => {
  changingId.value = lead.id;
  try {
    const { data } = await leadsAPI.update(lead.id, { lead: { status } });
    replaceLead(data);
    useAlert('Status atualizado com sucesso.');
  } catch (error) {
    useAlert(
      error.response?.data?.error || 'Não foi possível alterar o status.'
    );
  } finally {
    changingId.value = null;
  }
};

const deleteLead = async lead => {
  if (!window.confirm(`Excluir o lead ${lead.name}?\n\nO contato continuará cadastrado. Negócios vinculados não serão excluídos.`)) return;
  deletingId.value = lead.id;
  try {
    await store.dispatch('jrcCrm/leads/deleteLead', { leadId: lead.id, params: filters });
    if (String(route.query.leadId) === String(lead.id)) closeDetails();
    useAlert('Lead excluído com sucesso.');
  } catch (error) {
    useAlert(error.response?.data?.error || 'Não foi possível excluir o lead.');
  } finally {
    deletingId.value = null;
  }
};

const convertLead = async payload => {
  if (saving.value) return;
  saving.value = true;
  try {
    const { data } = await leadsAPI.convert(convertingLead.value.id, payload);
    replaceLead(data.lead);
    convertingLead.value = null;
    useAlert(data.message);
    router.push({
      name: 'crm_deals',
      params: { accountId: route.params.accountId },
      query: { dealId: data.deal.id },
    });
  } catch (error) {
    useAlert(
      error.response?.data?.error || 'Não foi possível converter o lead.'
    );
  } finally {
    saving.value = false;
  }
};

const openConversation = lead => {
  if (!lead.conversation) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: lead.conversation.display_id || lead.conversation.id,
    },
  });
};
const openDeal = lead =>
  router.push({
    name: 'crm_deals',
    params: { accountId: route.params.accountId },
    query: { dealId: lead.deal_id },
  });
const openContact = lead =>
  router.push({
    name: 'contacts_edit',
    params: { accountId: route.params.accountId, contactId: lead.contact_id },
  });

onMounted(async () => {
  showForm.value = route.query.new === '1';
  const [pipelineResponse, productResponse] = await Promise.all([
    pipelinesAPI.list(),
    productsAPI.list({ active: true }),
    load(),
  ]);
  products.value = productResponse.data;
  pipelines.value = await Promise.all(
    pipelineResponse.data.map(async pipeline => {
      const { data } = await stagesAPI.list({ pipeline_id: pipeline.id });
      return { ...pipeline, stages: data };
    })
  );
});
</script>

<template>
  <div class="flex h-full flex-col bg-n-surface-1 p-4 sm:p-6">
    <header class="mb-6 flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center gap-3">
        <span
          class="flex size-11 items-center justify-center rounded-2xl bg-n-iris-3 text-n-iris-11"
          ><i class="i-lucide-user-round-plus size-5"
        /></span>
        <div>
          <h2 class="text-2xl font-bold text-n-slate-12">Leads</h2>
          <p class="text-sm text-n-slate-11">
            Potenciais clientes em qualificação
          </p>
        </div>
      </div>
      <button
        type="button"
        class="rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white shadow-md transition hover:bg-n-brand/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-50"
        @click="showForm = true"
      >
        <i class="i-lucide-plus mr-2 inline size-4" />Novo lead
      </button>
    </header>
    <section class="mb-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <article v-for="item in leadSummary" :key="item.label" class="rounded-2xl border border-[#e4e9f1] bg-white p-4 shadow-sm">
        <div class="flex items-center justify-between"><span class="text-xs font-semibold text-[#667085]">{{ item.label }}</span><span class="grid size-10 place-content-center rounded-xl" :class="item.tone === 'blue' ? 'bg-blue-50 text-blue-600' : item.tone === 'amber' ? 'bg-amber-50 text-amber-600' : item.tone === 'violet' ? 'bg-violet-50 text-violet-600' : 'bg-emerald-50 text-emerald-600'"><i class="size-4" :class="item.icon" /></span></div>
        <strong class="mt-2 block text-2xl text-[#172033]">{{ item.value }}</strong>
      </article>
    </section>

    <div class="mb-3 flex justify-end"><div class="flex rounded-xl border border-[#e4e9f1] bg-white p-1 shadow-sm"><button type="button" class="rounded-lg px-3 py-2 text-xs font-semibold" :class="viewMode === 'list' ? 'bg-blue-700 text-white' : 'text-[#667085]'" @click="viewMode = 'list'"><i class="i-lucide-list mr-1 size-4" />Lista</button><button type="button" class="rounded-lg px-3 py-2 text-xs font-semibold" :class="viewMode === 'kanban' ? 'bg-[#7c3aed] text-white' : 'text-[#667085]'" @click="viewMode = 'kanban'"><i class="i-lucide-columns-3 mr-1 size-4" />Kanban</button></div></div>

    <form
      class="mb-4 flex flex-wrap gap-2 rounded-2xl border border-n-weak bg-n-solid-2 p-3 shadow-sm"
      @submit.prevent="load"
    >
      <input
        v-model="filters.search"
        type="search"
        placeholder="Buscar por nome ou e-mail"
        class="h-10 min-w-64 flex-1 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand focus:outline-none focus:ring-2 focus:ring-n-brand/20"
      /><select
        v-model="filters.status"
        class="h-10 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm font-medium text-n-slate-12"
        @change="load"
      >
        <option value="">Todos os status</option>
        <option value="new">Novo</option>
        <option value="in_contact">Em contato</option>
        <option value="qualified">Qualificado</option>
        <option value="converted">Convertido</option>
        <option value="discarded">Descartado</option></select
      ><button
        type="submit"
        class="h-10 rounded-xl border border-n-weak bg-n-solid-2 px-4 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-3"
      >
        Pesquisar
      </button>
    </form>
    <div v-if="viewMode === 'list'"
      class="flex-1 overflow-auto rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
    >
      <table class="min-w-full divide-y divide-n-weak text-sm">
        <thead
          class="bg-n-alpha-2 text-left text-xs font-semibold uppercase text-n-slate-11"
        >
          <tr>
            <th class="w-[34%] px-4 py-3">Nome / empresa</th>
            <th class="w-[15%] px-3 py-3">Status</th>
            <th class="w-[13%] px-3 py-3">Origem</th>
            <th class="w-[14%] px-3 py-3">Responsável</th>
            <th class="w-[18%] px-3 py-3 text-right">Próximo passo</th>
            <th class="w-[6%] px-3 py-3 text-right">Ações</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-if="!leads.length">
            <td colspan="6" class="px-5 py-14 text-center text-n-slate-11">
              Nenhum lead encontrado.
            </td>
          </tr>
          <tr
            v-for="lead in leads"
            :key="lead.id"
            class="cursor-pointer transition-colors hover:bg-n-alpha-2"
            @click="openDetails(lead)"
          >
            <td class="px-4 py-3">
              <p class="truncate font-semibold text-n-slate-12" :title="lead.name">{{ lead.name }}</p>
              <p class="text-xs text-n-slate-11">
                {{ lead.company_name || 'Empresa não informada' }}
              </p>
            </td>
            <td class="px-3 py-3">
              <select
                v-if="!['converted'].includes(lead.status)"
                :value="lead.status"
                :disabled="changingId === lead.id"
                class="rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-xs font-semibold text-n-slate-12 disabled:opacity-50"
                @click.stop
                @change="changeStatus(lead, $event.target.value)"
              >
                <option value="new">Novo</option>
                <option value="in_contact">Em contato</option>
                <option value="qualified">Qualificado</option>
                <option value="discarded">Descartado</option></select
              ><CrmStatusBadge v-else :value="lead.status" />
            </td>
            <td class="px-3 py-3 font-medium text-n-slate-11">
              {{ lead.source || '—' }}
            </td>
            <td class="px-3 py-3 text-n-slate-11">
              {{ lead.owner?.name || '—' }}
            </td>
            <td class="px-3 py-3 text-right">
              <button
                v-if="['new', 'in_contact'].includes(lead.status)"
                type="button"
                class="rounded-lg bg-n-iris-3 px-3 py-2 text-xs font-bold text-n-iris-11 hover:bg-n-iris-4"
                @click.stop="changeStatus(lead, 'qualified')"
              >
                Marcar como qualificado</button
              ><button
                v-else-if="lead.status === 'qualified'"
                type="button"
                class="rounded-lg bg-n-teal-10 px-3 py-2 text-xs font-bold text-white hover:bg-n-teal-11"
                @click.stop="convertingLead = lead"
              >
                Converter em negócio</button
              ><button
                v-else-if="lead.status === 'converted'"
                type="button"
                class="rounded-lg bg-n-blue-3 px-3 py-2 text-xs font-bold text-n-blue-11"
                @click.stop="openDeal(lead)"
              >
                Abrir negócio
              </button>
              <span v-else class="text-xs text-n-slate-10">
                Sem ação pendente
              </span>
            </td>
            <td class="px-3 py-3 text-right">
              <button
                type="button"
                :disabled="deletingId === lead.id"
                class="inline-flex size-9 items-center justify-center rounded-lg border border-n-weak text-n-ruby-11 transition hover:bg-n-ruby-3 disabled:opacity-50"
                title="Excluir lead"
                @click.stop="deleteLead(lead)"
              >
                <i class="i-lucide-trash-2 size-4" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-else class="grid flex-1 gap-4 overflow-auto xl:grid-cols-4">
      <section v-for="column in kanbanColumns" :key="column.status" class="min-h-[420px] rounded-2xl border p-3" :class="column.className">
        <div class="mb-3 flex items-center justify-between"><strong class="text-sm text-[#344054]">{{ column.label }}</strong><span class="rounded-full bg-white px-2 py-0.5 text-xs font-bold text-[#667085]">{{ column.items.length }}</span></div>
        <div class="space-y-3"><button v-for="lead in column.items" :key="lead.id" type="button" class="w-full rounded-xl border border-white/80 bg-white p-3 text-left shadow-sm transition hover:-translate-y-0.5" @click="openDetails(lead)"><strong class="block truncate text-sm text-[#172033]">{{ lead.name }}</strong><span class="mt-1 block truncate text-xs text-[#667085]">{{ lead.company_name || lead.email || lead.phone || 'Sem empresa' }}</span><div class="mt-3 flex items-center justify-between"><span class="text-[11px] text-[#98a2b3]">{{ lead.source || 'Origem não informada' }}</span><i class="i-lucide-chevron-right size-4 text-[#98a2b3]" /></div></button></div>
      </section>
    </div>
    <LeadCreateModal v-if="showForm" @close="showForm = false" @created="onLeadCreated" />
    <Teleport to="body">
      <LeadDetailModal
        v-if="selectedLead"
        :lead="selectedLead"
        :saving="changingId === selectedLead.id"
        @close="closeDetails"
        @status-change="changeStatus"
        @convert="convertingLead = $event"
        @conversation="openConversation"
        @contact="openContact"
        @deal="openDeal" /><LeadConversionModal
        v-if="convertingLead"
        :lead="convertingLead"
        :pipelines="pipelines"
        :products="products"
        :saving="saving"
        @close="convertingLead = null"
        @submit="convertLead"
    /></Teleport>
  </div>
</template>
