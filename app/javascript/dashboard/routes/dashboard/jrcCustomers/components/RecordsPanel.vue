<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, buttonClass, errorMessage } from '../copy';
const props = defineProps({
  companyId: { type: [Number, String], required: true },
  kind: { type: String, required: true },
});
const { accountId, accountScopedRoute, date } = useCustomerMaster();
const rows = ref([]);
const meta = ref({ total: 0 });
const page = ref(1);
const busy = ref(false);
const error = ref('');
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  busy.value = true;
  error.value = '';
  rows.value = [];
  try {
    const { data } = await API.records(props.companyId, {
      kind: props.kind,
      page: page.value,
    });
    if (version === generation) {
      rows.value = data.payload;
      meta.value = data.meta;
    }
  } catch (err) {
    if (version === generation) error.value = errorMessage(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const routeFor = row => {
  if (props.kind === 'conversations')
    return accountScopedRoute('inbox_conversation', {
      conversation_id: row.display_id,
    });
  if (props.kind === 'tickets')
    return accountScopedRoute('jrc_service_desk_detail', { ticketId: row.id });
  if (props.kind === 'projects')
    return accountScopedRoute('jrc_projects_detail', { projectId: row.id });
  if (props.kind === 'project_tasks')
    return accountScopedRoute(
      'jrc_projects_detail',
      { projectId: row.project_id },
      { taskId: row.id }
    );
  const routes = {
    contracts: 'crm_contracts',
    orders: 'crm_orders',
    follow_ups: 'crm_activities',
    leads: 'crm_leads',
    deals: 'crm_deals',
    proposals: 'crm_proposals',
    activities: 'crm_activities',
    campaigns: 'jrc_campaigns_index',
    calls: 'calls_dashboard_index',
  };
  return accountScopedRoute(routes[props.kind]);
};
watch(
  [accountId, () => props.companyId, () => props.kind],
  () => {
    page.value = 1;
    load();
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <p
      v-if="error"
      class="text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <p
      v-if="!busy && !rows.length"
      class="py-6 text-n-slate-10"
    >
      {{ T.noData }}
    </p>
    <div class="divide-y divide-n-weak">
      <article
        v-for="row in rows"
        :key="row.id"
        class="flex flex-wrap items-center justify-between gap-3 py-4"
      >
        <div>
          <RouterLink
            :to="routeFor(row)"
            class="font-semibold text-n-brand"
            >{{
              row.title ||
              row.name ||
              row.contract_number ||
              row.order_number ||
              `#${row.display_id || row.id}`
            }}</RouterLink
          >
          <p class="text-sm text-n-slate-10">
            {{ row.status }} / {{ date(row.created_at) }}
          </p>
          <p
            v-if="row.due_at"
            class="text-sm"
          >
            {{ date(row.due_at) }}
          </p>
        </div>
        <span
          v-if="row.duration_seconds != null"
          class="text-sm"
          >{{ row.duration_seconds }} {{ T.secondsShort }}</span
        >
      </article>
    </div>
    <div class="mt-4 flex items-center gap-3">
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="page--"
      >
        {{ T.previous }}</button
      ><span>{{ page }} / {{ Math.max(1, Math.ceil(meta.total / 25)) }}</span
      ><button
        type="button"
        :class="buttonClass"
        :disabled="busy || page * 25 >= meta.total"
        @click="page++"
      >
        {{ T.next }}
      </button>
    </div>
  </section>
</template>
