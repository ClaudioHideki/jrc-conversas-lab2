<script setup>
import { useCustomerSegmentFilter } from '../../helpers/useCustomerSegmentFilter';
import { useQuickActionTarget } from 'dashboard/components-next/layout/useQuickActionTarget';
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import {
  computed,
  onMounted,
  onBeforeUnmount,
  reactive,
  ref,
  watch,
} from 'vue';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import {
  leadsAPI,
  pipelinesAPI,
  productsAPI,
  stagesAPI,
} from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import CrmListingHeader from '../../components/shared/CrmListingHeader.vue';
import CrmBadge from '../../components/shared/CrmBadge.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import LeadNextAction from './LeadNextAction.vue';
import LeadConversionModal from './LeadConversionModal.vue';
import LeadDetailModal from './LeadDetailModal.vue';
import LeadCreateModal from './LeadCreateModal.vue';

const store = useStore();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
let disposed = false;
let generation = 0;
const identity = computed(
  () => `${route.params.accountId}:${authorityScope(store.getters)}`
);
const captureContext = () => ({ identity: identity.value, generation });
const isCurrent = context =>
  !disposed &&
  context.identity === identity.value &&
  context.generation === generation;
onBeforeUnmount(() => {
  disposed = true;
  generation += 1;
});
const metadataError = ref('');
const listError = computed(() => store.getters['jrcCrm/leads/error']);
const loading = computed(() => store.getters['jrcCrm/leads/isLoading']);
const showForm = ref(false);
useQuickActionTarget('crm_leads', () => {
  showForm.value = true;
});
const viewMode = ref('list');
const saving = ref(false);
const changingId = ref(null);
const deletingId = ref(null);
const convertingLead = ref(null);
const conversionError = ref('');
watch(convertingLead, () => {
  conversionError.value = '';
});
const pipelines = ref([]);
const products = ref([]);
const filters = reactive({ search: '', status: '' });
const leads = computed(() => store.getters['jrcCrm/leads/allLeads'] || []);
const columnStyles = [
  [
    'new',
    t('CRM.LIST_LAYOUT.NEW_LEADS'),
    'i-lucide-user-round-plus',
    'border-n-blue-6 bg-n-blue-3 text-n-blue-11',
    'bg-n-blue-2',
    'border-s-n-blue-9',
  ],
  [
    'in_contact',
    t('CRM.LIST_LAYOUT.CONTACTING'),
    'i-lucide-clock-3',
    'border-n-amber-6 bg-n-amber-3 text-n-amber-11',
    'bg-n-amber-2',
    'border-s-n-amber-9',
  ],
  [
    'qualified',
    t('CRM.LIST_LAYOUT.QUALIFYING'),
    'i-lucide-filter',
    'border-n-iris-6 bg-n-iris-3 text-n-iris-11',
    'bg-n-iris-2',
    'border-s-n-iris-9',
  ],
  [
    'converted',
    t('CRM.LIST_LAYOUT.CONVERTED'),
    'i-lucide-chart-no-axes-combined',
    'border-n-teal-6 bg-n-teal-3 text-n-teal-11',
    'bg-n-teal-2',
    'border-s-n-teal-9',
  ],
  [
    'discarded',
    t('CRM.LIST_LAYOUT.DISCARDED'),
    'i-lucide-archive',
    'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11',
    'bg-n-ruby-2',
    'border-s-n-ruby-9',
  ],
].map(([status, label, icon, tone, panel, accent]) => ({
  status,
  label,
  icon,
  tone,
  panel,
  accent,
}));
const ownerFilter = ref('');
const sourceFilter = ref('');
const moreFilters = ref(false);
const listPage = ref(1);
const perPage = ref(13);
const columnLimits = ref({});
const owners = computed(() =>
  [
    ...new Map(
      leads.value
        .filter(lead => lead.owner)
        .map(lead => [lead.owner.id, lead.owner])
    ).values(),
  ].sort((a, b) => a.name.localeCompare(b.name))
);
const sources = computed(() =>
  [...new Set(leads.value.map(lead => lead.source).filter(Boolean))].sort()
);
const visibleLeads = computed(() =>
  leads.value.filter(lead => {
    const owner = lead.owner ? String(lead.owner.id) : 'unassigned';
    return (
      (!ownerFilter.value || owner === ownerFilter.value) &&
      (!sourceFilter.value || lead.source === sourceFilter.value)
    );
  })
);
const pagedLeads = computed(() =>
  visibleLeads.value.slice(
    (listPage.value - 1) * perPage.value,
    listPage.value * perPage.value
  )
);
const leadSummary = computed(() =>
  columnStyles.slice(0, 4).map(column => ({
    ...column,
    value: leads.value.filter(lead => lead.status === column.status).length,
  }))
);
const kanbanColumns = computed(() =>
  columnStyles
    .map(column => ({
      ...column,
      items: visibleLeads.value.filter(lead => lead.status === column.status),
      limit: columnLimits.value[column.status] || 4,
    }))
    .filter(column => column.status !== 'discarded' || column.items.length)
);
const resetListingPage = () => {
  listPage.value = 1;
  columnLimits.value = {};
};
watch([ownerFilter, sourceFilter, perPage], resetListingPage);
watch(
  () => visibleLeads.value.length,
  total => {
    listPage.value = Math.min(
      listPage.value,
      Math.max(1, Math.ceil(total / perPage.value))
    );
  }
);
const selectedLead = computed(() =>
  leads.value.find(item => String(item.id) === String(route.query.leadId))
);
const { segmentParams, watchSegment } = useCustomerSegmentFilter();
const load = () => {
  resetListingPage();
  return store.dispatch('jrcCrm/leads/fetchLeads', segmentParams(filters));
};
watchSegment(load);

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

