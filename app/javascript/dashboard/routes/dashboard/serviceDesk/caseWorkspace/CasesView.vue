<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskCases';
import ScopeBar from '../components/ScopeBar.vue';
import Lookup from '../components/LookupSelect.vue';
import ServiceSelect from '../components/ServiceDefinitionSelect.vue';
import CaseWorkspace from './CaseWorkspace.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { serviceDeskRouteName } from '../routeDefinitions';
import { canonicalId } from '../helpers/access';
import {
  list as decodeList,
  formatElapsed,
  STATES,
  SEVERITIES,
  TONES,
  mayDrop,
} from './rules';
const props = defineProps({ screen: { type: String, required: true } });
const session = useServiceDesk();
const route = useRoute();
const router = useRouter();
const { t, locale } = useI18n();
const tr = (key, values) => t(`JRC_SERVICE_DESK.CASES.${key}`, values);
const kind = computed(() =>
  props.screen === 'problems' ? 'problem' : 'incident'
);
const unitId = ref(canonicalId(route.query.unit_id) || '');
const operatorId = ref(canonicalId(route.query.operator_company_id) || '');
const page = ref(1);
const query = ref(
  typeof route.query.query === 'string' ? route.query.query.slice(0, 200) : ''
);
const status = ref(
  STATES.includes(route.query.status) ? route.query.status : ''
);
const severity = ref(
  SEVERITIES.includes(route.query.severity) ? route.query.severity : ''
);
const requesterId = ref('');
const source = ref('');
const ownerId = ref('');
const serviceId = ref('');
const from = ref('');
const to = ref('');
const view = ref(
  route.query.view === 'kanban' && kind.value === 'incident' ? 'kanban' : 'list'
);
const result = ref(null);
const loading = ref(false);
const error = ref('');
const modal = ref(false);
const selectedId = ref('');
const selectedUnit = ref('');
const initialTarget = ref('');
const dragging = ref('');
let generation = 0;
let controller;
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.[props.screen]?.index === true
);
const identity = computed(() =>
  JSON.stringify([
    session.state.status,
    session.state.context?.account_id,
    session.state.context?.user_id,
    session.state.context?.units,
    session.state.context?.capabilities,
  ])
);
const pages = computed(() =>
  Math.max(1, Math.ceil((result.value?.meta.total || 0) / 20))
);
const stamp = value =>
  value
    ? new Date(value).toLocaleString(
        (locale?.value || 'pt-BR').replace('_', '-')
      )
    : tr('not_defined');
