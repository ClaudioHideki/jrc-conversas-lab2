<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import api from 'dashboard/api/jrcNicoHelpdesk';
import HelpdeskPolicyForm from './HelpdeskPolicyForm.vue';
import HelpdeskKpis from './HelpdeskKpis.vue';
import HelpdeskDailyReport from './HelpdeskDailyReport.vue';
import HelpdeskReportHistory from './HelpdeskReportHistory.vue';
import HelpdeskGroupPreview from './HelpdeskGroupPreview.vue';
import HelpdeskReportFilters from './HelpdeskReportFilters.vue';
import { helpdeskRows, helpdeskValue } from './helpdeskPresentation';
import { buildHelpdeskLabels } from './helpdeskLabels';

const route = useRoute();
const store = useStore();
const { t } = useI18n();
const label = computed(() => buildHelpdeskLabels(t));
const emptyState = () => ({
  catalog: [],
  policies: [],
  options: {},
  can_manage: false,
});
const state = ref(emptyState());
const events = ref([]);
const approvals = ref([]);
const draft = ref(null);
const ticketId = ref('');
const output = ref(null);
const outputType = ref('');
const history = ref(null);
const historyDetail = ref(null);
const historyPolicyId = ref(null);
const reportFilters = ref({});
const disableReason = ref('');
const noteBodies = ref({});
const taskDrafts = ref({});
const groupEventId = ref(null);
const busy = ref(false);
const error = ref('');
let generation = 0;
const accountId = () => Number(route.params.accountId);
const identity = () =>
  `${accountId()}:${store.getters.getCurrentUserID}:${store.getters.getCurrentRole}`;
const date = value =>
  value ? new Date(value).toLocaleString() : t('JRC_NICO_HELPDESK.NO_DATA');
const value = item => helpdeskValue(item, t('JRC_NICO_HELPDESK.NO_DATA'));
const name = (kind, id) =>
  state.value.options?.[kind]?.find(item => item.id === id)?.name || value(id);
