<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { useBackofficePresentation } from '../../crm/views/backoffice/useBackofficePresentation';

const props = defineProps({
  companyId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const { accountId, identity, accountScopedRoute, date } = useCustomerMaster();
const { label } = useBackofficePresentation();
const views = [
  'requests',
  'documents',
  'approvals',
  'contracts',
  'issues',
  'history',
];
const view = ref('requests');
const page = ref(1);
const query = ref('');
const appliedQuery = ref('');
const result = ref(null);
const busy = ref(false);
const error = ref('');
let generation = 0;
let controller;
const viewTitle = key =>
  ({
    requests: t('CRM.CUSTOMER_MASTER_360.VIEWS.requests'),
    documents: t('CRM.CUSTOMER_MASTER_360.VIEWS.documents'),
    approvals: t('CRM.CUSTOMER_MASTER_360.VIEWS.approvals'),
    contracts: t('CRM.CUSTOMER_MASTER_360.VIEWS.contracts'),
    issues: t('CRM.CUSTOMER_MASTER_360.VIEWS.issues'),
    history: t('CRM.CUSTOMER_MASTER_360.VIEWS.history'),
  })[key];
const countTitle = key =>
  ({
    total: t('CRM.CUSTOMER_MASTER_360.COUNTS.total'),
    active: t('CRM.CUSTOMER_MASTER_360.COUNTS.active'),
    overdue: t('CRM.CUSTOMER_MASTER_360.COUNTS.overdue'),
    completed: t('CRM.CUSTOMER_MASTER_360.COUNTS.completed'),
  })[key];
const source = row =>
  accountScopedRoute(
    'crm_backoffice_request',
    { requestId: row.request_id || row.id },
    {
      tab:
        {
          documents: 'documents',
          contracts: 'contracts',
          issues: 'issues',
          history: 'history',
        }[view.value] || 'overview',
    }
  );
const eventTitle = kind =>
  ({
    backoffice_created: t('CRM.CUSTOMER_MASTER_360.EVENT_CREATED'),
    backoffice_updated: t('CRM.CUSTOMER_MASTER_360.EVENT_UPDATED'),
    backoffice_stage_changed: t('CRM.CUSTOMER_MASTER_360.EVENT_STAGE'),
    backoffice_document_uploaded: t('CRM.CUSTOMER_MASTER_360.EVENT_DOCUMENT'),
    backoffice_document_status_changed: t(
      'CRM.CUSTOMER_MASTER_360.EVENT_DOCUMENT_DECISION'
    ),
    backoffice_issue_created: t('CRM.CUSTOMER_MASTER_360.EVENT_ISSUE'),
    backoffice_issue_resolved: t(
      'CRM.CUSTOMER_MASTER_360.EVENT_ISSUE_RESOLVED'
    ),
    backoffice_reopened: t('CRM.CUSTOMER_MASTER_360.EVENT_REOPENED'),
  })[kind] || t('CRM.CUSTOMER_MASTER_360.EVENT_RECORDED');
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.backoffice(
      props.companyId,
      {
        view: view.value,
        page: page.value,
        per_page: 20,
        q: appliedQuery.value,
      },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (token === generation) result.value = data;
  } catch (failure) {
    if (token !== generation) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? t('CRM.CUSTOMER_MASTER_360.DENIED')
      : t('CRM.CUSTOMER_MASTER_360.LOAD_ERROR');
  } finally {
    if (token === generation) busy.value = false;
  }
};
const search = () => {
  appliedQuery.value = query.value;
  if (page.value === 1) load();
  else page.value = 1;
};
watch(
  [identity, () => props.companyId, view],
  () => {
    generation += 1;
    controller?.abort();
    result.value = null;
    if (page.value === 1) load();
    else page.value = 1;
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  result.value = null;
});
</script>

<template>
  <section
    class="space-y-4"
    :aria-busy="busy"
  >
    <header class="rounded-xl border border-n-teal-6 bg-n-teal-3 p-4">
      <h2 class="font-bold text-n-teal-12">
        {{ t('CRM.CUSTOMER_MASTER_360.BACKOFFICE_TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('CRM.CUSTOMER_MASTER_360.BACKOFFICE_DESCRIPTION') }}
      </p>
    </header>
    <nav
      class="flex flex-wrap gap-2"
      :aria-label="t('CRM.CUSTOMER_MASTER_360.BACKOFFICE_TITLE')"
    >
      <button
        v-for="item in views"
        :key="item"
        type="button"
        class="rounded-lg border px-3 py-2 text-sm font-semibold"
        :class="
          view === item
            ? 'border-n-blue-8 bg-n-blue-9 text-white'
            : 'border-n-teal-6 bg-n-teal-3 text-n-teal-12'
        "
        :aria-current="view === item ? 'page' : undefined"
        @click="view = item"
      >
        {{ viewTitle(item) }}
      </button>
    </nav>
    <form
      v-if="view !== 'history'"
      class="flex flex-wrap gap-2"
      @submit.prevent="search"
    >
      <input
        v-model.trim="query"
        type="search"
        maxlength="200"
        class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm"
        :aria-label="t('CRM.CUSTOMER_MASTER_360.SEARCH')"
        :placeholder="t('CRM.CUSTOMER_MASTER_360.SEARCH')"
      />
      <button
        type="submit"
        :disabled="busy"
        class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm text-white disabled:opacity-50"
      >
        {{ t('CRM.CUSTOMER_MASTER_360.SEARCH_BUTTON') }}
      </button>
    </form>
    <p
      v-if="busy"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ t('CRM.CUSTOMER_MASTER_360.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
    >
      {{ error }}
    </p>
    <template v-if="result">
      <div
        v-if="result.summary"
        class="grid grid-cols-2 gap-3 md:grid-cols-4"
      >
        <article
          v-for="key in ['total', 'active', 'overdue', 'completed']"
          :key="key"
          class="rounded-xl border border-n-blue-6 bg-n-blue-3 p-3"
        >
          <p class="text-xs text-n-blue-12">
            {{ countTitle(key) }}
          </p>
          <b class="mt-1 block text-xl text-n-blue-12">{{
            result.summary[key]
          }}</b>
        </article>
      </div>
      <p
        v-if="!result.data.length"
        class="rounded-lg border border-dashed border-n-weak p-4 text-sm text-n-slate-11"
      >
        {{ t('CRM.CUSTOMER_MASTER_360.EMPTY') }}
      </p>
      <article
        v-for="row in result.data"
        :key="row.id"
        class="space-y-2 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm"
      >
        <template v-if="view === 'history'">
          <b>{{ eventTitle(row.event_type) }}</b>
          <p class="text-n-slate-11">{{ date(row.created_at) }}</p>
        </template>
        <template v-else>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <b>{{ row.request_number }}</b>
            <span class="rounded-lg bg-n-teal-3 px-2 py-1">
              <span class="text-xs text-n-teal-12">{{
                label(row.status)
              }}</span>
            </span>
          </div>
          <p>{{ row.title }}</p>
          <p class="text-xs text-n-slate-11">
            {{
              `${label(row.stage)} · ${row.owner.name} · ${date(row.updated_at)}`
            }}
          </p>
          <p class="text-xs text-n-slate-11">{{ row.order.order_number }}</p>
        </template>
        <RouterLink
          :to="source(row)"
          class="inline-block rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-n-blue-12"
        >
          {{ t('CRM.CUSTOMER_MASTER_360.OPEN_REQUEST') }}
        </RouterLink>
      </article>
      <nav
        class="flex justify-between gap-3"
        :aria-label="t('CRM.CUSTOMER_MASTER_360.PAGINATION')"
      >
        <button
          type="button"
          :disabled="busy || result.meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="page = result.meta.page - 1"
        >
          {{ t('CRM.CUSTOMER_MASTER_360.PREVIOUS') }}
        </button>
        <span class="self-center text-sm">{{
          `${result.meta.page} / ${result.meta.pages}`
        }}</span>
        <button
          type="button"
          :disabled="busy || result.meta.page >= result.meta.pages"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="page = result.meta.page + 1"
        >
          {{ t('CRM.CUSTOMER_MASTER_360.NEXT') }}
        </button>
      </nav>
    </template>
    <button
      type="button"
      :disabled="busy"
      class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
      @click="load"
    >
      {{ t('CRM.CUSTOMER_MASTER_360.REFRESH') }}
    </button>
  </section>
</template>
