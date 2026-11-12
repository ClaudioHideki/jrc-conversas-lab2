<script setup>
import { computed, getCurrentInstance, reactive, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskSatisfaction';
import { useOperationalScope } from '../composables/useOperationalScope';
import { assertEnvelope } from '../helpers/operationalRules.mjs';
import { canonicalId } from '../helpers/access';
import { tones } from '../helpers/visualTheme';
import ServiceSelect from './ServiceDefinitionSelect.vue';
import Panel from './ServiceDeskPanel.vue';
import ReportDialog from './ReportDialog.vue';
import CompanyPicker from '../../jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from '../../jrcCustomers/useCustomerMaster';
const props = defineProps({ unitId: { type: String, required: true } });
const emit = defineEmits(['responses']);
const { t, locale } = useI18n();
const { canAccess: masterAllowed } = useCustomerMaster();
const scope = useOperationalScope(
  toRef(props, 'unitId'),
  context => context?.capabilities?.surveys?.index === true
);
const filters = reactive({
  from: '',
  to: '',
  service_id: '',
  company_id: '',
  type: '',
  period_basis: 'cohort',
  record_status: '',
});
const result = ref(null);
const busy = ref(false);
const error = ref('');
const selected = ref(null);
const chartId = `sd-satisfaction-${getCurrentInstance().uid}`;
const count = value => Number.isSafeInteger(value) && value >= 0;
const optional = (value, min, max) =>
  value === null || (Number.isFinite(value) && value >= min && value <= max);
const validate = data => {
  if (
    !data.summary ||
    !count(data.summary.response_count) ||
    !optional(data.summary.csat, 1, 5) ||
    !optional(data.summary.nps, -100, 100)
  )
    throw new TypeError('Invalid survey metrics');
  if (
    !Array.isArray(data.items) ||
    !data.items.every(
      row =>
        canonicalId(row.id) &&
        canonicalId(row.ticket_id) &&
        typeof row.responded_at === 'string' &&
        ['csat', 'nps', 'ces', 'custom'].includes(row.kind)
    )
  )
    throw new TypeError('Invalid responses');
  if (
    !Array.isArray(data.distribution) ||
    !data.distribution.every(
      row =>
        Number.isInteger(row.score) &&
        row.score >= 1 &&
        row.score <= 5 &&
        count(row.count)
    )
  )
    throw new TypeError('Invalid distribution');
  if (
    !Array.isArray(data.services) ||
    !data.services.every(
      row => optional(row.csat, 1, 5) && count(row.responses)
    )
  )
    throw new TypeError('Invalid service scores');
  if (
    !Array.isArray(data.summary.trend) ||
    !data.summary.trend.every(
      row =>
        ['csat', 'nps', 'ces', 'custom'].includes(row.kind) &&
        count(row.response_count) &&
        typeof row.day === 'string' &&
        Number.isFinite(Date.parse(row.day))
    )
  )
    throw new TypeError('Invalid trend');
  const delivery = data.summary.delivery;
  if (!delivery || typeof delivery.available !== 'boolean')
    throw new TypeError('Invalid delivery evidence');
  if (
    delivery.available &&
    ![
      'sent_count',
      'delivered_count',
      'eligible_answered_count',
      'eligible_count',
    ].every(key => count(delivery[key]))
  )
    throw new TypeError('Invalid delivery counts');
  return data;
};
const params = () =>
  Object.fromEntries(
    Object.entries({ ...filters, unit_id: props.unitId }).filter(
      ([, value]) => value !== ''
    )
  );
const load = async () => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  error.value = '';
  try {
    const data = await API.report(
      lease.context.account_id,
      params(),
      lease.signal
    );
    if (!scope.live(lease)) return;
    result.value = validate(assertEnvelope(data, lease.context, lease.unit));
  } catch {
    if (scope.live(lease)) {
      result.value = null;
      error.value = 'unavailable';
    }
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
const reset = () => {
  scope.cancel();
  result.value = null;
  selected.value = null;
  busy.value = false;
  error.value = '';
};
watch(
  [scope.identity, () => props.unitId],
  () => {
    reset();
    Object.assign(filters, {
      from: '',
      to: '',
      service_id: '',
      company_id: '',
      type: '',
      period_basis: 'cohort',
      record_status: '',
    });
  },
  { flush: 'sync' }
);
watch(filters, reset, { flush: 'sync' });
const download = async () => {
  if (!result.value || busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  try {
    const blob = await API.export(
      lease.context.account_id,
      params(),
      lease.signal
    );
    if (!scope.live(lease)) return;
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `JRC_ServiceDesk_Satisfacao_Unidade${lease.unit}.csv`;
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch {
    if (scope.live(lease)) error.value = 'export_failed';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
const number = (value, digits = 0) =>
  value === null || value === undefined
    ? '—'
    : new Intl.NumberFormat(locale.value.replace('_', '-'), {
        minimumFractionDigits: digits,
        maximumFractionDigits: digits,
      }).format(value);
const cards = computed(() => {
  const summary = result.value?.summary;
  const delivery = summary?.delivery?.available ? summary.delivery : null;
  return [
    {
      key: 'sent',
      tone: 'blue',
      icon: 'i-lucide-send',
      value: number(delivery?.sent_count),
    },
    {
      key: 'delivered',
      tone: 'teal',
      icon: 'i-lucide-circle-check',
      value: number(delivery?.delivered_count),
    },
    {
      key: 'responses',
      tone: 'iris',
      icon: 'i-lucide-message-circle',
      value: number(summary?.response_count),
    },
    {
      key: 'response_rate',
      tone: 'blue',
      icon: 'i-lucide-target',
      value:
        delivery?.response_rate == null
          ? '—'
          : `${number(delivery.response_rate, 1)}%`,
    },
    {
      key: 'csat',
      tone: 'teal',
      icon: 'i-lucide-star',
      value: summary?.csat == null ? '—' : `${number(summary.csat, 1)} / 5`,
    },
    {
      key: 'nps',
      tone: 'ruby',
      icon: 'i-lucide-gauge',
      value: number(summary?.nps, 1),
    },
  ];
});
const trend = computed(() =>
  (result.value?.summary.trend || []).filter(
    row => row.kind === 'csat' && Number.isFinite(row.average_score)
  )
);
const points = computed(() =>
  trend.value
    .map(
      (row, index) =>
        `${25 + (index * 350) / Math.max(trend.value.length - 1, 1)},${155 - ((row.average_score - 1) / 4) * 130}`
    )
    .join(' ')
);
const totalCsat = computed(() =>
  (result.value?.distribution || []).reduce((sum, row) => sum + row.count, 0)
);
const distribution = computed(() => {
  let offset = 0;
  const colors = ['#dc2626', '#f97316', '#facc15', '#84cc16', '#059669'];
  return [...(result.value?.distribution || [])].reverse().map(row => {
    const length = totalCsat.value ? (row.count / totalCsat.value) * 100 : 0;
    const item = { ...row, length, offset, color: colors[row.score - 1] };
    offset += length;
    return item;
  });
});
const date = value =>
  new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: result.value?.timezone || 'UTC',
  }).format(new Date(value));
</script>

<template>
  <section class="grid gap-4" data-testid="satisfaction-dashboard">
    <Panel
      :title="t('JRC_SERVICE_DESK.SATISFACTION.filters')"
      icon="i-lucide-filter"
    >
      <form
        class="grid items-end gap-3 sm:grid-cols-2 xl:grid-cols-6"
        @submit.prevent="load"
      >
        <label
          v-for="field in ['from', 'to']"
          :key="field"
          class="grid gap-1 text-sm"
          >{{ t(`JRC_SERVICE_DESK.SATISFACTION.${field}`)
          }}<input
            v-model="filters[field]"
            type="date"
            :disabled="busy"
            class="rounded-xl border border-blue-200 bg-n-solid-1 p-2.5"
        /></label>
        <label class="grid gap-1 text-sm"
          >{{ t('JRC_SERVICE_DESK.SATISFACTION.type')
          }}<select
            v-model="filters.type"
            :disabled="busy"
            class="rounded-xl border border-blue-200 bg-n-solid-1 p-2.5"
          >
            <option value="">
              {{ t('JRC_SERVICE_DESK.SATISFACTION.all') }}
            </option>
            <option
              v-for="kind in ['csat', 'nps', 'ces', 'custom']"
              :key="kind"
              :value="kind"
            >
              {{ kind.toUpperCase() }}
            </option>
          </select></label
        >
        <ServiceSelect
          class="min-w-0 [&_select]:w-full [&_.w-fit]:w-full"
          v-model="filters.service_id"
          :unit-id="unitId"
          :disabled="busy"
          :show-refresh="false"
          :general-label="t('JRC_SERVICE_DESK.SATISFACTION.all')"
        />
        <CompanyPicker
          v-if="masterAllowed"
          :model-value="filters.company_id || null"
          :account-id="scope.session.state.context.account_id"
          @update:model-value="
            filters.company_id = $event ? String($event) : ''
          "
        />
        <label class="grid gap-1 text-sm"
          >{{ t('JRC_SERVICE_DESK.SATISFACTION.period_basis')
          }}<select
            v-model="filters.period_basis"
            :disabled="busy"
            class="rounded-xl border border-blue-200 bg-n-solid-1 p-2.5"
          >
            <option value="cohort">
              {{ t('JRC_SERVICE_DESK.SATISFACTION.cohort') }}
            </option>
            <option value="response">
              {{ t('JRC_SERVICE_DESK.SATISFACTION.response_period') }}
            </option>
          </select></label
        >
        <div class="flex flex-wrap gap-2 sm:col-span-2 xl:col-span-6">
          <button
            type="submit"
            :disabled="busy || !scope.allowed.value"
            class="rounded-xl bg-blue-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
          >
            {{ t('JRC_SERVICE_DESK.COMPLETION.load') }}</button
          ><button
            type="button"
            :disabled="
              !result ||
              busy ||
              result.meta.total > 10000 ||
              scope.session.state.context?.capabilities?.surveys?.export !==
                true
            "
            class="rounded-xl border border-blue-200 bg-n-solid-1 px-4 py-2 text-sm font-semibold text-n-blue-11 disabled:opacity-40"
            @click="download"
          >
            {{ t('JRC_SERVICE_DESK.SATISFACTION.export') }}
          </button>
        </div>
      </form>
      <p class="mb-0 mt-3 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.SATISFACTION.basis_help') }}
      </p>
    </Panel>
    <p
      v-if="error"
      role="alert"
      class="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800"
    >
      {{ t(`JRC_SERVICE_DESK.SATISFACTION.${error}`) }}
    </p>
    <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6">
      <article
        v-for="card in cards"
        :key="card.key"
        class="rounded-2xl border border-white/70 bg-gradient-to-br p-4 shadow-sm dark:border-n-weak"
        :class="tones[card.tone].gradient"
      >
        <div class="flex items-center gap-3">
          <span
            :class="[card.icon, tones[card.tone].text]"
            class="size-8 shrink-0"
            aria-hidden="true"
          />
          <div>
            <strong class="block text-2xl" :class="tones[card.tone].text">{{
              card.value
            }}</strong
            ><span class="text-xs font-medium">{{
              t(`JRC_SERVICE_DESK.SATISFACTION.metrics.${card.key}`)
            }}</span>
          </div>
        </div>
      </article>
    </div>
    <p v-if="result" class="m-0 text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.SATISFACTION.delivery_help') }}
      <span v-if="result.summary.delivery.available">{{
        t('JRC_SERVICE_DESK.SATISFACTION.denominator', {
          count: result.summary.delivery.response_denominator,
        })
      }}</span>
    </p>
    <div class="grid items-stretch gap-4 xl:grid-cols-3">
      <Panel
        :title="t('JRC_SERVICE_DESK.SATISFACTION.trend')"
        icon="i-lucide-chart-line"
      >
        <svg
          v-if="trend.length"
          viewBox="0 0 400 180"
          class="w-full text-blue-600"
          role="img"
          :aria-labelledby="`${chartId}-trend`"
        >
          <title :id="`${chartId}-trend`">
            {{ t('JRC_SERVICE_DESK.SATISFACTION.trend') }}
          </title>
          <path d="M25 15V155H380" fill="none" stroke="#b6cbea" />
          <path
            v-for="y in [25, 57.5, 90, 122.5]"
            :key="y"
            :d="`M25 ${y}H380`"
            fill="none"
            stroke="#e0eaff"
          />
          <polyline
            :points="points"
            fill="none"
            stroke="currentColor"
            stroke-width="3"
          />
          <circle
            v-for="(point, index) in points.split(' ')"
            :key="index"
            :cx="point.split(',')[0]"
            :cy="point.split(',')[1]"
            r="3.5"
            fill="currentColor"
          />
        </svg>
        <p v-else class="py-10 text-center text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.SATISFACTION.no_data') }}
        </p>
        <details v-if="trend.length" class="text-xs">
          <summary class="cursor-pointer text-n-blue-11">
            {{ t('JRC_SERVICE_DESK.SATISFACTION.show_data') }}
          </summary>
          <ul>
            <li v-for="row in trend" :key="row.day">
              {{ row.day }} ·
              {{
                t('JRC_SERVICE_DESK.SATISFACTION.scale', {
                  value: number(row.average_score, 2),
                })
              }}
              ·
              {{ row.response_count }}
            </li>
          </ul>
        </details>
      </Panel>
      <Panel
        :title="t('JRC_SERVICE_DESK.SATISFACTION.distribution')"
        icon="i-lucide-chart-pie"
      >
        <div class="flex flex-wrap items-center justify-center gap-3">
          <svg
            viewBox="0 0 120 120"
            class="size-40"
            role="img"
            :aria-labelledby="`${chartId}-distribution`"
          >
            <title :id="`${chartId}-distribution`">
              {{ t('JRC_SERVICE_DESK.SATISFACTION.distribution') }}
            </title>
            <circle
              cx="60"
              cy="60"
              r="43"
              fill="none"
              stroke="#e1eaff"
              stroke-width="15"
            />
            <circle
              v-for="row in distribution"
              :key="row.score"
              cx="60"
              cy="60"
              r="43"
              fill="none"
              :stroke="row.color"
              stroke-width="15"
              pathLength="100"
              :stroke-dasharray="`${row.length} ${100 - row.length}`"
              :stroke-dashoffset="-row.offset"
              transform="rotate(-90 60 60)"
            />
            <text
              x="60"
              y="64"
              text-anchor="middle"
              class="fill-current text-lg font-bold"
            >
              {{ totalCsat }}
            </text>
          </svg>
          <ul class="m-0 grid list-none gap-2 p-0 text-sm">
            <li v-for="row in distribution" :key="row.score">
              {{
                t('JRC_SERVICE_DESK.SATISFACTION.scale', { value: row.score })
              }}
              · {{ row.count }} · {{ number(row.length, 1) }}%
            </li>
          </ul>
        </div>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.SATISFACTION.normalized') }}
        </p>
      </Panel>
      <Panel
        :title="t('JRC_SERVICE_DESK.SATISFACTION.services')"
        icon="i-lucide-wrench"
      >
        <ul v-if="result?.services.length" class="m-0 grid list-none gap-2 p-0">
          <li
            v-for="row in result.services"
            :key="row.service_id"
            class="flex items-center justify-between gap-2 rounded-xl border border-blue-100 bg-blue-50/40 p-3 text-sm dark:border-n-weak dark:bg-n-solid-2"
          >
            <span
              >{{ row.name || t('JRC_SERVICE_DESK.SATISFACTION.unclassified')
              }}<small class="block text-n-slate-11"
                >{{ row.responses }}
                {{
                  t('JRC_SERVICE_DESK.SATISFACTION.metrics.responses')
                }}</small
              ></span
            ><strong
              class="rounded-lg bg-emerald-100 px-2 py-1 text-emerald-900"
              >{{ number(row.csat, 2) }}</strong
            >
          </li>
        </ul>
        <p v-else class="py-10 text-center text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.SATISFACTION.no_data') }}
        </p>
      </Panel>
    </div>
    <Panel
      :title="t('JRC_SERVICE_DESK.SATISFACTION.recent')"
      icon="i-lucide-message-square-text"
    >
      <button
        type="button"
        class="mb-3 rounded-xl border border-blue-200 px-3 py-2 text-sm text-n-blue-11"
        @click="emit('responses')"
      >
        {{ t('JRC_SERVICE_DESK.SATISFACTION.all_responses') }}
      </button>
      <div class="overflow-x-auto">
        <table class="w-full text-start text-sm">
          <thead class="bg-blue-50 dark:bg-n-solid-2">
            <tr>
              <th
                v-for="key in [
                  'date',
                  'company',
                  'ticket',
                  'service',
                  'rating',
                  'comment',
                ]"
                :key="key"
                class="p-3 text-start"
              >
                {{ t(`JRC_SERVICE_DESK.SATISFACTION.columns.${key}`) }}
              </th>
              <th class="p-3">
                <span class="sr-only">{{
                  t('JRC_SERVICE_DESK.SATISFACTION.view')
                }}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in result?.items || []"
              :key="row.id"
              class="border-b border-blue-100 dark:border-n-weak"
            >
              <td class="whitespace-nowrap p-3">
                {{ date(row.responded_at) }}
              </td>
              <td class="p-3">{{ row.company?.name || '—' }}</td>
              <td class="p-3 text-n-blue-11">#{{ row.ticket_number }}</td>
              <td class="p-3">{{ row.service?.name || '—' }}</td>
              <td class="whitespace-nowrap p-3">
                <span
                  v-if="row.kind === 'csat'"
                  aria-hidden="true"
                  class="text-emerald-600"
                  >{{
                    '★'.repeat(
                      Math.min(5, Math.max(0, Math.round(row.score || 0)))
                    )
                  }}</span
                ><span class="block text-xs"
                  >{{ row.kind.toUpperCase() }} {{ number(row.score, 1) }}</span
                >
              </td>
              <td class="max-w-xs truncate p-3">{{ row.comment || '—' }}</td>
              <td class="p-3">
                <button
                  type="button"
                  :aria-label="t('JRC_SERVICE_DESK.SATISFACTION.view')"
                  class="rounded-lg p-2 text-n-blue-11 hover:bg-blue-100"
                  @click="selected = row"
                >
                  <span class="i-lucide-eye block size-4" aria-hidden="true" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p
        v-if="!result?.items.length"
        class="py-5 text-center text-sm text-n-slate-11"
      >
        {{ t('JRC_SERVICE_DESK.SATISFACTION.no_data') }}
      </p>
    </Panel>
    <ReportDialog
      v-if="selected"
      :show-export="false"
      :title="`${t('JRC_SERVICE_DESK.SATISFACTION.view')} — #${selected.ticket_number}`"
      @close="selected = null"
      ><dl class="grid gap-3">
        <dt class="font-semibold">{{ selected.title }}</dt>
        <dd class="m-0">
          {{ selected.kind.toUpperCase() }} · {{ number(selected.score, 2) }}
        </dd>
        <dd class="m-0">{{ date(selected.responded_at) }}</dd>
        <dd class="m-0 whitespace-pre-wrap">{{ selected.comment || '—' }}</dd>
      </dl></ReportDialog
    >
  </section>
</template>
