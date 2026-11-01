<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
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
const tab = ref('context');
const tabs = ['context', 'documents', 'checklist', 'issues', 'history'];
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
const checklist = computed(
  () =>
    record.value?.metadata?.implementation_checklist ||
    record.value?.order.snapshot?.checklist ||
    []
);
const manage = section => ({
  name: 'crm_backoffice',
  params: { section },
  query: { requestId: record.value.id },
});
const load = async () => {
  sequence += 1;
  const request = sequence;
  loading.value = true;
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
const action = async command => {
  if (saving.value) return;
  saving.value = true;
  error.value = '';
  message.value = '';
  try {
    await command();
    await load();
    message.value = text('ACTION_SUCCESS');
  } catch (failure) {
    error.value =
      failure.response?.data?.errors?.join(', ') ||
      failure.response?.data?.message ||
      text(
        failure.response?.status === 409 ? 'APPROVAL_ERROR' : 'ACTION_ERROR'
      );
  } finally {
    saving.value = false;
  }
};
watch(() => [route.params.accountId, route.params.requestId], load, {
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
        :to="{ name: 'crm_backoffice', params: { section: 'requests' } }"
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
              {{ record.contact?.name || text('NO_CLIENT') }}
              {{ text('SEPARATOR') }} {{ record.order.order_number }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <span
              class="rounded-lg bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800"
            >
              {{ label(record.stage) }}
            </span>
            <span class="rounded-lg bg-n-slate-3 px-3 py-2 text-sm">
              {{ label(record.status) }}
            </span>
            <span
              class="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900"
            >
              {{ label(record.priority) }}
            </span>
          </div>
        </div>
        <div class="mt-5 grid gap-3 text-sm sm:grid-cols-2 2xl:grid-cols-4">
          <div class="rounded-xl border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">{{ text('QUEUE_OWNER') }}</p>
            <b class="mt-1 block">
              {{ record.queue?.name || text('NO_QUEUE') }}
            </b>
            <span>{{ record.owner.name }}</span>
          </div>
          <div class="rounded-xl border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">{{ text('UNIT') }}</p>
            <b class="mt-1 block">
              {{ record.business_unit?.name || text('NO_UNIT') }}
            </b>
            <p class="mt-1 text-xs">{{ label(record.request_kind) }}</p>
          </div>
          <div class="rounded-xl border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">{{ text('DEADLINE') }}</p>
            <b class="mt-1 block">{{ date(record.due_at) }}</b>
            <p class="mt-1 text-xs">
              {{ text('CREATED') }} {{ date(record.created_at) }}
            </p>
          </div>
          <div
            class="rounded-xl border border-n-weak p-3"
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
              {{ text('TOTAL_DEADLINE') }} {{ date(record.sla.total_due_at) }}
            </p>
          </div>
        </div>
      </header>
      <section
        class="rounded-2xl border border-amber-200 bg-n-solid-2 p-5 shadow-sm"
      >
        <h3 class="font-bold">{{ text('NEXT_ACTION') }}</h3>
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
                      record.status === 'blocked' ? 'in_progress' : 'blocked',
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
          <RouterLink
            v-if="orderApproval"
            :to="manage('approvals')"
            class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white"
          >
            {{ text('REVIEW_APPROVAL') }}
          </RouterLink>
        </div>
      </section>
      <section
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <nav
          :aria-label="text('DETAIL_NAV')"
          class="flex gap-2 overflow-x-auto border-b border-n-weak bg-n-slate-2 p-3"
        >
          <button
            v-for="item in tabs"
            :id="`backoffice-tab-${item}`"
            :key="item"
            :aria-pressed="tab === item"
            class="whitespace-nowrap rounded-lg px-4 py-2 text-sm font-semibold"
            :class="
              tab === item
                ? 'bg-emerald-600 text-white'
                : 'border border-n-weak bg-n-solid-2 text-n-slate-11'
            "
            @click="tab = item"
          >
            {{ text(`DETAIL_TABS.${item}`) }}
          </button>
        </nav>
        <div
          class="p-5"
          :aria-labelledby="`backoffice-tab-${tab}`"
        >
          <div
            v-if="tab === 'context'"
            class="space-y-5"
          >
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
                    :to="{
                      name: 'crm_orders',
                      query: { orderId: record.order.id },
                    }"
                    class="text-sm font-semibold underline"
                  >
                    {{ text('OPEN_ORDER') }}
                  </RouterLink>
                  <RouterLink
                    v-if="record.contact"
                    :to="{
                      name: 'crm_customer_360',
                      params: { customerId: record.contact.id },
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
            class="space-y-3"
          >
            <RouterLink
              :to="manage('docs')"
              class="inline-block rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white"
            >
              {{ text('MANAGE_DOCUMENTS') }}
            </RouterLink>
            <div
              v-for="document in record.metadata.document_checklist || []"
              :key="document.key"
              class="rounded-xl border border-n-weak p-4 text-sm"
            >
              <b>{{ document.label }}</b>
              <p class="mt-1">
                {{ label(document.status) }} {{ text('SEPARATOR') }}
                {{ document.required ? text('REQUIRED') : text('OPTIONAL') }}
              </p>
            </div>
            <div
              v-for="document in record.documents"
              :key="document.id"
              class="flex flex-wrap justify-between gap-3 rounded-xl border border-blue-100 bg-blue-50 p-4 text-sm text-blue-900"
            >
              <b class="break-all">{{ document.filename }}</b>
              <span>{{ label(document.status) }}</span>
            </div>
            <p
              v-if="
                !record.documents.length &&
                !record.metadata.document_checklist?.length
              "
              class="py-5 text-sm text-n-slate-11"
            >
              {{ text('EMPTY_DOCUMENTS') }}
            </p>
          </div>
          <div
            v-else-if="tab === 'checklist'"
            class="space-y-3"
          >
            <RouterLink
              :to="
                manage(
                  record.stage === 'provisioning' ? 'provision' : 'implement'
                )
              "
              class="inline-block rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white"
            >
              {{ text('MANAGE_EXECUTION') }}
            </RouterLink>
            <div
              v-for="(item, index) in checklist"
              :key="index"
              class="flex items-center justify-between gap-3 rounded-xl border border-n-weak p-4 text-sm"
            >
              <span>{{ item.label || item.name || item.title }}</span>
              <b>{{ item.done ? text('DONE') : text('PENDING') }}</b>
            </div>
            <p
              v-if="!checklist.length"
              class="py-5 text-sm text-n-slate-11"
            >
              {{ text('EMPTY_CHECKLIST') }}
            </p>
            <p
              v-if="record.metadata.provisioning_completed_at"
              class="rounded-xl bg-emerald-50 p-4 text-sm text-emerald-900"
            >
              {{ text('PROVISIONED') }}
              {{ date(record.metadata.provisioning_completed_at) }}
            </p>
          </div>
          <div
            v-else-if="tab === 'issues'"
            class="space-y-3"
          >
            <RouterLink
              :to="manage('issues')"
              class="inline-block rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-white"
            >
              {{ text('MANAGE_ISSUES') }}
            </RouterLink>
            <article
              v-for="issue in record.metadata.issues || []"
              :key="issue.id"
              class="rounded-xl border border-amber-200 p-4 text-sm"
            >
              <b>{{ issue.description }}</b>
              <p class="mt-2">
                {{ label(issue.status || 'open') }} {{ text('SEPARATOR') }}
                {{ date(issue.due_at) }}
              </p>
            </article>
            <p
              v-if="!record.metadata.issues?.length"
              class="py-5 text-sm text-n-slate-11"
            >
              {{ text('EMPTY_ISSUES') }}
            </p>
          </div>
          <div
            v-else
            class="space-y-3"
          >
            <p class="text-xs text-n-slate-11">{{ text('HISTORY_NOTE') }}</p>
            <article
              v-for="event in record.history"
              :key="event.id"
              class="rounded-xl border border-n-weak border-l-4 border-l-emerald-400 p-4 text-sm"
            >
              <p class="text-xs text-n-slate-11">
                {{ date(event.created_at) }}
              </p>
              <b class="mt-1 block">{{ label(event.event_type) }}</b>
              <p
                v-if="event.to_value?.stage"
                class="mt-1"
              >
                {{ text('STAGE') }}{{ text('FIELD_SEPARATOR') }}
                {{ label(event.to_value.stage) }}
              </p>
              <p
                v-if="event.to_value?.status"
                class="mt-1"
              >
                {{ text('STATUS') }}{{ text('FIELD_SEPARATOR') }}
                {{ label(event.to_value.status) }}
              </p>
            </article>
            <p
              v-if="!record.history.length"
              class="py-5 text-sm text-n-slate-11"
            >
              {{ text('EMPTY_HISTORY') }}
            </p>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