const names = (kind, ids = []) => ids.map(id => name(kind, id)).join(', ');
function clear() {
  generation += 1;
  state.value = emptyState();
  events.value = [];
  approvals.value = [];
  draft.value = null;
  output.value = null;
  outputType.value = '';
  history.value = null;
  historyDetail.value = null;
  historyPolicyId.value = null;
  reportFilters.value = {};
  noteBodies.value = {};
  taskDrafts.value = {};
  groupEventId.value = null;
  disableReason.value = '';
}
function rows(payload, prefix = '') {
  return helpdeskRows(payload, t('JRC_NICO_HELPDESK.NO_DATA'), prefix);
}
async function refresh() {
  generation += 1;
  output.value = null;
  outputType.value = '';
  history.value = null;
  historyDetail.value = null;
  groupEventId.value = null;
  taskDrafts.value = {};
  noteBodies.value = {};
  const current = generation;
  const id = accountId();
  const operator = identity();
  const [context, eventResponse, approvalResponse] = await Promise.all([
    api.show(id),
    api.events(id),
    api.approvals(id),
  ]);
  if (current !== generation || operator !== identity()) return;
  if (Number(context.data.account_id) !== id)
    throw new Error('Account mismatch');
  state.value = context.data;
  events.value = eventResponse.data.events;
  approvals.value = approvalResponse.data.approvals;
  draft.value ||= context.data.defaults;
}
async function perform(action) {
  const operator = identity();
  busy.value = true;
  error.value = '';
  try {
    await action();
  } catch {
    if (operator === identity()) {
      clear();
      error.value = t('JRC_NICO_HELPDESK.ERROR');
    }
  } finally {
    if (operator === identity()) busy.value = false;
  }
}
async function savePolicy(definition) {
  const operator = identity();
  await api.createPolicy(accountId(), definition);
  if (operator === identity()) await refresh();
}
async function publish(policy) {
  const operator = identity();
  await api.publishPolicy(accountId(), policy);
  if (operator === identity()) await refresh();
}
async function inspect(policy, type) {
  const id = accountId();
  const operator = identity();
  const request = generation;
  const selection = reportFilters.value[policy.id];
  if (selection?.valid === false) return;
  let result;
  if (type === 'simulation')
    result = await api.simulate(id, {
      policy_id: policy.id,
      ticket_id: Number(ticketId.value),
      trigger: 'created',
    });
  if (type === 'kpis')
    result = await api.kpis(
      id,
      policy.id,
      selection?.from || new Date(Date.now() - 30 * 86400000).toISOString(),
      {
        ...(selection?.until ? { until: selection.until } : {}),
        ...(Object.keys(selection?.filters || {}).length
          ? { filters: selection.filters }
          : {}),
      }
    );
  if (type === 'report')
    result = await api.report(id, policy.id, selection?.filters || {});
  if (operator !== identity() || request !== generation) return;
  output.value = result.data;
  outputType.value = type;
}
async function loadHistory(policyId, page = 1) {
  const id = accountId();
  const operator = identity();
  const request = generation;
  history.value = null;
  historyDetail.value = null;
  const result = await api.reports(id, policyId, page);
  if (operator !== identity() || request !== generation) return;
  if (!Array.isArray(result.data.reports) || result.data.page !== page)
    throw new Error('Invalid history response');
  historyPolicyId.value = policyId;
  history.value = result.data;
}
async function selectReport(reportId) {
  const id = accountId();
  const operator = identity();
  const request = generation;
  historyDetail.value = null;
  const result = await api.reportHistory(id, reportId);
  if (operator !== identity() || request !== generation) return;
  if (Number(result.data.id) !== Number(reportId) || !result.data.payload)
    throw new Error('Invalid report response');
  historyDetail.value = result.data;
}
async function decision(approval, approve) {
  const id = accountId();
  const operator = identity();
  if (approve) await api.approve(id, approval);
  else await api.cancel(id, approval);
  if (operator === identity()) await refresh();
}
async function prepare(event, priority) {
  const id = accountId();
  const operator = identity();
  const argumentsValue = priority
    ? event.result.priority_arguments
    : { ticket_id: event.ticket_id, body: noteBodies.value[event.id] };
  await api.prepare(id, {
    event_id: event.id,
    tool: priority ? 'update_service_ticket' : 'add_service_ticket_note',
    arguments: argumentsValue,
  });
  if (operator === identity()) await refresh();
}
function openTask(event) {
  taskDrafts.value[event.id] ||= {
    project_id: '',
    board_column_id: '',
    title: '',
  };
}
async function prepareTask(event) {
  const id = accountId();
  const operator = identity();
  const task = taskDrafts.value[event.id];
  await api.prepare(id, {
    event_id: event.id,
    tool: 'create_project_task',
    arguments: {
      ticket_id: event.ticket_id,
      project_id: Number(task.project_id),
      board_column_id: Number(task.board_column_id),
      title: task.title.trim(),
    },
  });
  if (operator === identity()) await refresh();
}
async function disable(policy) {
  const id = accountId();
  const operator = identity();
  await api.disablePolicy(
    id,
    policy.id,
    disableReason.value,
    crypto.randomUUID()
  );
  if (operator === identity()) {
    disableReason.value = '';
    await refresh();
  }
}
watch(identity, () => {
  clear();
  busy.value = false;
  perform(refresh);
});
onBeforeUnmount(clear);
onMounted(() => perform(refresh));
</script>

