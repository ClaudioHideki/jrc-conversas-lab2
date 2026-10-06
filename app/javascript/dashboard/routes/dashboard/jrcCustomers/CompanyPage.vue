<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import API from 'dashboard/api/jrcCustomers';
import RelationshipPanel from '../jrcRelationship/Customer360Relationship.vue';
import { useI18n } from 'vue-i18n';
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
  SIZE_OPTIONS,
  SOURCE_OPTIONS,
  buttonClass,
  errorMessage,
} from './copy';

const route = useRoute();
const { t } = useI18n();
const { accountId, accountScopedRoute, date } = useCustomerMaster();
const companyId = computed(() => route.params.companyId);
const company = ref(null);
const addresses = ref([]);
const branches = ref([]);
const branchesTotal = ref(0);
const overview = ref(null);
const section = ref('overview');
const tab = ref('overview');
const editing = ref(false);
const error = ref('');
const busy = ref(false);
let generation = 0;

const availableTabs = computed(() => {
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
  if (overview.value?.capabilities?.relationship) base.push('relationship');
  return base;
});

const navigationGroups = computed(() => {
  const definitions = [
    ['overview', ['overview']],
    ['registration', ['general', 'addresses', 'contacts']],
    [
      'relationshipArea',
      ['relationship', 'timeline', 'conversations', 'calls', 'campaigns'],
    ],
    ['commercial', ['leads', 'deals', 'proposals', 'orders', 'contracts']],
    ['operation', ['activities', 'projects', 'project_tasks']],
    ['service', ['tickets', 'follow_ups']],
  ];
  return definitions
    .map(([key, items]) => ({
      key,
      tabs: items.filter(item => availableTabs.value.includes(item)),
    }))
    .filter(group => group.tabs.length);
});

const activeGroup = computed(
  () =>
    navigationGroups.value.find(group => group.key === section.value) ||
    navigationGroups.value[0]
);

const money = cents =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(cents || 0) / 100);

const cards = computed(() => {
  if (!overview.value) return [];
  const result = [
    { label: T.count, value: overview.value.contacts },
    { label: T.openConversations, value: overview.value.conversations_open },
  ];
  if (overview.value.capabilities.crm) {
    result.push(
      { label: T.opportunities, value: overview.value.opportunities },
      {
        label: T.openOpportunityValue,
        value: money(overview.value.opportunities_value_cents),
      },
      { label: T.pendingActivities, value: overview.value.pending_activities }
    );
  }
  if (overview.value.capabilities.service_desk)
    result.push(
      { label: T.openTickets, value: overview.value.tickets_open },
      { label: T.slaBreached, value: overview.value.sla_breached }
    );
  if (overview.value.capabilities.projects)
    result.push({
      label: T.activeProjects,
      value: overview.value.projects_active,
    });
  if (overview.value.capabilities.contracts)
    result.push(
      { label: T.activeContracts, value: overview.value.contracts_active },
      {
        label: T.monthlyRevenue,
        value: money(overview.value.contracts_mrr_cents),
      }
    );
  return result;
});

const displayValue = (key, value) => {
  if (value === null || value === undefined || value === '') return '\u2014';
  if (key === 'relationship_tags')
    return (
      value.map(item => RELATIONSHIPS[item] || item).join(', ') || '\u2014'
    );
  if (key === 'tags') return value.join(', ') || '\u2014';
  if (key === 'size') return SIZE_OPTIONS[value] || value;
  if (key === 'source') return SOURCE_OPTIONS[value] || value;
  if (key.endsWith('_at')) return date(value);
  return value;
};

