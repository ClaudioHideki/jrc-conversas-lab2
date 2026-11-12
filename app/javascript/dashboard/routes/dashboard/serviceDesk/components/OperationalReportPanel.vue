<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import KpiCard from './KpiCard.vue';
import { downloadCsv } from '../helpers/csvExport';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import API from 'dashboard/api/serviceDeskOperationalRules';
import LookupSelect from './LookupSelect.vue';
import ServiceSelect from './ServiceDefinitionSelect.vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import { namedReportValue } from '../helpers/screenExperience.js';
import Panel from './ServiceDeskPanel.vue';
import ScopeBar from './ScopeBar.vue';
import TicketTable from './TicketTable.vue';
import { useOperationalScope } from '../composables/useOperationalScope';
import { assertEnvelope, reportFilters } from '../helpers/operationalRules.mjs';
import {
  decodeMetrics,
  reportDimensions,
} from '../helpers/operationalResults.mjs';
import { decodeRecord } from '../helpers/contracts';
const props = defineProps({
  initialDimension: { type: String, default: null },
});
const emit = defineEmits(['open']);
const resultTab = ref(props.initialDimension ? 'summary' : 'results');
const { t } = useI18n();
const { canAccess: masterAllowed } = useCustomerMaster();
const advanced = ref(false);
const unitId = ref('');
const operatorId = ref('');
const scope = useOperationalScope(
  unitId,
  context => context?.capabilities?.operational_reports?.index === true
);
const fields = [
  'service_id',
  'company_id',
  'inbox_id',
  'channel_type',
  'category_id',
  'priority_id',
  'status_id',
  'team_id',
  'account_user_id',
  'from',
  'to',
];
const filters = reactive(Object.fromEntries(fields.map(key => [key, ''])));
const result = ref(null);
const customerAllowed = computed(
  () =>
    masterAllowed.value &&
    scope.session.state.context?.effective_permissions?.includes(
      'jrc_service_desk_customers_view'
    )
);
const busy = ref(false);
const feedback = ref('');
const page = ref(1);
const reset = () => {
  scope.cancel();
  result.value = null;
  busy.value = false;
  feedback.value = '';
  page.value = 1;
};
watch(
  [scope.identity, unitId],
  () => {
    reset();
    fields.forEach(key => {
      filters[key] = '';
    });
  },
  { flush: 'sync' }
);
watch(filters, reset, { flush: 'sync' });
const load = async (targetPage = 1) => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  feedback.value = '';
  try {
    const query = reportFilters({ ...filters, page: targetPage, per_page: 25 });
    const payload = assertEnvelope(
      await API.report(
        lease.context.account_id,
        lease.unit,
        query,
        lease.signal
      ),
      lease.context,
      lease.unit
    );
    if (!scope.live(lease)) return;
    const metrics = decodeMetrics(payload.report, lease.context);
    if (
      !Array.isArray(payload.items) ||
      payload.meta?.page !== targetPage ||
      payload.meta?.per_page !== 25 ||
      payload.meta?.total !== metrics.total
    )
      throw new Error('Invalid report metadata');
    const items = payload.items.map(row =>
      decodeRecord(row, lease.context, 'tickets')
    );
    if (!items.every(row => row.unit_id === lease.unit))
      throw new Error('Foreign unit');
    result.value = { metrics, items, meta: payload.meta };
    page.value = targetPage;
  } catch {
    if (scope.live(lease)) {
      result.value = null;
      feedback.value = 'unavailable';
    }
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
const exportTickets = async () => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  try {
    const blob = await API.export(
      lease.context.account_id,
      lease.unit,
      reportFilters({ ...filters }),
      lease.signal
    );
    if (!scope.live(lease)) return;
    const href = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = href;
    link.download = 'service-desk-tickets.csv';
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(href), 1000);
  } catch {
    if (scope.live(lease)) feedback.value = 'unavailable';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
function dimensionName(dimension, value) {
  const name = namedReportValue(
    dimension,
    value,
    result.value?.items || [],
    scope.session.state.context,
    unitId.value
  );
  return (
    name ||
    (value === null
      ? t('JRC_SERVICE_DESK.COMMON.no_value')
      : t('JRC_SERVICE_DESK.EXPERIENCE.reference', { id: value }))
  );
}
function drilldown(dimension, value) {
  const field = {
    by_service: 'service_id',
    by_category: 'category_id',
    by_priority: 'priority_id',
    by_customer: 'company_id',
    by_status: 'status_id',
    by_team: 'team_id',
  }[dimension];
  if (!field || value === null || busy.value) return;
  filters[field] = String(value);
  load(1);
}
const visibleDimensions = computed(() =>
  props.initialDimension
    ? reportDimensions.filter(key => key === props.initialDimension)
    : reportDimensions
);
const canExport = computed(
  () => !!result.value && !busy.value && scope.allowed.value
);
const exportCsv = () => {
  if (!canExport.value) return;
  if (resultTab.value === 'results') {
    exportTickets();
    return;
  }
  downloadCsv(
    [
      [
        t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.field'),
        t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.value'),
        t('JRC_SERVICE_DESK.COMPLETION.report_total_short'),
      ],
      ...visibleDimensions.value.flatMap(key =>
        (result.value.metrics[key]?.items || []).map(row => [
          t(`JRC_SERVICE_DESK.COMPLETION.dimensions.${key}`),
          dimensionName(key, row.id),
          row.count,
        ])
      ),
    ],
    'service-desk-resumo.csv'
  );
};
const localDates = reactive({ from: '', to: '' });
watch([scope.identity, unitId], () => {
  localDates.from = '';
  localDates.to = '';
});
const updateDate = field => {
  filters[field] = localDates[field]
    ? new Date(localDates[field]).toISOString()
    : '';
};
const exportWorkforce = () => {
  if (!canExport.value || !result.value.metrics.workforce) return;
  const columns = [
    'employee',
    'created',
    'assigned',
    'pending',
    'closed',
    'closed_for_other_assignee',
    'closed_by_other',
    'resolution_mean',
    'assignee_sla',
  ];
  downloadCsv(
    [
      columns.map(key => t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.${key}`)),
      ...result.value.metrics.workforce.items.map(row => [
        row.name,
        row.created,
        row.assigned,
        row.pending,
        row.closed,
        row.closed_for_other_assignee,
        row.closed_by_other,
        row.resolution_mean_seconds,
        row.sla_completed
          ? (100 * (row.sla_completed - row.sla_breached)) / row.sla_completed
          : null,
      ]),
    ],
    'service-desk-funcionarios.csv'
  );
};
const compliance = row =>
  row.completed
    ? `${((100 * (row.completed - row.completed_breached)) / row.completed).toFixed(1)}%`
    : t('JRC_SERVICE_DESK.COMMON.no_value');
const cards = computed(() => {
  const metrics = result.value?.metrics;
  return [
    { key: 'total', tone: 'blue', value: metrics?.total ?? null },
    {
      key: 'resolution_rate',
      tone: 'teal',
      value:
        metrics?.resolution_rate == null
          ? null
          : Math.round(metrics.resolution_rate),
      display:
        metrics?.resolution_rate == null
          ? ''
          : `${metrics.resolution_rate.toFixed(1)}%`,
    },
    {
      key: 'resolved',
      tone: 'teal',
      value: metrics?.phases ? metrics.phases.resolved || 0 : null,
    },
    {
      key: 'waiting',
      tone: 'amber',
      value: metrics?.phases ? metrics.phases.waiting || 0 : null,
    },
    {
      key: 'closed',
      tone: 'iris',
      value: metrics?.activity?.closed_tickets ?? null,
    },
    {
      key: 'running_breached',
      tone: 'ruby',
      value: metrics?.sla
        ? Object.values(metrics.sla).reduce(
            (sum, row) => sum + row.running_overdue,
            0
          )
        : null,
    },
  ];
});
defineExpose({ canExport, exportCsv });
</script>

<template>
  <section
    v-if="scope.session.state.context?.capabilities?.operational_reports?.index"
    class="grid gap-5"
    data-testid="operational-report"
  >
    <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
      <KpiCard
        v-for="card in cards"
        :key="card.key"
        :label="t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.metrics.${card.key}`)"
        :value="card.value"
        :display-value="card.display || ''"
        :hint="
          card.key === 'resolution_rate'
            ? t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.resolution_rate_help')
            : ''
        "
        :tone="card.tone"
        compact
      />
    </div>
    <Panel
      :title="t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.filters')"
      icon="i-lucide-list-filter"
    >
      <form
        class="grid gap-4 md:grid-cols-2 xl:grid-cols-6"
        @submit.prevent="load(1)"
      >
        <div
          class="md:col-span-2 xl:col-span-2 [&_.sd-scope-bar]:!grid-cols-1 md:[&_.sd-scope-bar]:!grid-cols-2 [&_.sd-scope-bar>p]:hidden"
        >
          <ScopeBar
            v-model:unit-id="unitId"
            v-model:operator-id="operatorId"
            required
            :disabled="busy"
          />
        </div>
        <ServiceSelect
          v-model="filters.service_id"
          :unit-id="unitId"
          :disabled="busy || !scope.allowed.value"
          :general-label="t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.all_services')"
          :show-refresh="false"
          class="min-w-0 [&_.w-fit]:w-full [&_select]:w-full"
        />
        <LookupSelect
          v-for="[field, resource, label] in [
            ['category_id', 'categories', 'category'],
            ['priority_id', 'priorities', 'priority'],
            ['status_id', 'statuses', 'status'],
          ]"
          :key="field"
          v-model="filters[field]"
          :resource="resource"
          :unit-id="unitId"
          :disabled="busy"
          :label="t(`JRC_SERVICE_DESK.FIELDS.${label}`)"
        />
        <label
          v-for="field in ['from', 'to']"
          :key="field"
          class="grid gap-1 text-sm xl:col-span-2"
          >{{ t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.${field}`)
          }}<input
            v-model="localDates[field]"
            type="datetime-local"
            :disabled="busy"
            class="w-full rounded-xl border border-blue-200 bg-n-solid-1 p-2.5 dark:border-n-weak"
            @change="updateDate(field)"
        /></label>
        <div
          class="flex flex-wrap items-end justify-end gap-2 md:col-span-2 xl:col-span-2"
        >
          <Button
            type="submit"
            icon="i-lucide-refresh-cw"
            :disabled="busy || !scope.allowed.value"
            :label="t('JRC_SERVICE_DESK.COMPLETION.load')"
          />
          <Button
            type="button"
            variant="outline"
            icon="i-lucide-download"
            :disabled="busy || !scope.allowed.value"
            :label="t('JRC_SERVICE_DESK.COMPLETION.export')"
            @click="exportTickets"
          />
        </div>
        <details
          class="rounded-xl border border-blue-200 bg-blue-50/50 p-3 dark:border-n-weak dark:bg-n-solid-2 md:col-span-2 xl:col-span-6"
          :open="advanced"
          @toggle="advanced = $event.target.open"
        >
          <summary class="cursor-pointer text-sm font-semibold">
            {{ t('JRC_SERVICE_DESK.EXPERIENCE.advanced_filters') }}
          </summary>
          <div class="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            <LookupSelect
              v-if="scope.session.state.context?.capabilities?.teams?.index"
              v-model="filters.team_id"
              resource="teams"
              :unit-id="unitId"
              :disabled="busy"
              :label="t('JRC_SERVICE_DESK.FIELDS.team')"
            />
            <LookupSelect
              v-if="scope.session.state.context?.capabilities?.assignees?.index"
              v-model="filters.account_user_id"
              resource="assignees"
              :unit-id="unitId"
              :disabled="busy"
              :label="t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.employee_filter')"
            />
            <div
              v-if="customerAllowed"
              class="grid gap-1"
            >
              <span class="text-sm">{{
                t('JRC_SERVICE_DESK.FIELDS.company_id')
              }}</span
              ><CompanyPicker
                :key="scope.identity.value"
                :model-value="filters.company_id || null"
                :disabled="busy || !scope.allowed.value"
                @update:model-value="
                  filters.company_id = $event ? String($event) : ''
                "
              />
            </div>
            <label
              v-for="field in ['inbox_id', 'channel_type']"
              :key="field"
              class="grid gap-1 text-sm"
              >{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`)
              }}<input
                v-model="filters[field]"
                :disabled="busy"
                class="rounded-xl border border-n-weak bg-n-solid-1 p-2.5"
            /></label>
          </div>
        </details>
      </form>
    </Panel>
    <p
      v-if="feedback"
      role="status"
    >
      {{ t(`JRC_SERVICE_DESK.COMPLETION.${feedback}`) }}
    </p>
    <template v-if="result">
      <div class="grid items-start gap-5 2xl:grid-cols-[minmax(0,1fr)_340px]">
        <Panel
          :title="t('JRC_SERVICE_DESK.COMPLETION.report_title')"
          icon="i-lucide-chart-column"
        >
          <template #actions>
            <Button
              size="sm"
              variant="outline"
              icon="i-lucide-download"
              :disabled="!canExport"
              :label="t('JRC_SERVICE_DESK.COMPLETION.export')"
              @click="exportCsv"
            />
          </template>
          <nav
            class="mb-4 flex flex-wrap gap-2"
            :aria-label="t('JRC_SERVICE_DESK.COMPLETION.report_title')"
          >
            <button
              v-for="tab in ['results', 'summary']"
              :key="tab"
              type="button"
              class="rounded-xl border px-4 py-2 text-sm font-semibold"
              :class="
                resultTab === tab
                  ? 'border-blue-600 bg-blue-600 text-white'
                  : 'border-blue-200 bg-n-solid-1'
              "
              :aria-pressed="resultTab === tab"
              @click="resultTab = tab"
            >
              {{ t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.${tab}`) }}
            </button>
          </nav>
          <template v-if="resultTab === 'results'">
            <p
              v-if="!result.items.length"
              role="status"
            >
              {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
            </p>
            <TicketTable
              :items="result.items"
              @open="emit('open', $event)"
              @preview="emit('open', $event)"
            />
            <Pagination
              v-if="result.meta.total"
              :current-page="page"
              :total-items="result.meta.total"
              :items-per-page="25"
              @update:current-page="load($event)"
            />
          </template>
          <div
            v-else
            class="grid gap-4 lg:grid-cols-2"
          >
            <section
              v-for="dimension in visibleDimensions"
              :key="dimension"
              class="rounded-xl border border-blue-200 bg-blue-50/40 p-4 dark:border-n-weak dark:bg-n-solid-2"
            >
              <h3 class="m-0 mb-3 text-sm font-bold">
                {{ t(`JRC_SERVICE_DESK.COMPLETION.dimensions.${dimension}`) }}
              </h3>
              <p v-if="result.metrics[dimension] === null">
                {{ t('JRC_SERVICE_DESK.COMMON.not_available') }}
              </p>
              <div
                v-for="row in result.metrics[dimension]?.items || []"
                :key="row.id ?? 'missing'"
                class="flex justify-between gap-3 border-b border-n-weak py-2 text-sm"
              >
                <button
                  type="button"
                  class="text-start text-n-blue-11"
                  :disabled="
                    row.id === null ||
                    busy ||
                    ['by_unit', 'by_origin'].includes(dimension)
                  "
                  @click="drilldown(dimension, row.id)"
                >
                  {{ dimensionName(dimension, row.id) }}</button
                ><strong class="tabular-nums">{{ row.count }}</strong>
              </div>
              <p
                v-if="result.metrics[dimension]?.truncated"
                class="mt-3 text-xs"
              >
                {{ t('JRC_SERVICE_DESK.COMPLETION.truncated') }}
              </p>
            </section>
          </div>
        </Panel>
        <Panel
          :title="t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.sla_title')"
          icon="i-lucide-timer"
        >
          <div class="overflow-x-auto">
            <table
              v-if="result.metrics.sla"
              class="w-full text-sm"
            >
              <caption class="mb-3 text-start text-xs text-n-slate-11">
                {{
                  t('JRC_SERVICE_DESK.COMPLETION.sla_summary')
                }}
              </caption>
              <thead class="border-b border-blue-200 text-start text-xs">
                <tr>
                  <th class="py-3 text-start">
                    {{ t('JRC_SERVICE_DESK.COMPLETION.clock') }}
                  </th>
                  <th>{{ t('JRC_SERVICE_DESK.COMPLETION.observed') }}</th>
                  <th>{{ t('JRC_SERVICE_DESK.COMPLETION.completed') }}</th>
                  <th>{{ t('JRC_SERVICE_DESK.COMPLETION.mean_seconds') }}</th>
                  <th>{{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.in_time') }}</th>
                  <th>{{ t('JRC_SERVICE_DESK.COMPLETION.breached') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(row, kind) in result.metrics.sla"
                  :key="kind"
                  class="border-b border-n-weak"
                >
                  <td class="py-4">
                    {{ t(`JRC_SERVICE_DESK.COMPLETION.clocks.${kind}`) }}
                  </td>
                  <td class="px-2 text-center">{{ row.observed }}</td>
                  <td class="px-2 text-center">{{ row.completed }}</td>
                  <td class="px-2 text-center">
                    {{
                      row.mean_elapsed_seconds ??
                      t('JRC_SERVICE_DESK.COMPLETION.not_available')
                    }}
                  </td>
                  <td class="px-2 text-center">
                    <span
                      class="rounded-lg bg-emerald-100 px-2 py-1 font-semibold text-emerald-800"
                      >{{ compliance(row) }}</span
                    >
                  </td>
                  <td class="px-2 text-center">
                    <span
                      class="rounded-lg bg-rose-100 px-2 py-1 font-semibold text-rose-800"
                      >{{
                        row.completed
                          ? row.completed_breached
                          : t('JRC_SERVICE_DESK.COMPLETION.not_available')
                      }}</span
                    >
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="mb-0 mt-4 text-xs text-n-slate-11">
            {{ t('JRC_SERVICE_DESK.COMPLETION.report_definition') }}
          </p>
        </Panel>
      </div>
      <details
        v-if="result.metrics.daily_activity"
        class="rounded-2xl border border-blue-200 bg-n-solid-1 p-4 shadow-sm dark:border-n-weak"
      >
        <summary class="cursor-pointer font-semibold text-n-blue-11">
          {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.flow') }}
        </summary>
        <p class="mt-3 text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.flow_help') }}
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr>
                <th class="py-3 text-start">
                  {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.date') }}
                </th>
                <th
                  v-for="key in [
                    'opened',
                    'closed',
                    'reopened',
                    'backlog_change',
                  ]"
                  :key="key"
                  class="px-3"
                >
                  {{ t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.flow_${key}`) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in result.metrics.daily_activity.items"
                :key="row.date"
                class="border-t border-n-weak"
              >
                <td class="py-3">{{ row.date }}</td>
                <td
                  v-for="key in [
                    'opened',
                    'closed',
                    'reopened',
                    'backlog_change',
                  ]"
                  :key="key"
                  class="px-3 text-center tabular-nums"
                >
                  {{ row[key] }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p
          v-if="result.metrics.daily_activity.truncated"
          class="text-xs"
        >
          {{ t('JRC_SERVICE_DESK.COMPLETION.truncated') }}
        </p>
      </details>
      <Panel
        v-if="result.metrics.workforce"
        :title="t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.workforce')"
        icon="i-lucide-users"
      >
        <template #actions
          ><Button
            size="sm"
            variant="outline"
            icon="i-lucide-download"
            :disabled="!canExport"
            :label="t('JRC_SERVICE_DESK.COMPLETION.export')"
            @click="exportWorkforce"
        /></template>
        <p class="text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.workforce_help') }}
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr>
                <th class="py-3 text-start">
                  {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.employee') }}
                </th>
                <th
                  v-for="field in [
                    'created',
                    'assigned',
                    'pending',
                    'closed',
                    'closed_for_other_assignee',
                    'closed_by_other',
                  ]"
                  :key="field"
                  class="px-3"
                >
                  {{ t(`JRC_SERVICE_DESK.REPORT_EXPERIENCE.${field}`) }}
                </th>
                <th class="px-3">
                  {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.resolution_mean') }}
                </th>
                <th class="px-3">
                  {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.assignee_sla') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in result.metrics.workforce.items"
                :key="row.account_user_id"
                class="border-t border-n-weak"
              >
                <td class="py-3 font-semibold">{{ row.name }}</td>
                <td
                  v-for="field in [
                    'created',
                    'assigned',
                    'pending',
                    'closed',
                    'closed_for_other_assignee',
                    'closed_by_other',
                  ]"
                  :key="field"
                  class="px-3 text-center tabular-nums"
                >
                  {{ row[field] }}
                </td>
                <td class="px-3 text-center">
                  {{
                    row.resolution_mean_seconds === null
                      ? t('JRC_SERVICE_DESK.COMMON.no_value')
                      : Math.round(row.resolution_mean_seconds)
                  }}
                </td>
                <td class="px-3 text-center">
                  {{
                    row.sla_completed
                      ? `${((100 * (row.sla_completed - row.sla_breached)) / row.sla_completed).toFixed(1)}%`
                      : t('JRC_SERVICE_DESK.COMMON.no_value')
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p
          v-if="result.metrics.workforce.truncated"
          class="text-xs"
        >
          {{ t('JRC_SERVICE_DESK.COMPLETION.truncated') }}
        </p>
      </Panel>
      <p class="text-xs text-n-slate-11">
        {{
          t('JRC_SERVICE_DESK.COMPLETION.report_total', {
            count: result.metrics.total,
            time: result.metrics.observed_at,
          })
        }}
      </p>
    </template>
  </section>
</template>
