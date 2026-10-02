<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import API from 'dashboard/api/jrcCustomers';
import CompanyEditor from './components/CompanyEditor.vue';
import CompanyAddresses from './components/CompanyAddresses.vue';
import CompanyContacts from './components/CompanyContacts.vue';
import TimelinePanel from './components/TimelinePanel.vue';
import RecordsPanel from './components/RecordsPanel.vue';
import { useCustomerMaster } from './useCustomerMaster';
import {
  T,
  FIELD_LABELS,
  RELATIONSHIPS,
  buttonClass,
  errorMessage,
} from './copy';
const route = useRoute();
const { accountId, accountScopedRoute, date } = useCustomerMaster();
const companyId = computed(() => route.params.companyId);
const company = ref(null);
const addresses = ref([]);
const branches = ref([]);
const branchesTotal = ref(0);
const overview = ref(null);
const tab = ref('overview');
const editing = ref(false);
const error = ref('');
const busy = ref(false);
let generation = 0;
const tabs = computed(() => {
  const base = [
    'overview',
    'general',
    'addresses',
    'contacts',
    'timeline',
    'conversations',
  ];
  if (overview.value?.capabilities?.crm)
    base.push('leads', 'deals', 'proposals', 'activities');
  if (overview.value?.capabilities?.service_desk) base.push('tickets');
  if (overview.value?.capabilities?.projects)
    base.push('projects', 'project_tasks');
  if (overview.value?.capabilities?.contracts)
    base.push('contracts', 'orders', 'follow_ups');
  if (overview.value?.capabilities?.calls) base.push('calls');
  if (overview.value?.capabilities?.campaigns) base.push('campaigns');
  return base;
});
const cards = computed(() => {
  if (!overview.value) return [];
  const result = [
    [T.count, overview.value.contacts],
    [T.openConversations, overview.value.conversations_open],
  ];
  if (overview.value.capabilities.crm)
    result.push(
      [T.opportunities, overview.value.opportunities],
      [T.pendingActivities, overview.value.pending_activities]
    );
  if (overview.value.capabilities.service_desk)
    result.push([T.openTickets, overview.value.tickets_open]);
  if (overview.value.capabilities.projects)
    result.push([T.activeProjects, overview.value.projects_active]);
  if (overview.value.capabilities.contracts)
    result.push([T.activeContracts, overview.value.contracts_active]);
  return result;
});
const load = async () => {
  generation += 1;
  const version = generation;
  busy.value = true;
  error.value = '';
  try {
    const [record, summary] = await Promise.all([
      API.company(companyId.value),
      API.overview(companyId.value),
    ]);
    if (version === generation) {
      company.value = record.data.payload;
      addresses.value = record.data.addresses;
      branches.value = record.data.branches;
      branchesTotal.value = record.data.branches_total;
      overview.value = summary.data;
    }
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const saved = () => {
  editing.value = false;
  load();
};
watch(
  [accountId, companyId],
  () => {
    company.value = null;
    overview.value = null;
    tab.value = 'overview';
    editing.value = false;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <main
    class="h-full w-full overflow-auto bg-n-solid-1 p-5 text-n-slate-12 md:p-8"
  >
    <RouterLink
      :to="accountScopedRoute('jrc_customer_companies')"
      class="text-sm text-n-brand"
      >{{ T.customers }} / {{ T.companies }}</RouterLink
    >
    <p
      v-if="error"
      class="my-4 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      class="my-4"
      role="status"
    >
      {{ T.loading }}
    </p>
    <template v-if="company"
      ><header
        class="my-5 flex flex-wrap items-start justify-between gap-4 rounded-2xl border border-n-weak bg-n-solid-2 p-6"
      >
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-n-brand">
            {{ T.master }} / #{{ company.id }}
          </p>
          <h1 class="mt-2 text-2xl font-bold">{{ company.name }}</h1>
          <p class="mt-2 text-sm text-n-slate-10">
            {{ company.tax_id }} / {{ company.segment }} /
            {{ company.owner_name }} / {{ company.city }}
          </p>
          <p class="mt-2 text-sm font-medium">
            {{ RELATIONSHIPS[company.relationship_type] }} /
            {{ company.active ? T.active : T.inactive }}
          </p>
        </div>
        <button
          type="button"
          :class="buttonClass"
          @click="editing = !editing"
        >
          {{ editing ? T.close : T.editCompany }}
        </button>
      </header>
      <CompanyEditor
        v-if="editing"
        :company="company"
        class="mb-6"
        @saved="saved"
        @cancel="editing = false"
      />
      <RouterLink
        v-if="overview?.capabilities?.crm || overview?.capabilities?.projects"
        class="mb-4 inline-block text-sm text-n-brand underline"
        :to="
          accountScopedRoute(
            'jrc_operations_agenda',
            {},
            { company_id: company.id }
          )
        "
        >{{ T.agenda }} / {{ company.name }}</RouterLink
      >
      <nav
        class="mb-5 flex gap-2 overflow-x-auto border-b border-n-weak pb-3"
        :aria-label="T.overview"
      >
        <button
          v-for="key in tabs"
          :key="key"
          type="button"
          class="whitespace-nowrap rounded-lg px-3 py-2 text-sm"
          :class="
            tab === key
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          :aria-current="tab === key ? 'page' : undefined"
          @click="tab = key"
        >
          {{ T[key] }}
        </button>
      </nav>
      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <template v-if="tab === 'overview'"
          ><div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <article
              v-for="card in cards"
              :key="card[0]"
              class="rounded-xl border border-n-weak p-4"
            >
              <p class="text-sm text-n-slate-10">{{ card[0] }}</p>
              <strong class="mt-2 block text-3xl">{{ card[1] }}</strong>
            </article>
          </div>
          <p class="mt-5 text-sm">
            {{ T.lastInteraction }}: {{ date(overview?.last_interaction_at) }}
          </p>
          <p class="mt-3 text-sm text-n-slate-10">{{ T.permissionsHelp }}</p>
          <TimelinePanel
            class="mt-6"
            :resource-id="company.id"
        /></template>
        <template v-else-if="tab === 'general'"
          ><dl class="grid gap-5 md:grid-cols-3">
            <div
              v-for="(label, key) in FIELD_LABELS"
              :key="key"
            >
              <template
                v-if="Object.prototype.hasOwnProperty.call(company, key)"
                ><dt class="text-xs text-n-slate-10">{{ label }}</dt>
                <dd class="mt-1 break-words text-sm">
                  {{ company[key] || '\u2014' }}
                </dd></template
              >
            </div>
          </dl>
          <div
            v-if="company.parent_company_id"
            class="mt-5"
          >
            <span>{{ T.parent }}: </span
            ><RouterLink
              :to="
                accountScopedRoute('jrc_customer_company', {
                  companyId: company.parent_company_id,
                })
              "
              class="text-n-brand"
              >#{{ company.parent_company_id }}</RouterLink
            >
          </div>
          <div
            v-if="branches.length"
            class="mt-5"
          >
            <h3 class="font-semibold">{{ T.branches }}</h3>
            <RouterLink
              v-for="branch in branches"
              :key="branch.id"
              :to="
                accountScopedRoute('jrc_customer_company', {
                  companyId: branch.id,
                })
              "
              class="mt-2 block text-n-brand"
              >{{ branch.name }}</RouterLink
            ><RouterLink
              v-if="branchesTotal > branches.length"
              :to="
                accountScopedRoute(
                  'jrc_customer_companies',
                  {},
                  { parent_company_id: company.id }
                )
              "
              class="mt-3 block text-n-brand"
              >{{ T.branches }}: {{ branchesTotal }} / {{ T.more }}</RouterLink
            >
          </div></template
        >
        <CompanyAddresses
          v-else-if="tab === 'addresses'"
          :company-id="company.id"
          :addresses="addresses"
          @changed="load"
        />
        <CompanyContacts
          v-else-if="tab === 'contacts'"
          :company-id="company.id"
          @changed="load"
        />
        <TimelinePanel
          v-else-if="tab === 'timeline'"
          :resource-id="company.id"
        />
        <RecordsPanel
          v-else
          :key="`${accountId}:${company.id}:${tab}`"
          :company-id="company.id"
          :kind="tab"
        />
      </section>
    </template>
  </main>
</template>