const onLeadCreated = async (lead, { keepOpen = false } = {}) => {
  const context = captureContext();
  showForm.value = keepOpen;
  filters.search = '';
  filters.status = '';
  await load();
  if (isCurrent(context) && !keepOpen) openDetails(lead);
};

const changeStatus = async (lead, status) => {
  const context = captureContext();
  changingId.value = lead.id;
  try {
    const { data } = await leadsAPI.update(lead.id, { lead: { status } });
    if (!isCurrent(context)) return;
    replaceLead(data);
    useAlert('Status atualizado com sucesso.');
  } catch (error) {
    if (!isCurrent(context)) return;
    useAlert(
      error.response?.data?.error || 'Não foi possível alterar o status.'
    );
  } finally {
    if (isCurrent(context)) changingId.value = null;
  }
};

const deleteLead = async lead => {
  if (deletingId.value !== null) return;
  const context = captureContext();
  if (
    !window.confirm(
      `Excluir o lead ${lead.name}?\n\nO contato continuará cadastrado. Negócios vinculados não serão excluídos.`
    )
  )
    return;
  deletingId.value = lead.id;
  try {
    await store.dispatch('jrcCrm/leads/deleteLead', {
      leadId: lead.id,
      params: segmentParams(filters),
    });
    if (!isCurrent(context)) return;
    if (String(route.query.leadId) === String(lead.id)) closeDetails();
    useAlert('Lead excluído com sucesso.');
  } catch (error) {
    if (!isCurrent(context)) return;
    useAlert(error.response?.data?.error || 'Não foi possível excluir o lead.');
  } finally {
    if (isCurrent(context)) deletingId.value = null;
  }
};

