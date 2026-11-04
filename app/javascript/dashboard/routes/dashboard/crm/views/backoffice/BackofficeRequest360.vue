<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
import { moduleTabClasses } from 'dashboard/components-next/navigation/moduleTabClasses';
import { stageTones, money } from './backofficeVisuals';
import BackofficeRequestSummary from './BackofficeRequestSummary.vue';
import BackofficeAssignment from './BackofficeAssignment.vue';
import BackofficeActions from './BackofficeActions.vue';
import BackofficeDocumentVersions from './BackofficeDocumentVersions.vue';
import BackofficeContractPanel from './BackofficeContractPanel.vue';
import BackofficeFinance from './BackofficeFinance.vue';
import BackofficeCompletionReport from './BackofficeCompletionReport.vue';
import ApprovalGateBadge from 'dashboard/routes/dashboard/approvals/ApprovalGateBadge.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

const route = useRoute();
const store = useStore();
const { text, label, date, slaLabel } = useBackofficePresentation();
const record = ref(null);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const message = ref('');
const tabs = [
  'operations',
  'context',
  'documents',
  'contracts',
  'checklist',
  'issues',
  'finance',
  'history',
];
const tab = ref(
  tabs.includes(route.query.tab) ? route.query.tab : 'operations'
);
const historyPage = ref(1);
const startIssue = ref(false);
const tabTones = {
  operations: 'blue',
  context: 'cyan',
  documents: 'amber',
  contracts: 'blue',
  checklist: 'teal',
  issues: 'rose',
  finance: 'violet',
  history: 'blue',
};
let sequence = 0;
const terminal = computed(() =>
  ['completed', 'canceled', 'rejected'].includes(record.value?.status)
);
const orderApproval = computed(
  () =>
    record.value?.metadata?.source === 'order_approval' &&
    record.value?.request_kind === 'approval'
);
const admin = computed(() => store.getters.getCurrentRole === 'administrator');
const requestContext = computed(() =>
  JSON.stringify([
    route.params.accountId,
    route.params.requestId,
    store.getters.getCurrentUser?.id,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
  ])
);
const load = async () => {
  sequence += 1;
  const request = sequence;
  loading.value = true;
  saving.value = false;
  error.value = '';
  record.value = null;
  try {
    const { data } = await backofficeAPI.show(route.params.requestId);
    if (sequence === request) record.value = data;
  } catch {
    if (sequence === request) error.value = text('DETAIL_ERROR');
  } finally {
    if (sequence === request) loading.value = false;
  }
};
const refreshDocuments = async () => {
  const current = sequence;
  const context = requestContext.value;
  try {
    const { data } = await backofficeAPI.show(route.params.requestId);
    if (current === sequence && context === requestContext.value)
      record.value = data;
  } catch (failure) {
    if (current !== sequence || context !== requestContext.value) return;
    error.value = text('DETAIL_ERROR');
    if ([401, 403, 404].includes(failure.response?.status)) record.value = null;
  }
};
const action = async command => {
  if (saving.value) return;
  const context = requestContext.value;
  saving.value = true;
  error.value = '';
  message.value = '';
  try {
    await command();
    if (context !== requestContext.value) return;
    await load();
    if (context !== requestContext.value) return;
    message.value = text('ACTION_SUCCESS');
  } catch (failure) {
    if (context !== requestContext.value) return;
    error.value =
      failure.response?.data?.errors?.join(', ') ||
      failure.response?.data?.message ||
      text(
        failure.response?.status === 409 ? 'APPROVAL_ERROR' : 'ACTION_ERROR'
      );
  } finally {
    if (context === requestContext.value) saving.value = false;
  }
};
watch(requestContext, load, {
  immediate: true,
});
onBeforeUnmount(() => {
  sequence += 1;
});
</script>

