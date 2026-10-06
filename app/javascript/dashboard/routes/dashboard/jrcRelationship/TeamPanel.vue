<script setup>
import { ref, watch, reactive } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import MetricsPanel from './MetricsPanel.vue';
import MetricDrilldownPanel from './MetricDrilldownPanel.vue';
import {
  message,
  money as formatMoney,
  inputClass,
  buttonClass,
} from './definitions';
const props = defineProps({
  startDate: String,
  endDate: String,
  search: { type: String, default: '' },
  refresh: Number,
});
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const rows = ref([]);
const metrics = ref(null);
const drilldown = ref(null);
const error = ref('');
const busy = ref(false);
const metadata = ref(null);
const localRefresh = ref(0);
const filters = reactive({
  segment_id: '',
  product_id: '',
  business_unit_id: '',
  complexity: '',
});
let activeController;
const query = () => ({
  ...Object.fromEntries(
    Object.entries(filters).filter(([, value]) => value !== '')
  ),
  from: props.startDate || undefined,
  to: props.endDate || undefined,
  agent_q: props.search.trim() || undefined,
});
const inspectMetric = async (metric, page = 1) => {
  const requested = typeof metric === 'object' ? metric : { metric };
  const controller = activeController;
  try {
    const { data } = await API.drilldown(
      route.params.accountId,
      { ...query(), ...requested, page },
      { signal: controller.signal }
    );
    if (!controller.signal.aborted) drilldown.value = data;
  } catch (err) {
    if (!controller.signal.aborted) error.value = message(err);
  }
};
const filterPortfolio = filter =>
  router.push({
    name: 'jrc_relationship_portfolio',
    params: route.params,
    query: {
      ...query(),
      mode: filter.renewal_days ? 'renewals' : undefined,
      renewal_days: filter.renewal_days,
      band: filter.band,
      factor: filter.factor,
      factor_direction: filter.direction,
    },
  });
const keys = [
  'customers',
  'mrr_cents',
  'health_average',
  'at_risk',
  'renewals_60',
  'overdue_actions',
  'overdue_activities',
  'waiting_customer_actions',
  'waiting_finance_actions',
  'churned',
  'retained',
  'retention_rate',
  'expansion_potential_cents',
  'expansion_won_cents',
  'without_contact',
  'nps',
  'csat',
  'first_action_minutes',
];
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.refresh,
    () => localRefresh.value,
    () => props.startDate,
    () => props.endDate,
    () => props.search,
  ],
  async (_, __, cleanup) => {
    const controller = new AbortController();
    activeController = controller;
    cleanup(() => controller.abort());
    rows.value = [];
    metadata.value = null;
    metrics.value = null;
    drilldown.value = null;
    error.value = '';
    busy.value = true;
    try {
      const params = query();
      const results = await Promise.all([
        API.metadata(route.params.accountId, { signal: controller.signal }),
        API.team(route.params.accountId, params, {
          signal: controller.signal,
        }),
        API.dashboard(route.params.accountId, params, {
          signal: controller.signal,
        }),
      ]);
      if (!controller.signal.aborted) {
        metadata.value = results[0].data;
        rows.value = results[1].data.payload;
        metrics.value = results[2].data;
      }
    } catch (err) {
      if (!controller.signal.aborted) error.value = message(err);
    } finally {
      if (!controller.signal.aborted) busy.value = false;
    }
  },
  { immediate: true }
);
const money = value => formatMoney(value, metadata.value?.formatting);
</script>

<template>
  <section class="space-y-4 overflow-auto">
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ error }}
    </p>
    <form
      v-if="metadata"
      class="flex flex-wrap items-end gap-3"
      @submit.prevent="localRefresh += 1"
    >
      <label
        v-for="key in ['segment_id', 'product_id', 'business_unit_id']"
        :key="key"
        class="text-xs"
        >{{ t(`RELATIONSHIP.FIELDS.${key}`)
        }}<select
          v-model="filters[key]"
          :class="inputClass"
        >
          <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
          <option
            v-for="item in metadata[
              {
                segment_id: 'segments',
                product_id: 'products',
                business_unit_id: 'units',
              }[key]
            ] || []"
            :key="item[0]"
            :value="item[0]"
          >
            {{ item[1] }}
          </option>
        </select></label
      >
      <label class="text-xs"
        >{{ t('RELATIONSHIP.FIELDS.complexity')
        }}<input
          v-model="filters.complexity"
          :class="inputClass" /></label
      ><button
        type="submit"
        :class="buttonClass"
        :disabled="busy"
      >
        {{ t('RELATIONSHIP.FILTER') }}
      </button>
    </form>
    <MetricsPanel
      v-if="metrics"
      :metrics="metrics"
      :metadata="metadata"
      inspect
      @inspect="inspectMetric"
      @filter="filterPortfolio"
    />
    <MetricDrilldownPanel
      v-if="drilldown"
      :data="drilldown"
      :metadata="metadata"
      @close="drilldown = null"
      @page="
        inspectMetric({ metric: drilldown.metric, day: drilldown.day }, $event)
      "
    />
    <div
      v-if="rows.length"
      class="overflow-x-auto rounded-xl border border-n-weak"
    >
      <table class="w-full text-left text-sm">
        <thead class="bg-n-alpha-2">
          <tr>
            <th class="p-3">{{ t('RELATIONSHIP.FIELDS.owner_id') }}</th>
            <th
              v-for="key in keys"
              :key="key"
              class="p-3"
            >
              {{ t(`RELATIONSHIP.METRICS.${key}`) }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr
            v-for="row in rows"
            :key="row.user.id"
          >
            <td class="p-3 font-semibold">{{ row.user.name }}</td>
            <td
              v-for="key in keys"
              :key="key"
              class="p-3"
            >
              {{
                key.endsWith('_cents')
                  ? money(row.metrics[key])
                  : (row.metrics[key] ?? '—')
              }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p
      v-if="!busy && !error && !rows.length"
      class="text-sm text-n-slate-11"
    >
      {{ t('RELATIONSHIP.EMPTY') }}
    </p>
  </section>
</template>