const convertLead = async payload => {
  if (saving.value || !convertingLead.value) return;
  const context = captureContext();
  saving.value = true;
  conversionError.value = '';
  try {
    const { data } = await leadsAPI.convert(convertingLead.value.id, payload);
    if (!isCurrent(context)) return;
    replaceLead(data.lead);
    convertingLead.value = null;
    useAlert(data.message);
    router.push({
      name: 'crm_deals',
      params: { accountId: route.params.accountId },
      query: { dealId: data.deal.id },
    });
  } catch (error) {
    if (!isCurrent(context)) return;
    conversionError.value =
      error.response?.data?.error || t('CRM.SALES_FLOW.CONVERT_ERROR');
  } finally {
    if (isCurrent(context)) saving.value = false;
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

const initialize = async () => {
  const context = captureContext();
  metadataError.value = '';
  try {
    const [pipelineResponse, productResponse] = await Promise.all([
      pipelinesAPI.list(),
      productsAPI.list({ active: true }),
      load(),
    ]);
    if (!isCurrent(context)) return;
    const loadedPipelines = await Promise.all(
      pipelineResponse.data.map(async pipeline => {
        const { data } = await stagesAPI.list({ pipeline_id: pipeline.id });
        return { ...pipeline, stages: data };
      })
    );
    if (!isCurrent(context)) return;
    products.value = productResponse.data;
    pipelines.value = loadedPipelines;
  } catch {
    if (isCurrent(context)) metadataError.value = t('CRM.LEAD_LIST.LOAD_ERROR');
  }
};
watch(identity, () => {
  generation += 1;
  showForm.value = false;
  convertingLead.value = null;
  pipelines.value = [];
  products.value = [];
  saving.value = false;
  changingId.value = null;
  deletingId.value = null;
  ownerFilter.value = '';
  sourceFilter.value = '';
  initialize();
});
onMounted(() => {
  showForm.value = route.query.new === '1';
  initialize();
});
</script>

<template>
  <div
    class="flex min-h-full min-w-0 flex-col gap-3 bg-gradient-to-b from-n-blue-2 to-n-surface-1 p-3 sm:px-6"
  >
    <CrmListingHeader :title="t('CRM.NAV.LEADS')">
      <button
        type="button"
        class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white shadow-sm"
        @click="showForm = true"
      >
        <span class="i-lucide-plus size-4" aria-hidden="true" />
        {{ t('CRM.LIST_LAYOUT.NEW_LEAD') }}
      </button>
    </CrmListingHeader>
    <section class="grid grid-cols-2 gap-2 lg:grid-cols-4">
      <article
        v-for="item in leadSummary"
        :key="item.status"
        class="flex min-w-0 items-center justify-between gap-2 rounded-lg border px-3 py-2"
        :class="item.tone"
      >
        <div class="flex min-w-0 items-center gap-2 text-xs font-semibold">
          <span :class="item.icon" class="size-4 shrink-0" aria-hidden="true" />
          {{ item.label }}
        </div>
        <strong class="text-lg leading-none tabular-nums">{{
          item.value
        }}</strong>
      </article>
    </section>
    <form
      class="flex flex-wrap items-center gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-2 shadow-sm"
      @submit.prevent="load"
    >
      <label class="relative min-w-[min(100%,14rem)] flex-1">
        <span
          class="i-lucide-search pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-11"
          aria-hidden="true"
        />
        <input
          v-model="filters.search"
          type="search"
          :placeholder="t('CRM.LIST_LAYOUT.LEADS_SEARCH')"
          :aria-label="t('CRM.LIST_LAYOUT.LEADS_SEARCH')"
          class="reset-base m-0 h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 pe-3 ps-9 text-sm"
        />
      </label>
      <select
        v-model="filters.status"
        :aria-label="t('CRM.LIST_LAYOUT.STATUS')"
        class="!mb-0 h-9 w-auto min-w-32 !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
        @change="load"
      >
        <option value="">{{ t('CRM.LIST_LAYOUT.STATUS') }}</option>
        <option value="new">Novo</option>
        <option value="in_contact">Em contato</option>
        <option value="qualified">Qualificado</option>
        <option value="converted">Convertido</option>
        <option value="discarded">Descartado</option>
      </select>
      <select
        v-model="ownerFilter"
        :aria-label="t('CRM.LIST_LAYOUT.OWNER')"
        class="!mb-0 h-9 w-auto min-w-36 max-w-full !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
      >
        <option value="">{{ t('CRM.LIST_LAYOUT.OWNER') }}</option>
        <option value="unassigned">
          {{ t('CRM.LIST_LAYOUT.UNASSIGNED') }}
        </option>
        <option
          v-for="owner in owners"
          :key="owner.id"
          :value="String(owner.id)"
        >
          {{ owner.name }}
        </option>
      </select>
      <button
        type="button"
        :aria-expanded="moreFilters"
        class="inline-flex h-9 items-center gap-2 rounded-lg border border-n-weak px-3 text-xs font-semibold text-n-blue-11"
        @click="moreFilters = !moreFilters"
      >
        <span class="i-lucide-list-filter size-4" aria-hidden="true" />
        {{ t('CRM.DIRECTORY.MORE_FILTERS') }}
      </button>
      <button
        type="submit"
        class="h-9 rounded-lg border border-n-weak px-3 text-xs font-semibold text-n-blue-11"
      >
        {{ t('CRM.LIST_LAYOUT.SEARCH') }}
      </button>
      <div
        class="flex gap-1 rounded-lg border border-n-weak bg-n-solid-2 p-0.5"
      >
        <button
          v-for="mode in ['list', 'kanban']"
          :key="mode"
          type="button"
          :aria-pressed="viewMode === mode"
          class="inline-flex h-8 items-center gap-1.5 rounded-md px-2.5 text-xs font-semibold"
          :class="
            viewMode === mode ? 'bg-n-brand text-white' : 'text-n-slate-11'
          "
          @click="viewMode = mode"
        >
          <span
            :class="mode === 'list' ? 'i-lucide-list' : 'i-lucide-columns-3'"
            class="size-4"
            aria-hidden="true"
          />
          {{
            mode === 'list'
              ? t('CRM.LIST_LAYOUT.LIST')
              : t('CRM.LIST_LAYOUT.KANBAN')
          }}
        </button>
      </div>
      <div v-if="moreFilters" class="w-full border-t border-n-weak pt-2">
        <select
          v-model="sourceFilter"
          :aria-label="t('CRM.LIST_LAYOUT.SOURCE')"
          class="!mb-0 h-9 w-auto min-w-36 !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
        >
          <option value="">{{ t('CRM.LIST_LAYOUT.SOURCE') }}</option>
          <option v-for="source in sources" :key="source" :value="source">
            {{ source }}
          </option>
        </select>
      </div>
    </form>
    <div
      v-if="listError || metadataError"
      role="alert"
      class="mb-3 rounded-xl border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
    >
      {{ metadataError || t('CRM.LEAD_LIST.LOAD_ERROR') }}
      <button type="button" class="ml-2 underline" @click="initialize">
        {{ t('CRM.LEAD_LIST.RETRY') }}
      </button>
    </div>
    <section
      v-if="viewMode === 'list'"
      class="min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-sm"
    >
      <div class="relative overflow-x-auto">
        <table
          class="w-full min-w-[820px] divide-y divide-n-weak text-sm"
          :aria-label="t('CRM.LIST_LAYOUT.LEADS_LIST')"
        >
          <thead
            class="bg-n-slate-3 text-left text-[11px] font-semibold uppercase tracking-wide text-n-slate-11"
          >
            <tr>
              <th class="w-[34%] px-4 py-2">
                {{ t('CRM.LIST_LAYOUT.LEAD_NAME') }}
              </th>
              <th class="w-[15%] px-3 py-2">
                {{ t('CRM.LIST_LAYOUT.STATUS') }}
              </th>
              <th class="w-[13%] px-3 py-2">
                {{ t('CRM.LIST_LAYOUT.SOURCE') }}
              </th>
              <th class="w-[14%] px-3 py-2">
                {{ t('CRM.LIST_LAYOUT.OWNER') }}
              </th>
              <th class="w-[18%] px-3 py-2">
                {{ t('CRM.LIST_LAYOUT.NEXT_STEP') }}
              </th>
              <th class="w-[6%] px-3 py-2 text-right">
                {{ t('CRM.CONTACT_LEAD.UI.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr v-if="loading">
              <td colspan="6" class="px-5 py-14 text-center text-n-slate-11">
                {{ t('CRM.LEAD_LIST.LOADING') }}
              </td>
            </tr>
            <tr v-else-if="!listError && !pagedLeads.length">
              <td colspan="6" class="px-5 py-14 text-center text-n-slate-11">
                {{ t('CRM.LIST_LAYOUT.NO_MATCHING_LEADS') }}
              </td>
            </tr>
            <tr
              v-for="lead in pagedLeads"
              :key="lead.id"
              class="cursor-pointer transition-colors hover:bg-n-blue-2"
              @click="openDetails(lead)"
            >
              <td class="px-4 py-1.5">
                <p
                  class="m-0 truncate font-semibold leading-tight text-n-slate-12"
                  :title="lead.name"
                >
                  {{ lead.name }}
                </p>
                <p v-if="lead.company_name" class="m-0 text-xs text-n-slate-11">
                  {{ lead.company_name }}
                </p>
              </td>
              <td class="px-3 py-1.5">
                <div
                  class="relative inline-flex whitespace-nowrap rounded-full focus-within:ring-2 focus-within:ring-n-brand"
                >
                  <CrmStatusBadge :value="lead.status" />
                  <select
                    v-if="lead.status !== 'converted'"
                    :aria-label="t('CRM.LIST_LAYOUT.STATUS')"
                    :value="lead.status"
                    :disabled="changingId === lead.id"
                    class="absolute inset-0 !m-0 h-full w-full cursor-pointer opacity-0"
                    @click.stop
                    @change="changeStatus(lead, $event.target.value)"
                  >
                    <option value="new">Novo</option>
                    <option value="in_contact">Em contato</option>
                    <option value="qualified">Qualificado</option>
                    <option value="discarded">Descartado</option>
                  </select>
                </div>
              </td>
              <td class="px-3 py-1.5 font-medium text-n-slate-11">
                {{ lead.source || '—' }}
              </td>
              <td class="px-3 py-1.5 text-n-slate-11">
                <div
                  v-if="lead.owner?.name"
                  class="flex items-center gap-2 whitespace-nowrap"
                >
                  <Avatar :name="lead.owner.name" :size="24" rounded-full />
                  {{ lead.owner.name }}
                </div>
                <span v-else>{{ t('CRM.LIST_LAYOUT.UNASSIGNED') }}</span>
              </td>
              <td class="px-3 py-1.5">
                <LeadNextAction
                  :status="lead.status"
                  :can-open-deal="Boolean(lead.deal_id)"
                  :disabled="changingId === lead.id"
                  @qualify="changeStatus(lead, 'qualified')"
                  @convert="convertingLead = lead"
                  @deal="openDeal(lead)"
                />
              </td>
              <td class="px-3 py-1.5 text-right">
                <div class="flex justify-end gap-1 whitespace-nowrap">
                  <button
                    type="button"
                    class="inline-flex h-7 items-center gap-1 rounded-md border border-n-blue-6 bg-n-blue-2 px-2 text-xs font-semibold text-n-blue-11"
                    @click.stop="openDetails(lead)"
                  >
                    <span
                      class="i-lucide-external-link size-3.5"
                      aria-hidden="true"
                    />
                    {{ t('CRM.LIST_LAYOUT.OPEN') }}
                  </button>
                  <button
                    type="button"
                    :disabled="deletingId !== null"
                    class="inline-flex size-7 items-center justify-center rounded-md border border-n-weak !p-0 text-n-ruby-11 transition hover:bg-n-ruby-3 disabled:opacity-50"
                    title="Excluir lead"
                    aria-label="Excluir lead"
                    @click.stop="deleteLead(lead)"
                  >
                    <i class="i-lucide-trash-2 size-4" aria-hidden="true" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div
        v-if="visibleLeads.length"
        class="flex flex-wrap items-center gap-1 border-t border-n-weak sm:flex-nowrap"
      >
        <PaginationFooter
          class="!border-t-0"
          :current-page="listPage"
          :items-per-page="perPage"
          :total-items="visibleLeads.length"
          current-page-info="CRM.LIST_LAYOUT.SHOWING_LEADS"
          numbered
          @update:current-page="listPage = $event"
        />
        <select
          v-model.number="perPage"
          :aria-label="t('CRM.LIST_LAYOUT.ROWS_PER_PAGE')"
          class="!mb-2 ms-3 h-8 w-auto !appearance-auto rounded-md border border-n-weak bg-n-solid-1 !bg-none text-xs sm:!mb-0 sm:me-3 sm:ms-0"
        >
          <option v-for="size in [13, 25, 50]" :key="size" :value="size">
            {{ t('CRM.LIST_LAYOUT.LEADS_PER_PAGE', { count: size }) }}
          </option>
        </select>
      </div>
    </section>
    <section
      v-else
      :aria-label="t('CRM.LIST_LAYOUT.LEADS_BOARD')"
      class="grid min-w-0 gap-2 sm:grid-cols-2 xl:grid-cols-[repeat(auto-fit,minmax(12rem,1fr))]"
    >
      <section
        v-for="column in kanbanColumns"
        :key="column.status"
        class="min-w-0 rounded-xl p-2"
        :class="column.panel"
      >
        <header
          class="mb-2 flex items-center justify-between gap-2 rounded-lg border px-2.5 py-2"
          :class="column.tone"
        >
          <h3 class="flex items-center gap-2 text-sm font-semibold">
            <span
              :class="column.icon"
              class="size-4 shrink-0"
              aria-hidden="true"
            />
            {{ column.label }}
          </h3>
          <strong class="text-lg leading-none tabular-nums">{{
            column.items.length
          }}</strong>
        </header>
        <div class="grid gap-2">
          <article
            v-for="lead in column.items.slice(0, column.limit)"
            :key="lead.id"
            class="rounded-lg border border-n-weak border-s-[3px] bg-n-solid-2 shadow-sm"
            :class="column.accent"
          >
            <div class="px-2.5 py-1.5">
              <button
                type="button"
                class="block w-full truncate !p-0 text-left text-sm font-semibold !leading-tight text-n-slate-12 hover:text-n-brand"
                :title="lead.name"
                @click="openDetails(lead)"
              >
                {{ lead.name }}
              </button>
              <p
                v-if="lead.company_name"
                class="m-0 truncate text-xs text-n-slate-11"
              >
                {{ lead.company_name }}
              </p>
              <CrmBadge
                v-if="lead.source"
                color="blue"
                class="mt-1 !px-2 !py-0.5"
                >{{ lead.source }}</CrmBadge
              >
              <div
                class="mt-1 flex min-w-0 items-center justify-between gap-2 text-xs text-n-slate-11"
              >
                <div
                  v-if="lead.owner?.name"
                  class="flex min-w-0 items-center gap-1.5"
                >
                  <Avatar :name="lead.owner.name" :size="24" rounded-full />
                  <span class="truncate">{{ lead.owner.name }}</span>
                </div>
                <span v-else>{{ t('CRM.LIST_LAYOUT.UNASSIGNED') }}</span>
                <button
                  v-if="lead.conversation"
                  type="button"
                  class="grid size-6 shrink-0 place-items-center rounded-md text-n-blue-11 hover:bg-n-blue-3"
                  :aria-label="t('CRM.DIRECTORY.CONVERSE')"
                  @click="openConversation(lead)"
                >
                  <span
                    class="i-lucide-message-circle size-4"
                    aria-hidden="true"
                  />
                </button>
              </div>
            </div>
            <div
              class="flex items-center gap-1.5 border-t border-n-weak px-2.5 py-1"
            >
              <span
                class="i-lucide-calendar-check size-3.5 shrink-0 text-n-slate-11"
                aria-hidden="true"
              />
              <LeadNextAction
                :status="lead.status"
                :can-open-deal="Boolean(lead.deal_id)"
                :disabled="changingId === lead.id"
                @qualify="changeStatus(lead, 'qualified')"
                @convert="convertingLead = lead"
                @deal="openDeal(lead)"
              />
            </div>
          </article>
          <button
            v-if="column.items.length > column.limit"
            type="button"
            class="flex items-center justify-center gap-1 rounded-lg border px-2 py-1.5 text-xs font-semibold"
            :class="column.tone"
            @click="columnLimits[column.status] = column.limit + 4"
          >
            <span class="i-lucide-chevron-down size-4" aria-hidden="true" />
            {{
              t('CRM.LIST_LAYOUT.MORE_LEADS', {
                count: column.items.length - column.limit,
              })
            }}
          </button>
        </div>
      </section>
    </section>
    <LeadCreateModal
      v-if="showForm"
      @close="showForm = false"
      @created="onLeadCreated"
    />
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
        @deal="openDeal"
      /><LeadConversionModal
        v-if="convertingLead"
        :lead="convertingLead"
        :pipelines="pipelines"
        :products="products"
        :saving="saving"
        :error="conversionError"
        @close="convertingLead = null"
        @submit="convertLead"
      />
    </Teleport>
  </div>
</template>
