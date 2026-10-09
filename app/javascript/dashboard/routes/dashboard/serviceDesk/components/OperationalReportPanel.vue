<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
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
const emit = defineEmits(['open']);
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
const exportCsv = async () => {
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
  }[dimension];
  if (!field || value === null || busy.value) return;
  filters[field] = String(value);
  load(1);
}
</script>

<template>
  <Panel
    v-if="scope.session.state.context?.capabilities?.operational_reports?.index"
    :title="t('JRC_SERVICE_DESK.COMPLETION.report_title')"
  >
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      :disabled="busy"
    />
    <p class="my-3 text-sm">
      {{ t('JRC_SERVICE_DESK.COMPLETION.report_help') }}
    </p>
    <form
      class="grid gap-3 md:grid-cols-2"
      @submit.prevent="load(1)"
    >
      <ServiceSelect
        v-model="filters.service_id"
        :unit-id="unitId"
        :disabled="busy || !scope.allowed.value"
      />
      <div
        v-if="customerAllowed"
        class="grid gap-1"
      >
        <span class="text-sm">{{
          t('JRC_SERVICE_DESK.COMPLETION.fields.company_id')
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
      <LookupSelect
        v-model="filters.category_id"
        resource="categories"
        :unit-id="unitId"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.FIELDS.category')"
      />
      <LookupSelect
        v-model="filters.priority_id"
        resource="priorities"
        :unit-id="unitId"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.FIELDS.priority')"
      />
      <label
        v-for="field in ['from', 'to']"
        :key="field"
        class="grid gap-1 text-sm"
        >{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`)
        }}<input
          v-model="filters[field]"
          :disabled="busy"
          :placeholder="t('JRC_SERVICE_DESK.EXPERIENCE.timestamp_hint')"
          class="rounded border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <details
        class="md:col-span-2 rounded-xl border border-n-weak p-3"
        :open="advanced"
        @toggle="advanced = $event.target.open"
      >
        <summary class="cursor-pointer text-sm">
          {{ t('JRC_SERVICE_DESK.EXPERIENCE.advanced_filters') }}
        </summary>
        <p class="text-xs text-n-slate-11 my-2">
          {{ t('JRC_SERVICE_DESK.EXPERIENCE.advanced_filters_notice') }}
        </p>
        <div class="grid gap-3 md:grid-cols-2">
          <label
            v-for="field in ['inbox_id', 'channel_type']"
            :key="field"
            class="grid gap-1 text-sm"
            >{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`)
            }}<input
              v-model="filters[field]"
              :disabled="busy"
              class="rounded border border-n-weak bg-n-solid-1 p-2"
          /></label>
        </div>
      </details>
      <div class="flex flex-wrap gap-2 md:col-span-2">
        <Button
          type="submit"
          :disabled="busy || !scope.allowed.value"
          :label="t('JRC_SERVICE_DESK.COMPLETION.load')"
        /><Button
          variant="outline"
          :disabled="busy || !scope.allowed.value"
          :label="t('JRC_SERVICE_DESK.COMPLETION.export')"
          @click="exportCsv"
        />
      </div>
    </form>
    <p
      v-if="feedback"
      role="status"
    >
      {{ t(`JRC_SERVICE_DESK.COMPLETION.${feedback}`) }}
    </p>
    <template v-if="result">
      <p class="my-3">
        {{
          t('JRC_SERVICE_DESK.COMPLETION.report_total', {
            count: result.metrics.total,
            time: result.metrics.observed_at,
          })
        }}
      </p>
      <p class="my-2 text-sm">
        {{ t('JRC_SERVICE_DESK.COMPLETION.report_definition') }}
      </p>
      <div class="grid gap-4 md:grid-cols-2">
        <div
          v-for="dimension in reportDimensions"
          :key="dimension"
          class="rounded border border-n-weak p-3"
        >
          <h4 class="font-semibold">
            {{ t(`JRC_SERVICE_DESK.COMPLETION.dimensions.${dimension}`) }}
          </h4>
          <p v-if="result.metrics[dimension] === null">
            {{ t('JRC_SERVICE_DESK.COMPLETION.not_available') }}
          </p>
          <ul v-else>
            <li
              v-for="row in result.metrics[dimension].items"
              :key="row.id ?? 'missing'"
              class="flex justify-between gap-3"
            >
              <button
                type="button"
                class="text-start text-n-blue-11 underline break-words"
                :disabled="
                  row.id === null ||
                  busy ||
                  ['by_unit', 'by_origin'].includes(dimension)
                "
                @click="drilldown(dimension, row.id)"
              >
                {{ dimensionName(dimension, row.id) }}</button
              ><span class="tabular-nums">{{ row.count }}</span>
            </li>
          </ul>
          <p v-if="result.metrics[dimension]?.truncated">
            {{ t('JRC_SERVICE_DESK.COMPLETION.truncated') }}
          </p>
        </div>
      </div>
      <h4 class="mt-4 font-semibold">
        {{ t('JRC_SERVICE_DESK.COMPLETION.channels') }}
      </h4>
      <p class="text-xs">
        {{ t('JRC_SERVICE_DESK.COMPLETION.channel_overlap') }}
      </p>
      <ul>
        <li
          v-for="row in result.metrics.by_channel || []"
          :key="row.channel_type"
        >
          {{ row.channel_type }}: {{ row.count }}
        </li>
      </ul>
      <p
        v-if="result.metrics.reopen"
        class="my-3"
      >
        {{
          t('JRC_SERVICE_DESK.COMPLETION.reopen_summary', result.metrics.reopen)
        }}
      </p>
      <div
        v-if="result.metrics.sla"
        class="overflow-x-auto my-4"
      >
        <table class="w-full text-sm">
          <caption class="text-left">
            {{
              t('JRC_SERVICE_DESK.COMPLETION.sla_summary')
            }}
          </caption>
          <thead>
            <tr>
              <th>{{ t('JRC_SERVICE_DESK.COMPLETION.clock') }}</th>
              <th>{{ t('JRC_SERVICE_DESK.COMPLETION.completed') }}</th>
              <th>{{ t('JRC_SERVICE_DESK.COMPLETION.mean_seconds') }}</th>
              <th>{{ t('JRC_SERVICE_DESK.COMPLETION.breached') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, kind) in result.metrics.sla"
              :key="kind"
            >
              <td>{{ t(`JRC_SERVICE_DESK.COMPLETION.clocks.${kind}`) }}</td>
              <td>{{ row.completed }}</td>
              <td>
                {{
                  row.mean_elapsed_seconds ??
                  t('JRC_SERVICE_DESK.COMPLETION.not_available')
                }}
              </td>
              <td>{{ row.completed_breached }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p
        v-if="!result.items.length"
        role="status"
        class="my-4 text-sm"
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
  </Panel>
</template>