<template>
  <main class="flex flex-1 flex-col gap-6 overflow-auto p-6 text-n-slate-12">
    <header class="flex items-center justify-between gap-3">
      <div>
        <h1 class="text-2xl font-semibold">
          {{ $t('JRC_NICO_HELPDESK.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ $t('JRC_NICO_HELPDESK.DESCRIPTION') }}
        </p>
      </div>
      <button
        :disabled="busy"
        class="rounded-lg border border-n-weak px-4 py-2 disabled:opacity-50"
        @click="perform(refresh)"
      >
        {{ $t('JRC_NICO_HELPDESK.REFRESH') }}
      </button>
    </header>
    <p class="rounded-lg bg-n-amber-2 p-4 text-sm">
      {{ $t('JRC_NICO_HELPDESK.DISABLED') }}
    </p>
    <p v-if="error" role="alert" class="text-n-ruby-9">
      {{ error }}
    </p>
    <section class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
      <article
        v-for="group in state.catalog"
        :key="group.key"
        class="rounded-xl border border-n-weak p-4"
      >
        <h2 class="font-semibold">{{ group.key }} {{ group.name }}</h2>
        <p class="mt-2 text-sm">
          {{ label('catalog', group.status) }}
        </p>
        <p class="mt-2 text-xs text-n-slate-11">
          {{
            $t('JRC_NICO_HELPDESK.PHASE_HANDOFF', {
              phase: group.phase,
              handoff: group.human_handoff,
            })
          }}
        </p>
        <details v-if="group.missing.length" class="mt-2 text-xs">
          <summary>
            {{ $t('JRC_NICO_HELPDESK.DEPENDENCIES') }}
          </summary>
          <ul class="mt-2 list-inside list-disc">
            <li v-for="dependency in group.missing" :key="dependency">
              {{ dependency }}
            </li>
          </ul>
        </details>
      </article>
    </section>
    <section
      v-if="state.can_manage && draft"
      class="rounded-xl border border-n-weak p-4"
    >
      <h2 class="mb-4 text-lg font-semibold">
        {{ $t('JRC_NICO_HELPDESK.POLICY') }}
      </h2>
      <HelpdeskPolicyForm
        :definition="draft"
        :options="state.options"
        :busy="busy"
        @save="definition => perform(() => savePolicy(definition))"
      />
    </section>
    <section class="rounded-xl border border-n-weak p-4">
      <h2 class="mb-3 text-lg font-semibold">
        {{ $t('JRC_NICO_HELPDESK.VERSIONS') }}
      </h2>
      <label v-if="state.can_manage" class="mb-3 block text-sm">
        <span>
          {{ $t('JRC_NICO_HELPDESK.TICKET_ID') }}
        </span>
        <input
          v-model="ticketId"
          type="number"
          min="1"
          class="ml-3 rounded-lg border border-n-weak bg-n-background p-2"
        />
      </label>
      <label v-if="state.can_manage" class="mb-3 block text-sm">
        <span>
          {{ $t('JRC_NICO_HELPDESK.DISABLE_REASON') }}
        </span>
        <input
          v-model="disableReason"
          maxlength="1000"
          class="mt-1 block w-full rounded-lg border border-n-weak bg-n-background p-2"
        />
      </label>
      <article
        v-for="policy in state.policies"
        :key="policy.id"
        class="mb-3 rounded-lg bg-n-alpha-1 p-4"
      >
        <h3 class="font-medium">
          {{ $t('JRC_NICO_HELPDESK.VERSION', { number: policy.number }) }}
          {{ label('states', policy.halted ? 'halted' : policy.state) }}
        </h3>
        <dl
          v-if="policy.definition"
          class="mt-2 grid gap-2 text-sm md:grid-cols-2"
        >
          <div>
            <dt class="text-n-slate-11">
              {{ $t('JRC_NICO_HELPDESK.COMPANIES') }}
            </dt>
            <dd>
              {{
                names('companies', policy.definition.company_ids) ||
                $t('JRC_NICO_HELPDESK.EMPTY')
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ $t('JRC_NICO_HELPDESK.UNITS') }}
            </dt>
            <dd>
              {{
                names('units', policy.definition.unit_ids) ||
                $t('JRC_NICO_HELPDESK.EMPTY')
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ $t('JRC_NICO_HELPDESK.OPERATORS') }}
            </dt>
            <dd>
              {{
                names('operators', policy.definition.operator_ids) ||
                $t('JRC_NICO_HELPDESK.EMPTY')
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ $t('JRC_NICO_HELPDESK.HOURLY_LIMIT') }}
            </dt>
            <dd>
              {{ policy.definition.hourly_limit }}
            </dd>
          </div>
        </dl>
        <HelpdeskReportFilters
          :key="`${identity()}:${policy.id}:${generation}`"
          :policy="policy"
          :options="state.options"
          :busy="busy"
          @change="settings => (reportFilters[policy.id] = settings)"
        />
        <div class="mt-3 flex flex-wrap gap-3">
          <button
            v-if="state.can_manage && policy.state === 'draft'"
            :disabled="busy"
            class="rounded border border-n-weak px-3 py-1"
            @click="perform(() => publish(policy))"
          >
            {{ $t('JRC_NICO_HELPDESK.PUBLISH') }}
          </button>
          <button
            v-if="state.can_manage && policy.definition"
            :disabled="busy"
            class="rounded border border-n-weak px-3 py-1"
            @click="draft = JSON.parse(JSON.stringify(policy.definition))"
          >
            {{ $t('JRC_NICO_HELPDESK.COPY_VERSION') }}
          </button>
          <button
            v-if="state.can_manage"
            :disabled="busy || !ticketId"
            class="rounded border border-n-weak px-3 py-1"
            @click="perform(() => inspect(policy, 'simulation'))"
          >
            {{ $t('JRC_NICO_HELPDESK.SIMULATE') }}
          </button>
          <button
            :data-testid="`helpdesk-kpis-policy-${policy.id}`"
            :disabled="busy || reportFilters[policy.id]?.valid === false"
            class="rounded border border-n-weak px-3 py-1"
            @click="perform(() => inspect(policy, 'kpis'))"
          >
            {{ $t('JRC_NICO_HELPDESK.KPIS') }}
          </button>
          <button
            :data-testid="`helpdesk-preview-policy-${policy.id}`"
            :disabled="busy || reportFilters[policy.id]?.valid === false"
            class="rounded border border-n-weak px-3 py-1"
            @click="perform(() => inspect(policy, 'report'))"
          >
            {{ $t('JRC_NICO_HELPDESK.REPORT') }}
          </button>
          <button
            :disabled="busy"
            :data-testid="`helpdesk-history-policy-${policy.id}`"
            class="rounded border border-n-weak px-3 py-1"
            @click="perform(() => loadHistory(policy.id))"
          >
            {{ $t('JRC_NICO_HELPDESK.REPORT_HISTORY') }}
          </button>
          <button
            v-if="
              state.can_manage && policy.state === 'published' && !policy.halted
            "
            :disabled="busy || !disableReason.trim()"
            class="rounded border border-n-ruby-8 px-3 py-1 text-n-ruby-11"
            @click="perform(() => disable(policy))"
          >
            {{ $t('JRC_NICO_HELPDESK.DISABLE') }}
          </button>
        </div>
      </article>
    </section>
    <section class="overflow-auto rounded-xl border border-n-weak p-4">
      <h2 class="mb-3 text-lg font-semibold">
        {{ $t('JRC_NICO_HELPDESK.EVENTS') }}
      </h2>
      <p v-if="!events.length" class="text-sm text-n-slate-11">
        {{ $t('JRC_NICO_HELPDESK.EMPTY') }}
      </p>
      <table v-else class="w-full text-left text-sm">
        <thead>
          <tr>
            <th class="p-2">
              {{ $t('JRC_NICO_HELPDESK.RULES') }}
            </th>
            <th class="p-2">
              {{ $t('JRC_NICO_HELPDESK.TICKET') }}
            </th>
            <th class="p-2">
              {{ $t('JRC_NICO_HELPDESK.STATE') }}
            </th>
            <th class="p-2">
              {{ $t('JRC_NICO_HELPDESK.EVIDENCE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="event in events"
            :key="event.id"
            class="border-t border-n-weak"
          >
            <td class="p-2">
              {{ event.rule_key }}
              {{ label('rules', event.rule_key) }}
            </td>
            <td class="p-2">
              <router-link
                :to="{
                  name: 'jrc_service_desk_detail',
                  params: { accountId: accountId(), ticketId: event.ticket_id },
                }"
              >
                {{ event.ticket_id }}
              </router-link>
            </td>
            <td class="p-2">
              {{ label('states', event.state) }}
              <p class="text-xs text-n-slate-11">
                {{ date(event.detected_at) }}
              </p>
            </td>
            <td class="p-2">
              <dl>
                <div
                  v-for="row in rows(event.evidence)"
                  :key="row.field"
                  class="mb-1"
                >
                  <dt class="text-xs text-n-slate-11">
                    {{ row.field }}
                  </dt>
                  <dd>
                    {{ row.value }}
                  </dd>
                </div>
              </dl>
              <button
                class="mt-3 rounded border border-n-weak px-3 py-1"
                :disabled="busy"
                :data-group-event="event.id"
                @click="
                  groupEventId = groupEventId === event.id ? null : event.id
                "
              >
                {{ $t('JRC_NICO_HELPDESK.GROUP_PREVIEW') }}
              </button>
              <HelpdeskGroupPreview
                v-if="groupEventId === event.id"
                :key="`${identity()}:${event.id}`"
                :account-id="accountId()"
                :event="event"
                :catalog="state.catalog"
                :context-key="identity()"
                @prepared="perform(refresh)"
                @revoked="perform(refresh)"
              />
              <div v-if="event.state === 'prepared'" class="mt-3 space-y-3">
                <div
                  v-if="event.result?.tools?.includes('create_project_task')"
                >
                  <button
                    :disabled="busy"
                    class="rounded border border-n-weak px-3 py-1"
                    :data-task-event="event.id"
                    @click="openTask(event)"
                  >
                    {{ $t('JRC_NICO_HELPDESK.TASK_PREPARE') }}
                  </button>
                  <form
                    v-if="taskDrafts[event.id]"
                    class="mt-3 space-y-3"
                    :data-task-form="event.id"
                    @submit.prevent="perform(() => prepareTask(event))"
                  >
                    <label class="block text-xs"
                      >{{ $t('JRC_NICO_HELPDESK.TASK_PROJECT')
                      }}<input
                        v-model="taskDrafts[event.id].project_id"
                        type="number"
                        min="1"
                        required
                        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
                        name="project_id"
                    /></label>
                    <label class="block text-xs"
                      >{{ $t('JRC_NICO_HELPDESK.TASK_COLUMN')
                      }}<input
                        v-model="taskDrafts[event.id].board_column_id"
                        type="number"
                        min="1"
                        required
                        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
                        name="board_column_id"
                    /></label>
                    <label class="block text-xs"
                      >{{ $t('JRC_NICO_HELPDESK.TASK_TITLE')
                      }}<input
                        v-model="taskDrafts[event.id].title"
                        maxlength="255"
                        required
                        class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
                        name="title"
                    /></label>
                    <button
                      :disabled="busy || !taskDrafts[event.id].title.trim()"
                      type="submit"
                      class="rounded border border-n-weak px-3 py-1"
                    >
                      {{ $t('JRC_NICO_HELPDESK.PREPARE') }}
                    </button>
                  </form>
                </div>
                <div v-if="event.result?.priority_arguments">
                  <p class="mb-2 text-xs">
                    {{ $t('JRC_NICO_HELPDESK.PREPARE_PRIORITY') }}
                    {{
                      name(
                        'priorities',
                        event.result.priority_arguments.priority_id
                      )
                    }}
                  </p>
                  <button
                    :disabled="busy"
                    class="rounded border border-n-weak px-3 py-1"
                    @click="perform(() => prepare(event, true))"
                  >
                    {{ $t('JRC_NICO_HELPDESK.PREPARE') }}
                  </button>
                </div>
                <div
                  v-if="
                    event.result?.tools?.includes('add_service_ticket_note')
                  "
                >
                  <label class="block text-xs">
                    {{ $t('JRC_NICO_HELPDESK.INTERNAL_NOTE') }}
                    <textarea
                      v-model="noteBodies[event.id]"
                      maxlength="4000"
                      rows="3"
                      class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
                    />
                  </label>
                  <button
                    :disabled="busy || !noteBodies[event.id]?.trim()"
                    class="mt-2 rounded border border-n-weak px-3 py-1"
                    @click="perform(() => prepare(event, false))"
                  >
                    {{ $t('JRC_NICO_HELPDESK.PREPARE') }}
                  </button>
                </div>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </section>
    <section class="rounded-xl border border-n-weak p-4">
      <h2 class="mb-3 text-lg font-semibold">
        {{ $t('JRC_NICO_HELPDESK.APPROVALS') }}
      </h2>
      <p v-if="!approvals.length" class="text-sm text-n-slate-11">
        {{ $t('JRC_NICO_HELPDESK.EMPTY') }}
      </p>
      <article
        v-for="approval in approvals"
        :key="approval.id"
        class="mb-4 rounded-lg bg-n-alpha-1 p-4"
      >
        <h3 class="font-medium">
          {{ approval.tool }}
          {{ label('states', approval.state) }}
        </h3>
        <dl class="mt-3 grid gap-3 text-sm md:grid-cols-3">
          <div>
            <dt class="text-n-slate-11">
              {{ $t('JRC_NICO_HELPDESK.COMPANIES') }}
            </dt>
            <dd>
              {{ name('companies', approval.scope.company_id) }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ $t('JRC_NICO_HELPDESK.UNITS') }}
            </dt>
            <dd>
              {{ name('units', approval.scope.unit_id) }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ $t('JRC_NICO_HELPDESK.EXPIRES') }}
            </dt>
            <dd>
              {{ date(approval.expires_at) }}
            </dd>
          </div>
        </dl>
        <table class="mt-3 w-full text-left text-sm">
          <tbody>
            <tr
              v-for="row in rows(approval.arguments)"
              :key="row.field"
              class="border-t border-n-weak"
            >
              <th class="p-2 font-medium">
                {{ row.field }}
              </th>
              <td class="whitespace-pre-wrap p-2">
                {{ row.value }}
              </td>
            </tr>
          </tbody>
        </table>
        <p
          v-if="approval.state === 'unknown'"
          class="mt-2 text-sm text-n-amber-11"
        >
          {{ $t('JRC_NICO_HELPDESK.UNKNOWN_RESULT') }}
        </p>
        <details class="mt-3 text-xs">
          <summary>
            {{ $t('JRC_NICO_HELPDESK.PAYLOAD_DIGEST') }}
          </summary>
          <p class="mt-2 break-all font-mono">
            {{ approval.payload_digest }}
          </p>
        </details>
        <div v-if="approval.state === 'pending'" class="mt-3 flex gap-3">
          <button
            :disabled="busy || Date.parse(approval.expires_at) <= Date.now()"
            class="rounded bg-n-brand px-3 py-2 text-white disabled:opacity-50"
            @click="perform(() => decision(approval, true))"
          >
            {{ $t('JRC_NICO_HELPDESK.APPROVE') }}
          </button>
          <button
            :disabled="busy"
            class="rounded border border-n-weak px-3 py-2"
            @click="perform(() => decision(approval, false))"
          >
            {{ $t('JRC_NICO_HELPDESK.CANCEL') }}
          </button>
        </div>
      </article>
    </section>
    <HelpdeskKpis v-if="outputType === 'kpis' && output" :report="output" />
    <HelpdeskDailyReport
      v-if="outputType === 'report' && output"
      :report="output"
      :options="state.options"
    />
    <HelpdeskReportHistory
      v-if="history"
      :history="history"
      :detail="historyDetail"
      :options="state.options"
      :busy="busy"
      @select="id => perform(() => selectReport(id))"
      @next="page => perform(() => loadHistory(historyPolicyId, page))"
    />
    <section
      v-if="outputType === 'simulation' && output"
      class="rounded-xl border border-n-weak p-4"
    >
      <h2 class="mb-3 font-semibold">
        {{ $t('JRC_NICO_HELPDESK.SIMULATE') }}
      </h2>
      <p class="mb-3 text-sm">
        {{ $t('JRC_NICO_HELPDESK.SIMULATION_ONLY') }}
      </p>
      <article
        v-for="result in output.decisions"
        :key="result.rule_key"
        class="mb-3"
      >
        <h3 class="font-medium">
          {{ result.rule_key }}
          {{ label('rules', result.rule_key) }}
        </h3>
        <dl>
          <div
            v-for="row in rows(result.evidence)"
            :key="row.field"
            class="mt-2 text-sm"
          >
            <dt class="text-n-slate-11">
              {{ row.field }}
            </dt>
            <dd>
              {{ row.value }}
            </dd>
          </div>
        </dl>
      </article>
      <p v-if="!output.decisions.length">
        {{ $t('JRC_NICO_HELPDESK.EMPTY') }}
      </p>
    </section>
  </main>
</template>