<template>
  <div
    class="space-y-4"
    :aria-busy="loading || saving"
  >
    <div class="flex items-center justify-between gap-3">
      <RouterLink
        :to="{
          name: 'crm_backoffice',
          params: { section: 'requests' },
          query: { customer_segment_id: route.query.customer_segment_id },
        }"
        class="text-sm font-semibold text-emerald-700"
      >
        {{ text('BACK_TO_QUEUE') }}
      </RouterLink>
      <button
        class="rounded-lg border bg-n-solid-2 px-4 py-2 text-sm disabled:opacity-50"
        :disabled="loading || saving"
        @click="load"
      >
        {{ text('REFRESH') }}
      </button>
    </div>
    <p
      v-if="error"
      role="alert"
      class="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800"
    >
      {{ error }}
    </p>
    <p
      v-if="message"
      role="status"
      class="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800"
    >
      {{ message }}
    </p>
    <p
      v-if="loading"
      role="status"
      class="rounded-xl border bg-n-solid-2 p-8"
    >
      {{ text('LOADING') }}
    </p>
    <template v-else-if="record">
      <header
        class="rounded-2xl border border-emerald-200 border-t-4 border-t-emerald-500 bg-n-solid-2 p-5 shadow-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p
              class="text-xs font-bold uppercase tracking-wide text-emerald-700"
            >
              {{ text('DETAIL_TITLE') }} {{ text('SEPARATOR') }}
              {{ record.request_number }}
            </p>
            <h2 class="mt-2 text-xl font-bold">{{ record.title }}</h2>
            <p class="mt-2 text-sm text-n-slate-11">
              {{
                record.company?.name ||
                record.contact?.name ||
                text('NO_CLIENT')
              }}
              {{ text('SEPARATOR') }} {{ record.order.order_number }}
            </p>
            <p class="mt-2 text-xs text-n-slate-11">
              {{ record.queue?.name || text('NO_QUEUE') }}
              {{ text('SEPARATOR') }} {{ record.owner.name }}
              {{ text('SEPARATOR') }}
              {{ record.business_unit?.name || text('NO_UNIT') }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <BackofficeCompletionReport :record="record" />
            <span
              class="rounded-lg border px-3 py-2 text-sm font-semibold"
              :class="moduleTabClasses(stageTones[record.stage])"
            >
              {{ label(record.stage) }}
            </span>
            <span class="rounded-lg bg-n-slate-3 px-3 py-2 text-sm">
              {{ label(record.status) }}
            </span>
            <span
              class="rounded-lg border px-3 py-2 text-sm font-semibold"
              :class="
                moduleTabClasses(
                  record.priority === 'critical' ? 'rose' : 'amber'
                )
              "
            >
              {{ label(record.priority) }}
            </span>
          </div>
        </div>
      </header>
      <div class="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_280px]">
        <section
          class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
        >
          <nav
            :aria-label="text('DETAIL_NAV')"
            class="flex flex-wrap gap-2 border-b border-n-weak bg-n-slate-2 p-3"
          >
            <button
              v-for="item in tabs"
              :id="`backoffice-tab-${item}`"
              :key="item"
              :aria-pressed="tab === item"
              class="whitespace-nowrap rounded-lg border px-3 py-2 text-sm font-semibold"
              :class="moduleTabClasses(tabTones[item], tab === item)"
              @click="tab = item"
            >
              {{ text(`DETAIL_TABS.${item}`) }}
            </button>
          </nav>
          <div
            class="bg-n-slate-2 p-4"
            :aria-labelledby="`backoffice-tab-${tab}`"
          >
            <BackofficeRequestSummary
              v-if="tab === 'operations'"
              :record="record"
              @view="tab = $event"
            />
            <div
              v-else-if="tab === 'context'"
              class="space-y-5"
            >
              <div
                class="mt-3 grid gap-2 text-sm sm:grid-cols-2 xl:grid-cols-4"
              >
                <div class="rounded-lg border border-n-weak p-2">
                  <p class="text-xs text-n-slate-11">
                    {{ text('QUEUE_OWNER') }}
                  </p>
                  <b class="mt-1 block">
                    {{ record.queue?.name || text('NO_QUEUE') }}
                  </b>
                  <span>{{ record.owner.name }}</span>
                </div>
                <div class="rounded-lg border border-n-weak p-2">
                  <p class="text-xs text-n-slate-11">{{ text('UNIT') }}</p>
                  <b class="mt-1 block">
                    {{ record.business_unit?.name || text('NO_UNIT') }}
                  </b>
                  <p class="mt-1 text-xs">{{ label(record.request_kind) }}</p>
                </div>
                <div class="rounded-lg border border-n-weak p-2">
                  <p class="text-xs text-n-slate-11">{{ text('DEADLINE') }}</p>
                  <b class="mt-1 block">{{ date(record.due_at) }}</b>
                  <p class="mt-1 text-xs">
                    {{ text('CREATED') }} {{ date(record.created_at) }}
                  </p>
                </div>
                <div
                  class="rounded-lg border border-n-weak p-2"
                  :class="{
                    'bg-red-50 text-red-800': record.sla.state === 'overdue',
                  }"
                >
                  <p class="text-xs">{{ text('SLA') }}</p>
                  <b class="mt-1 block">{{ slaLabel(record.sla) }}</b>
                  <p
                    v-if="record.sla.paused_at"
                    class="mt-1 text-xs"
                  >
                    {{ text('PAUSED') }} {{ date(record.sla.paused_at) }}
                  </p>
                  <p
                    v-else
                    class="mt-1 text-xs"
                  >
                    {{ text('TOTAL_DEADLINE') }}
                    {{ date(record.sla.total_due_at) }}
                  </p>
                </div>
              </div>
              <p
                v-if="record.description"
                class="whitespace-pre-wrap text-sm"
              >
                {{ record.description }}
              </p>
              <div class="grid gap-4 sm:grid-cols-2">
                <article
                  class="rounded-xl border border-blue-200 bg-blue-50 p-4 text-blue-900"
                >
                  <h3 class="font-bold">{{ text('COMMERCIAL_CONTEXT') }}</h3>
                  <p class="mt-2 text-sm">
                    {{ record.order.order_number }} {{ text('SEPARATOR') }}
                    {{ label(record.order.status) }}
                  </p>
                  <p class="mt-1 text-sm">
                    {{ text('REQUESTED_BY') }} {{ record.requested_by.name }}
                  </p>
                  <div class="mt-4 flex flex-wrap gap-3">
                    <RouterLink
                      v-if="record.commercial.order_accessible"
                      :to="{
                        name: 'crm_orders',
                        query: { orderId: record.order.id },
                      }"
                      class="text-sm font-semibold underline"
                    >
                      {{ text('OPEN_ORDER') }}
                    </RouterLink>
                    <RouterLink
                      v-if="
                        record.contact &&
                        (record.commercial.company_accessible ||
                          record.commercial.contact_accessible)
                      "
                      :to="{
                        name:
                          record.company && record.commercial.company_accessible
                            ? 'jrc_customer_company'
                            : 'crm_customer_360',
                        params:
                          record.company && record.commercial.company_accessible
                            ? { companyId: record.company.id }
                            : { customerId: record.contact.id },
                      }"
                      class="text-sm font-semibold underline"
                    >
                      {{ text('OPEN_CLIENT') }}
                    </RouterLink>
                  </div>
                </article>
                <article
                  class="rounded-xl border border-violet-200 bg-violet-50 p-4 text-violet-900"
                >
                  <h3 class="font-bold">{{ text('CONTRACT') }}</h3>
                  <template v-if="record.contract">
                    <p class="mt-2 text-sm">
                      {{ record.contract.contract_number }}
                      {{ text('SEPARATOR') }}
                      {{ label(record.contract.signature_status) }}
                    </p>
                    <RouterLink
                      v-if="record.commercial.contract_accessible"
                      :to="{
                        name: 'crm_contracts',
                        query: { contractId: record.contract.id },
                      }"
                      class="mt-4 inline-block text-sm font-semibold underline"
                    >
                      {{ text('OPEN_CONTRACT') }}
                    </RouterLink>
                  </template>
                  <p
                    v-else
                    class="mt-2 text-sm"
                  >
                    {{ text('NO_CONTRACT') }}
                  </p>
                </article>
              </div>
              <dl
                class="grid gap-3 rounded-xl border border-n-weak p-4 text-sm sm:grid-cols-3"
              >
                <div>
                  <dt class="text-xs text-n-slate-11">
                    {{ text('FIRST_ACTION') }}
                  </dt>
                  <dd class="mt-1">
                    {{
                      record.sla.first_action_at
                        ? date(record.sla.first_action_at)
                        : text('NO_ACTION')
                    }}
                  </dd>
                  <dd class="mt-1">
                    {{ text('DEADLINE') }}{{ text('FIELD_SEPARATOR') }}
                    {{ date(record.sla.first_action_due_at) }}
                  </dd>
                </div>
                <div>
                  <dt class="text-xs text-n-slate-11">
                    {{ text('STAGE_DEADLINE') }}
                  </dt>
                  <dd class="mt-1">{{ date(record.sla.stage_due_at) }}</dd>
                </div>
                <div>
                  <dt class="text-xs text-n-slate-11">
                    {{ text('TOTAL_DEADLINE') }}
                  </dt>
                  <dd class="mt-1">{{ date(record.sla.total_due_at) }}</dd>
                </div>
              </dl>
            </div>
            <div
              v-else-if="tab === 'documents'"
              class="space-y-4"
            >
              <BackofficeDocumentVersions
                :record="record"
                @changed="refreshDocuments"
              />
              <details class="rounded-xl border border-n-weak bg-n-solid-2 p-4">
                <summary class="cursor-pointer font-semibold">
                  {{ text('DOCUMENTS.LEGACY') }}
                </summary>
                <BackofficeActions
                  :record="record"
                  tab="documents"
                  :saving="saving"
                  class="mt-4"
                  @command="action"
                />
              </details>
            </div>
            <BackofficeContractPanel
              v-else-if="tab === 'contracts'"
              :record="record"
            />
            <BackofficeActions
              v-else-if="['checklist', 'issues'].includes(tab)"
              :key="tab"
              :record="record"
              :start-issue="startIssue"
              :tab="tab"
              :saving="saving"
              @command="action"
            />
            <BackofficeFinance
              v-else-if="tab === 'finance'"
              :record="record"
              :saving="saving"
              @command="action"
            />
            <div
              v-else
              class="space-y-3"
            >
              <p class="text-xs text-n-slate-11">{{ text('HISTORY_NOTE') }}</p>
              <article
                v-for="event in record.history.slice(
                  (historyPage - 1) * 5,
                  historyPage * 5
                )"
                :key="event.id"
                class="rounded-lg border border-n-weak border-l-4 border-l-emerald-400 px-3 py-2 text-sm"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <b>{{ label(event.event_type) }}</b>
                  <time class="text-xs text-n-slate-11">
                    {{ date(event.created_at) }}
                  </time>
                </div>
                <div
                  v-if="event.to_value?.stage || event.to_value?.status"
                  class="mt-1 flex flex-wrap gap-3 text-xs text-n-slate-11"
                >
                  <span v-if="event.to_value?.stage">
                    {{ text('STAGE') }}{{ text('FIELD_SEPARATOR') }}
                    {{ label(event.to_value.stage) }}
                  </span>
                  <span v-if="event.to_value?.status">
                    {{ text('STATUS') }}{{ text('FIELD_SEPARATOR') }}
                    {{ label(event.to_value.status) }}
                  </span>
                </div>
              </article>
              <p
                v-if="!record.history.length"
                class="py-5 text-sm text-n-slate-11"
              >
                {{ text('EMPTY_HISTORY') }}
              </p>
              <div
                v-if="record.history.length > 5"
                class="flex justify-end gap-3 text-sm"
              >
                <button
                  :disabled="historyPage <= 1"
                  @click="historyPage--"
                >
                  {{ text('PREVIOUS') }}
                </button>
                <span>
                  {{ historyPage }} {{ text('PAGE_SEPARATOR') }}
                  {{ Math.ceil(record.history.length / 5) }}
                </span>
                <button
                  :disabled="historyPage * 5 >= record.history.length"
                  @click="historyPage++"
                >
                  {{ text('NEXT') }}
                </button>
              </div>
            </div>
          </div>
        </section>
        <aside class="min-w-0 xl:sticky xl:top-0">
          <div
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
          >
            <h3 class="flex items-center gap-2 font-bold">
              <span
                class="i-lucide-layers size-5 text-blue-600 dark:text-blue-300"
              />
              {{ text('REQUEST_SUMMARY.CENTRAL') }}
            </h3>
            <dl class="my-3 divide-y divide-n-weak text-xs">
              <div
                v-for="item in [
                  {
                    key: 'REQUEST_SUMMARY.PROTOCOL',
                    value: record.request_number,
                  },
                  {
                    key: 'REQUEST_SUMMARY.SALE_VALUE',
                    value: money(record.order.total_cents),
                  },
                  { key: 'SLA', value: slaLabel(record.sla) },
                  { key: 'PRIORITY', value: label(record.priority) },
                  { key: 'REQUEST_SUMMARY.OWNER', value: record.owner.name },
                ]"
                :key="item.key"
                class="flex justify-between gap-3 py-2"
              >
                <dt class="text-n-slate-11">{{ text(item.key) }}</dt>
                <dd class="text-right font-semibold">{{ item.value }}</dd>
              </div>
            </dl>
            <h4 class="text-sm font-bold">{{ text('NEXT_ACTION') }}</h4>
            <p class="mt-2 text-sm">
              {{ text('NEXT_STAGE') }}
              <b>{{ label(record.next_stage) }}</b>
            </p>
            <ul
              v-if="record.stage_blockers.length && !terminal"
              class="mt-3 list-inside list-disc space-y-2 rounded-xl bg-amber-50 p-4 text-sm text-amber-900"
            >
              <li
                v-for="blocker in record.stage_blockers"
                :key="blocker"
              >
                {{ blocker }}
              </li>
            </ul>
            <p class="mt-3 text-xs text-n-slate-11">
              {{ text('VALIDATION_NOTE') }}
            </p>
            <div class="mt-3 flex flex-wrap gap-2">
              <ApprovalGateBadge
                resource-key="backoffice.release"
                :resource-id="record.id"
              />
              <ApprovalGateBadge
                resource-key="crm.order_price"
                :resource-id="record.order.id"
              />
            </div>
            <div class="mt-4 flex flex-wrap gap-2">
              <button
                v-if="!terminal && !orderApproval"
                class="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
                :disabled="saving || record.stage_blockers.length > 0"
                @click="action(() => backofficeAPI.advance(record.id))"
              >
                {{ text('ADVANCE') }}
              </button>
              <button
                v-if="!terminal && !orderApproval"
                class="rounded-lg border border-amber-300 bg-amber-50 px-4 py-2 text-sm font-semibold text-amber-900 disabled:opacity-40"
                :disabled="saving"
                @click="
                  action(() =>
                    backofficeAPI.update(record.id, {
                      backoffice_request: {
                        status:
                          record.status === 'blocked'
                            ? 'in_progress'
                            : 'blocked',
                      },
                    })
                  )
                "
              >
                {{ text(record.status === 'blocked' ? 'RESUME' : 'BLOCK') }}
              </button>
              <button
                v-if="terminal && admin && !orderApproval"
                class="rounded-lg border border-emerald-300 px-4 py-2 text-sm text-emerald-700 disabled:opacity-40"
                :disabled="saving"
                @click="
                  action(() =>
                    backofficeAPI.reopen(record.id, { stage: 'analysis' })
                  )
                "
              >
                {{ text('REOPEN') }}
              </button>
            </div>
            <button
              v-if="!terminal && !orderApproval"
              class="mt-3 flex w-full items-center justify-center gap-2 rounded-lg border px-3 py-2 text-sm font-semibold"
              :class="moduleTabClasses('amber')"
              @click="
                startIssue = true;
                tab = 'issues';
              "
            >
              <span class="i-lucide-plus size-4" />
              {{ text('REQUEST_SUMMARY.NEW_ISSUE') }}
            </button>
            <details
              v-if="!terminal && !orderApproval"
              class="mt-4 border-t border-n-weak pt-3"
            >
              <summary
                class="cursor-pointer text-xs font-semibold text-n-slate-11"
              >
                {{ text('REQUEST_SUMMARY.MANAGE') }}
              </summary>
              <BackofficeAssignment
                :record="record"
                :saving="saving"
                @command="action"
              />
            </details>
            <BackofficeActions
              v-if="
                orderApproval ||
                record.stage === 'approval' ||
                record.request_kind === 'approval'
              "
              :record="record"
              tab="approval"
              :saving="saving"
              class="mt-4"
              @command="action"
            />
          </div>
        </aside>
      </div>
    </template>
  </div>
</template>