const metricRows = computed(() =>
  result.value
    ? [
        ['total', result.value.metrics.total, 'blue'],
        ['critical', result.value.metrics.critical, 'ruby'],
        ['active', result.value.metrics.active, 'amber'],
        ['resolved', result.value.metrics.resolved, 'teal'],
        ['closed', result.value.metrics.closed, 'violet'],
        [
          'average',
          formatElapsed(result.value.metrics.resolution_average_seconds) ||
            tr('unavailable'),
          'blue',
        ],
      ]
    : []
);
const metricTones = {
  blue: 'bg-n-blue-2 text-n-blue-11',
  ruby: 'bg-n-ruby-2 text-n-ruby-11',
  amber: 'bg-n-amber-2 text-n-amber-11',
  teal: 'bg-n-teal-2 text-n-teal-11',
  violet: 'bg-n-violet-2 text-n-violet-11',
};
function filters() {
  return {
    kind: kind.value,
    unit_id: unitId.value,
    operator_company_id: operatorId.value,
    query: query.value,
    status: status.value,
    severity: severity.value,
    requester_id: requesterId.value,
    source: source.value,
    owner_account_user_id: ownerId.value,
    service_id: serviceId.value,
    created_from: from.value,
    created_to: to.value,
    page: page.value,
    per_page: 20,
  };
}
function syncRoute() {
  const values = filters();
  const next = Object.fromEntries(
    Object.entries({ ...values, view: view.value }).filter(
      ([key, value]) => !['kind', 'per_page'].includes(key) && value !== ''
    )
  );
  router.replace({ name: route.name, params: route.params, query: next });
}
async function load() {
  generation += 1;
  const turn = generation;
  controller?.abort();
  controller = new AbortController();
  result.value = null;
  error.value = '';
  if (!allowed.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  const context = session.state.context;
  try {
    const data = await API.list(
      context.account_id,
      filters(),
      controller.signal
    );
    if (turn !== generation || context !== session.state.context) return;
    result.value = decodeList(data, context, kind.value);
  } catch {
    if (turn === generation) error.value = tr('error');
  } finally {
    if (turn === generation) loading.value = false;
  }
}
function search() {
  page.value = 1;
  syncRoute();
  load();
}
function reset() {
  query.value = '';
  status.value = '';
  severity.value = '';
  ownerId.value = '';
  requesterId.value = '';
  source.value = '';
  serviceId.value = '';
  from.value = '';
  to.value = '';
  search();
}
function open(row, target = '') {
  selectedId.value = row?.id || '';
  selectedUnit.value = row?.unit_id || unitId.value;
  initialTarget.value = target;
  if (!selectedUnit.value) return;
  modal.value = true;
}
function navigate(row) {
  modal.value = false;
  router.push({
    name: serviceDeskRouteName(
      row.resource_kind === 'problem' ? 'problems' : 'incidents'
    ),
    params: { accountId: row.account_id },
    query: { unit_id: row.unit_id, case_id: row.id },
  });
}
function closeModal() {
  modal.value = false;
  selectedId.value = '';
  initialTarget.value = '';
  if (route.query.case_id) {
    const next = { ...route.query };
    delete next.case_id;
    router.replace({ name: route.name, params: route.params, query: next });
  }
}
function drop(target) {
  const row = result.value?.items.find(item => item.id === dragging.value);
  dragging.value = '';
  if (mayDrop(row, target)) open(row, target);
}
watch(
  [identity, () => props.screen],
  () => {
    modal.value = false;
    selectedId.value = '';
    result.value = null;
    if (session.state.context?.units.length === 1 && !unitId.value)
      unitId.value = session.state.context.units[0].id;
    if (kind.value === 'problem') view.value = 'list';
    page.value = 1;
    load();
  },
  { immediate: true }
);
watch([unitId, operatorId], () => {
  page.value = 1;
  ownerId.value = '';
  requesterId.value = '';
  source.value = '';
  serviceId.value = '';
  modal.value = false;
  load();
});
watch(page, () => {
  syncRoute();
  load();
});
watch(
  [() => route.query.case_id, identity, () => props.screen],
  () => {
    const id = canonicalId(route.query.case_id);
    const unit = canonicalId(route.query.unit_id);
    if (
      id &&
      unit &&
      allowed.value &&
      session.state.context.units.some(item => item.id === unit)
    )
      open({ id, unit_id: unit });
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <div class="min-w-0 space-y-4">
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold">{{ tr(screen) }}</h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{
            tr(kind === 'problem' ? 'subtitle_problem' : 'subtitle_incident')
          }}
        </p>
      </div>
      <button
        type="button"
        class="rounded-xl bg-n-blue-9 px-4 py-3 text-sm font-medium text-white disabled:opacity-40"
        :disabled="!allowed || !unitId"
        @click="open(null)"
      >
        + {{ tr(kind === 'problem' ? 'new_problem' : 'new_incident') }}
      </button>
    </header>
    <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
      <ScopeBar
        v-model:unit-id="unitId"
        v-model:operator-id="operatorId"
      />
      <p
        v-if="!unitId"
        class="text-xs text-n-amber-11"
      >
        {{ tr('select_unit') }}
      </p>
      <form
        class="mt-3 grid gap-3 md:grid-cols-[minmax(0,1fr)_160px_150px_auto]"
        @submit.prevent="search"
      >
        <input
          v-model="query"
          maxlength="200"
          :aria-label="tr('search')"
          :placeholder="tr('search_placeholder')"
          class="min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
        />
        <select
          v-model="status"
          :aria-label="tr('status')"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
        >
          <option value="">{{ tr('status') }}: {{ tr('all') }}</option>
          <option
            v-for="value in STATES"
            :key="value"
            :value="value"
          >
            {{ tr(`state_values.${value}`) }}
          </option>
        </select>
        <select
          v-model="severity"
          :aria-label="tr('severity')"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
        >
          <option value="">{{ tr('priority') }}: {{ tr('all') }}</option>
          <option
            v-for="value in SEVERITIES"
            :key="value"
            :value="value"
          >
            {{ tr(`severity_values.${value}`) }}
          </option>
        </select>
        <button
          type="submit"
          class="rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white"
        >
          {{ tr('apply') }}
        </button>
      </form>
      <details class="mt-3">
        <summary class="cursor-pointer text-xs text-n-blue-11">
          {{ tr('advanced_filters') }}
        </summary>
        <div class="mt-4 grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Lookup
            v-model="ownerId"
            :label="tr('owner')"
            resource="assignees"
            :unit-id="unitId"
          />
          <ServiceSelect
            v-model="serviceId"
            :unit-id="unitId"
          />
          <Lookup
            v-model="requesterId"
            :label="tr('customer_filter')"
            resource="requesters"
            :unit-id="unitId"
          />
          <label class="grid gap-2 text-xs">
            {{ tr('source_filter') }}
            <select
              v-model="source"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
            >
              <option value="">{{ tr('all') }}</option>
              <option
                v-for="value in [
                  'manual',
                  'conversation',
                  'whatsapp',
                  'email',
                  'phone',
                  'portal',
                  'api',
                ]"
                :key="value"
                :value="value"
              >
                {{ tr(`sources.${value}`) }}
              </option>
            </select>
          </label>
          <label class="grid gap-2 text-xs">
            {{ tr('from') }}
            <input
              v-model="from"
              type="date"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
            />
          </label>
          <label class="grid gap-2 text-xs">
            {{ tr('to') }}
            <input
              v-model="to"
              type="date"
              class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
            />
          </label>
        </div>
      </details>
      <div
        class="mt-3 flex flex-wrap items-center justify-between gap-3 text-xs"
      >
        <button
          type="button"
          class="text-n-blue-11"
          @click="reset"
        >
          {{ tr('reset') }}
        </button>
        <div
          v-if="kind === 'incident'"
          class="flex gap-2"
        >
          <button
            v-for="value in ['list', 'kanban']"
            :key="value"
            type="button"
            class="rounded-lg px-3 py-2"
            :class="
              view === value
                ? 'bg-n-blue-9 text-white'
                : 'bg-n-blue-2 text-n-blue-11'
            "
            :aria-pressed="view === value"
            @click="
              view = value;
              syncRoute();
            "
          >
            {{ tr(value) }}
          </button>
        </div>
      </div>
    </div>
    <p
      v-if="!allowed"
      role="alert"
      class="rounded-xl bg-n-amber-2 p-4"
    >
      {{ tr('denied') }}
    </p>
    <p
      v-else-if="loading"
      role="status"
      class="p-8 text-center"
    >
      {{ tr('loading') }}
    </p>
    <div
      v-else-if="error"
      role="alert"
      class="rounded-xl bg-n-ruby-2 p-4"
    >
      <p>{{ error }}</p>
      <button
        type="button"
        class="mt-2 underline"
        @click="load"
      >
        {{ tr('refresh') }}
      </button>
    </div>
    <template v-if="result">
      <div
        v-if="kind === 'incident'"
        class="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-6"
      >
        <div
          v-for="[name, value, tone] in metricRows"
          :key="name"
          class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <p class="text-xs text-n-slate-11">{{ tr(name) }}</p>
          <p
            class="mt-3 inline-block rounded-lg px-3 py-1 text-xl font-semibold"
            :class="metricTones[tone]"
          >
            {{ value }}
          </p>
          <p
            v-if="name === 'average'"
            class="mt-2 text-xs text-n-slate-11"
          >
            {{ tr('sample', { count: result.metrics.resolution_sample_size }) }}
          </p>
        </div>
      </div>
      <p
        v-if="kind === 'incident'"
        class="text-xs text-n-slate-11"
      >
        {{ tr('metrics_note') }} {{ tr('average_help') }}
      </p>
      <div
        v-if="kind === 'incident'"
        class="grid gap-4 md:grid-cols-2"
      >
        <section
          v-for="[field, label, values] in [
            ['by_status', 'status_distribution', STATES],
            ['by_severity', 'severity_distribution', SEVERITIES],
          ]"
          :key="field"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <h2 class="mb-3 text-sm font-semibold">{{ tr(label) }}</h2>
          <div
            v-for="value in values"
            :key="value"
            class="mb-2 grid grid-cols-[120px_1fr_32px] items-center gap-2 text-xs"
          >
            <span>
              {{
                tr(
                  `${field === 'by_status' ? 'state_values' : 'severity_values'}.${value}`
                )
              }}
            </span>
            <meter
              class="h-3 w-full"
              :value="result.metrics[field][value] || 0"
              :max="Math.max(1, result.meta.total)"
              :aria-label="
                tr(
                  `${field === 'by_status' ? 'state_values' : 'severity_values'}.${value}`
                )
              "
            />
            <span class="text-right">
              {{ result.metrics[field][value] || 0 }}
            </span>
          </div>
        </section>
      </div>
      <p
        v-if="!result.items.length"
        class="rounded-xl border border-n-weak p-8 text-center text-sm"
      >
        {{ tr('empty') }}
      </p>
      <template v-else-if="view === 'list'">
        <div
          class="hidden overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1 md:block"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-n-blue-2 text-xs text-n-blue-11">
              <tr>
                <th
                  v-for="key in [
                    'code',
                    'title',
                    'status',
                    'priority',
                    'owner',
                    'started',
                  ]"
                  :key="key"
                  class="p-3"
                >
                  {{ tr(key) }}
                </th>
                <th class="p-3" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in result.items"
                :key="row.id"
                class="border-t border-n-weak"
              >
                <td class="p-3">
                  <button
                    type="button"
                    class="font-semibold text-n-blue-11"
                    @click="open(row)"
                  >
                    {{ row.code }}
                  </button>
                </td>
                <td class="max-w-xs p-3">
                  <button
                    type="button"
                    class="break-words text-left"
                    @click="open(row)"
                  >
                    {{ row.title }}
                  </button>
                  <p class="mt-1 text-xs text-n-slate-11">
                    {{ row.unit?.name }}
                  </p>
                </td>
                <td class="p-3">
                  <span
                    class="inline-block rounded-full px-2 py-1 text-xs"
                    :class="TONES[row.status]"
                  >
                    {{ tr(`state_values.${row.status}`) }}
                  </span>
                </td>
                <td class="p-3">
                  <span
                    class="inline-block rounded-full px-2 py-1 text-xs"
                    :class="TONES[row.severity]"
                  >
                    {{ tr(`severity_values.${row.severity}`) }}
                  </span>
                </td>
                <td class="p-3 text-xs">
                  {{ row.owner_name || tr('not_defined') }}
                </td>
                <td class="p-3 text-xs">{{ stamp(row.started_at) }}</td>
                <td class="p-3">
                  <button
                    type="button"
                    class="rounded-lg border px-3 py-2 text-xs"
                    @click="open(row)"
                  >
                    {{ tr('open') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="grid gap-3 md:hidden">
          <button
            v-for="row in result.items"
            :key="row.id"
            type="button"
            class="rounded-xl border border-n-weak bg-n-solid-1 p-4 text-left"
            @click="open(row)"
          >
            <p class="text-xs font-semibold text-n-blue-11">{{ row.code }}</p>
            <p class="mt-2 break-words text-sm font-medium">{{ row.title }}</p>
            <div class="mt-3 flex flex-wrap gap-2 text-xs">
              <span
                class="rounded-full px-2 py-1"
                :class="TONES[row.status]"
              >
                {{ tr(`state_values.${row.status}`) }}
              </span>
              <span
                class="rounded-full px-2 py-1"
                :class="TONES[row.severity]"
              >
                {{ tr(`severity_values.${row.severity}`) }}
              </span>
            </div>
            <p class="mt-3 text-xs text-n-slate-11">
              {{ row.owner_name || tr('not_defined') }}
            </p>
          </button>
        </div>
      </template>
      <template v-else>
        <p class="text-xs text-n-slate-11">{{ tr('page_cards') }}</p>
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <section
            v-for="state in STATES"
            :key="state"
            class="min-h-32 min-w-0 rounded-xl border border-n-weak p-3"
            :class="TONES[state]"
            @dragover.prevent
            @drop.prevent="drop(state)"
          >
            <h3 class="mb-3 flex justify-between gap-2 text-xs font-semibold">
              <span>{{ tr(`state_values.${state}`) }}</span>
              <span>{{ result.metrics.by_status[state] || 0 }}</span>
            </h3>
            <button
              v-for="row in result.items.filter(item => item.status === state)"
              :key="row.id"
              type="button"
              class="mb-3 block w-full rounded-xl border border-n-weak bg-n-solid-1 p-3 text-left text-n-slate-12 shadow-sm"
              :draggable="row.allowed_transitions.length > 0"
              @dragstart="
                dragging = row.id;
                $event.dataTransfer.setData('text/plain', row.id);
              "
              @dragend="dragging = ''"
              @click="open(row)"
            >
              <p class="text-xs text-n-blue-11">{{ row.code }}</p>
              <p class="mt-2 break-words text-sm font-medium">
                {{ row.title }}
              </p>
              <span
                class="mt-3 inline-block rounded-full px-2 py-1 text-xs"
                :class="TONES[row.severity]"
              >
                {{ tr(`severity_values.${row.severity}`) }}
              </span>
              <p class="mt-3 text-xs text-n-slate-11">
                {{ row.owner_name || tr('not_defined') }}
              </p>
            </button>
          </section>
        </div>
      </template>
      <footer
        class="flex flex-wrap items-center justify-between gap-3 py-3 text-xs"
      >
        <span>{{ tr('count', { count: result.meta.total }) }}</span>
        <div class="flex items-center gap-3">
          <button
            type="button"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 disabled:opacity-40"
            :disabled="page <= 1 || loading"
            @click="page -= 1"
          >
            {{ tr('previous') }}
          </button>
          <span>{{ tr('page', { page, pages }) }}</span>
          <button
            type="button"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 disabled:opacity-40"
            :disabled="page >= pages || loading"
            @click="page += 1"
          >
            {{ tr('next') }}
          </button>
        </div>
      </footer>
    </template>
    <CaseWorkspace
      v-if="modal"
      :key="`${kind}:${selectedUnit}:${selectedId}`"
      :kind="kind"
      :unit-id="selectedUnit"
      :record-id="selectedId"
      :initial-target="initialTarget"
      @close="closeModal"
      @saved="load"
      @navigate="navigate"
    />
  </div>
</template>