const chooseSection = group => {
  section.value = group.key;
  if (!group.tabs.includes(tab.value)) tab.value = group.tabs[0];
};

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
    section.value = 'overview';
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
    >
      {{ T.customers }} / {{ T.companies }}
    </RouterLink>

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

    <template v-if="company">
      <header
        class="my-5 flex flex-wrap items-start justify-between gap-4 rounded-2xl border border-n-weak bg-n-solid-2 p-6"
      >
        <div class="min-w-0">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-brand">
            {{ T.master }} / {{ company.customer_code || `#${company.id}` }}
          </p>
          <h1 class="mt-2 text-2xl font-bold">{{ company.name }}</h1>
          <p class="mt-2 text-sm text-n-slate-10">
            {{ company.tax_id || '—' }} / {{ company.segment || '—' }} /
            {{ company.owner_name || T.noOwner }} / {{ company.city || '—' }}
          </p>
          <div class="mt-3 flex flex-wrap items-center gap-2 text-sm">
            <span
              class="rounded-lg bg-n-brand px-2.5 py-1 font-medium text-white"
            >
              {{ RELATIONSHIPS[company.relationship_type] }}
            </span>
            <span
              v-for="item in company.relationship_tags || []"
              :key="item"
              class="rounded-lg bg-n-alpha-2 px-2.5 py-1"
            >
              {{ RELATIONSHIPS[item] || item }}
            </span>
            <span
              class="rounded-lg px-2.5 py-1"
              :class="
                company.active
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-alpha-2 text-n-slate-10'
              "
            >
              {{ company.active ? T.active : T.inactive }}
            </span>
          </div>
          <div
            v-if="company.tags?.length"
            class="mt-3 flex flex-wrap gap-2"
          >
            <span
              v-for="tagValue in company.tags"
              :key="tagValue"
              class="rounded-full border border-n-weak px-2.5 py-1 text-xs text-n-slate-11"
            >
              {{ tagValue }}
            </span>
          </div>
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
      >
        {{ T.agenda }} / {{ company.name }}
      </RouterLink>

      <nav
        class="mb-3 flex flex-wrap gap-2"
        :aria-label="T.overview"
      >
        <button
          v-for="group in navigationGroups"
          :key="group.key"
          type="button"
          class="rounded-lg px-3 py-2 text-sm font-medium"
          :class="
            section === group.key
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          @click="chooseSection(group)"
        >
          {{ T[group.key] }}
        </button>
      </nav>

      <nav
        v-if="activeGroup?.tabs?.length > 1"
        class="mb-5 flex flex-wrap gap-2 border-b border-n-weak pb-3"
        :aria-label="T[section]"
      >
        <button
          v-for="key in activeGroup.tabs"
          :key="key"
          type="button"
          class="rounded-lg px-3 py-2 text-sm"
          :class="
            tab === key
              ? 'bg-n-alpha-4 font-medium text-n-slate-12'
              : 'text-n-slate-10'
          "
          :aria-current="tab === key ? 'page' : undefined"
          @click="tab = key"
        >
          {{ key === 'relationship' ? t('RELATIONSHIP.TITLE') : T[key] }}
        </button>
      </nav>

      <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
        <template v-if="tab === 'overview'">
          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <article
              v-for="card in cards"
              :key="card.label"
              class="rounded-xl border border-n-weak p-4"
            >
              <p class="text-sm text-n-slate-10">{{ card.label }}</p>
              <strong class="mt-2 block text-2xl">{{ card.value }}</strong>
            </article>
          </div>

          <div class="mt-5 grid gap-4 md:grid-cols-3">
            <article class="rounded-xl bg-n-alpha-2 p-4 text-sm">
              <p class="text-n-slate-10">{{ T.lastInteraction }}</p>
              <strong class="mt-1 block">{{
                date(overview?.last_interaction_at)
              }}</strong>
            </article>
            <article class="rounded-xl bg-n-alpha-2 p-4 text-sm">
              <p class="text-n-slate-10">{{ T.lastConversation }}</p>
              <strong class="mt-1 block">{{
                date(overview?.last_conversation_at)
              }}</strong>
            </article>
            <article class="rounded-xl bg-n-alpha-2 p-4 text-sm">
              <p class="text-n-slate-10">{{ T.nextActivity }}</p>
              <strong class="mt-1 block">
                {{ overview?.next_activity?.title || T.noNextActivity }}
              </strong>
              <span
                v-if="overview?.next_activity?.due_at"
                class="mt-1 block text-n-slate-10"
              >
                {{ date(overview.next_activity.due_at) }}
              </span>
            </article>
          </div>

          <p class="mt-5 text-sm text-n-slate-10">{{ T.permissionsHelp }}</p>
          <TimelinePanel
            class="mt-6"
            :resource-id="company.id"
          />
        </template>

        <template v-else-if="tab === 'general'">
          <dl class="grid gap-5 md:grid-cols-3">
            <div
              v-for="(label, key) in FIELD_LABELS"
              :key="key"
            >
              <template
                v-if="Object.prototype.hasOwnProperty.call(company, key)"
              >
                <dt class="text-xs text-n-slate-10">{{ label }}</dt>
                <dd class="mt-1 break-words text-sm">
                  {{ displayValue(key, company[key]) }}
                </dd>
              </template>
            </div>
          </dl>

          <div
            v-if="company.parent_company_id"
            class="mt-5"
          >
            <span>{{ T.parent }}: </span>
            <RouterLink
              :to="
                accountScopedRoute('jrc_customer_company', {
                  companyId: company.parent_company_id,
                })
              "
              class="text-n-brand"
            >
              #{{ company.parent_company_id }}
            </RouterLink>
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
            >
              {{ branch.name }}
            </RouterLink>
            <RouterLink
              v-if="branchesTotal > branches.length"
              :to="
                accountScopedRoute(
                  'jrc_customer_companies',
                  {},
                  { parent_company_id: company.id }
                )
              "
              class="mt-3 block text-n-brand"
            >
              {{ T.branches }}: {{ branchesTotal }} / {{ T.more }}
            </RouterLink>
          </div>
        </template>

        <RelationshipPanel
          v-else-if="tab === 'relationship'"
          :assignment-id="overview.relationship.id"
        />
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
