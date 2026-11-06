<script setup>
import { computed, ref, watch, onBeforeUnmount, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ActionCasePanel from './ActionCasePanel.vue';
import PriorityBandBadge from './PriorityBandBadge.vue';
import { priorityCodes } from './priorityBands';
import NicoSummaryPanel from './NicoSummaryPanel.vue';
import { rememberViewport, viewportPosition } from './listViewport';
import {
  buttonClass,
  inputClass,
  date as formatDate,
  message,
  STATES,
} from './definitions';
const props = defineProps({ screen: { type: String, required: true } });
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const metadata = ref(null);
const metrics = ref(null);
const rows = ref([]);
const pagination = ref({ page: 1, per_page: 25, total: 0 });
const error = ref('');
const loading = ref(false);
const search = ref(String(route.query.q || ''));
const container = ref(null);
const nicoDialog = ref(null);
const isDashboard = computed(() => props.screen === 'overview');
const scope = computed(() => ({
  customer_segment_id: route.query.customer_segment_id || undefined,
  q: route.query.q || '',
  record_status: route.query.record_status || '',
  priority_band: route.query.priority_band || '',
  mine: route.query.mine !== 'false',
  returns_overdue: route.query.returns_overdue === 'true',
  page: Number(route.query.page) || 1,
}));
const date = value => formatDate(value, metadata.value?.formatting);
const patchQuery = values =>
  router.replace({ query: { ...route.query, page: undefined, ...values } });
const open = id => patchQuery({ action_id: id, page: route.query.page });
const close = () =>
  patchQuery({ action_id: undefined, page: route.query.page });
let generation = 0;
let controller;
let viewportKey = '';
const load = async () => {
  rememberViewport(viewportKey, container.value?.scrollTop || 0);
  viewportKey = JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    props.screen,
    scope.value,
  ]);
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  const options = { signal: controller.signal };
  const accountId = route.params.accountId;
  loading.value = true;
  error.value = '';
  rows.value = [];
  metrics.value = null;
  metadata.value = null;
  try {
    const meta = await API.metadata(accountId, options);
    if (version !== generation) return;
    metadata.value = meta.data;
    if (isDashboard.value) {
      const result = await API.dashboard(
        accountId,
        {
          mode: scope.value.mine ? 'mine' : undefined,
          customer_segment_id: scope.value.customer_segment_id,
        },
        options
      );
      if (version === generation) {
        metrics.value = result.data;
        rows.value = result.data.priority_actions || [];
      }
    } else {
      const result = await API.records(
        accountId,
        'actions',
        { ...scope.value, per_page: 25 },
        options
      );
      if (version === generation) {
        rows.value = result.data.payload;
        pagination.value = result.data.meta;
      }
    }
    await nextTick();
    if (version === generation && container.value)
      container.value.scrollTop = viewportPosition(viewportKey);
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED') {
      error.value = message(err);
      metadata.value = null;
    }
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.screen,
    () => JSON.stringify(scope.value),
  ],
  load,
  { immediate: true }
);
onBeforeUnmount(() => {
  rememberViewport(viewportKey, container.value?.scrollTop || 0);
  generation += 1;
  controller?.abort();
});
const cards = computed(() => [
  {
    key: 'customers',
    tone: 'border-blue-300 bg-blue-50 text-blue-900 dark:border-blue-800 dark:bg-blue-950/40 dark:text-blue-200',
    icon: 'i-lucide-users',
    to: 'portfolio',
  },
  {
    key: 'at_risk',
    tone: 'border-rose-300 bg-rose-50 text-rose-900 dark:border-rose-800 dark:bg-rose-950/40 dark:text-rose-200',
    icon: 'i-lucide-heart-pulse',
    to: 'health',
  },
  {
    key: 'actions_today',
    tone: 'border-n-violet-6 bg-n-violet-2 text-n-violet-12 ',
    icon: 'i-lucide-calendar-check',
    to: 'actions',
  },
  {
    key: 'overdue_returns',
    tone: 'border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-800 dark:bg-amber-950/40 dark:text-amber-200',
    icon: 'i-lucide-clock-alert',
    to: 'actions',
    query: { returns_overdue: 'true' },
  },
  {
    key: 'waiting_customer_actions',
    tone: 'border-teal-300 bg-teal-50 text-teal-900 dark:border-teal-800 dark:bg-teal-950/40 dark:text-teal-200',
    icon: 'i-lucide-message-circle',
    to: 'actions',
    query: { record_status: 'waiting_customer' },
  },
]);
</script>

<template>
  <div
    ref="container"
    class="min-h-0 flex-1 space-y-5 overflow-y-auto p-5 md:p-6"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-2xl font-semibold">
          {{
            t(
              isDashboard
                ? 'RELATIONSHIP.V2.MY_DASHBOARD'
                : 'RELATIONSHIP.V2.MY_ACTIONS'
            )
          }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('RELATIONSHIP.V2.ROUTINE') }}
        </p>
      </div>
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading"
        @click="load"
      >
        {{ t('RELATIONSHIP.REFRESH') }}
      </button>
    </div>
    <p
      v-if="error"
      role="alert"
      class="rounded-xl border border-rose-300 bg-rose-50 p-4 text-rose-900 dark:border-rose-800 dark:bg-rose-950 dark:text-rose-200"
    >
      {{ error }}
    </p>
    <p
      v-if="loading"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <template v-if="metadata">
      <div
        v-if="metadata.can_team"
        class="flex gap-2"
      >
        <button
          v-for="mine in [true, false]"
          :key="String(mine)"
          type="button"
          :class="[
            buttonClass,
            scope.mine === mine && 'border-n-violet-8 text-n-violet-11 ',
          ]"
          :aria-pressed="scope.mine === mine"
          @click="patchQuery({ mine: String(mine) })"
        >
          {{
            t(mine ? 'RELATIONSHIP.V2.MINE' : 'RELATIONSHIP.V2.AUTHORIZED_TEAM')
          }}
        </button>
      </div>
      <div
        v-if="metrics"
        class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5"
      >
        <RouterLink
          v-for="card in cards"
          :key="card.key"
          :to="{
            name: `jrc_relationship_${card.to}`,
            params: route.params,
            query: {
              mine: String(scope.mine),
              customer_segment_id: scope.customer_segment_id,
              ...card.query,
            },
          }"
          class="rounded-xl border p-4 transition hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-violet-8"
          :class="card.tone"
        >
          <span
            :class="card.icon"
            class="mb-3 block size-6"
            aria-hidden="true"
          />
          <p class="text-sm font-semibold">
            {{ t(`RELATIONSHIP.V2.CARDS.${card.key}`) }}
          </p>
          <strong class="mt-2 block text-3xl">{{
            metrics[card.key] ?? t('RELATIONSHIP.UNAVAILABLE')
          }}</strong>
        </RouterLink>
      </div>
      <section
        v-if="metrics?.monitoring"
        class="rounded-xl border border-n-violet-6 bg-n-violet-2 p-4"
      >
        <h3 class="font-semibold">{{ t('RELATIONSHIP.V2.MONITORING') }}</h3>
        <p class="mt-1 text-sm">
          {{
            t('RELATIONSHIP.V2.COVERAGE', {
              observed: metrics.monitoring.observed_customers,
              total: metrics.monitoring.customers,
            })
          }}
        </p>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('RELATIONSHIP.V2.LAST_PROCESSING') }}:
          {{ date(metrics.monitoring.last_processed_at) }} ·
          {{
            t('RELATIONSHIP.V2.STALE', {
              count: metrics.monitoring.stale_customers,
            })
          }}
        </p>
        <p class="mt-2 text-xs text-n-slate-11">
          {{ t('RELATIONSHIP.V2.MONITORING_LIMIT') }}
        </p>
        <p
          v-if="metrics.monitoring.latest_attempt"
          class="mt-2 text-sm"
        >
          {{
            t(
              `RELATIONSHIP.V2.PROCESSING.${metrics.monitoring.latest_attempt.state}`
            )
          }}
          ·
          {{
            t('RELATIONSHIP.V2.PROCESSING_RESULT', {
              processed: metrics.monitoring.latest_attempt.processed,
              failed: metrics.monitoring.latest_attempt.failed,
            })
          }}
          ·
          {{
            date(
              metrics.monitoring.latest_attempt.finished_at ||
                metrics.monitoring.latest_attempt.started_at
            )
          }}
        </p>
      </section>
      <button
        v-if="metrics"
        type="button"
        :class="buttonClass"
        @click="nicoDialog.open()"
      >
        {{ t('RELATIONSHIP.V2.NICO_SUMMARY') }}
      </button>
      <Dialog
        v-if="metrics"
        ref="nicoDialog"
        width="3xl"
        :title="t('RELATIONSHIP.V2.NICO_SUMMARY')"
        :show-confirm-button="false"
      >
        <NicoSummaryPanel
          :metrics="metrics"
          :enabled="metadata.can_nico"
          :metadata="metadata"
          @customer="
            router.push({
              name: 'jrc_relationship_customers',
              params: route.params,
              query: {
                assignment_id: $event,
                customer_segment_id: scope.customer_segment_id,
              },
            })
          "
        />
      </Dialog>
      <form
        v-if="!isDashboard"
        class="flex flex-wrap items-end gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        @submit.prevent="patchQuery({ q: search })"
      >
        <label class="min-w-48 flex-1 text-sm"
          >{{ t('RELATIONSHIP.FIELDS.customer')
          }}<input
            v-model="search"
            type="search"
            maxlength="100"
            :class="inputClass" /></label
        ><label class="text-sm"
          >{{ t('RELATIONSHIP.FIELDS.status')
          }}<select
            :value="scope.record_status"
            :class="inputClass"
            @change="patchQuery({ record_status: $event.target.value })"
          >
            <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
            <option
              v-for="status in STATES.actions"
              :key="status"
              :value="status"
            >
              {{ t(`RELATIONSHIP.STATES.${status}`) }}
            </option>
          </select></label
        ><label class="text-sm">
          {{ t('RELATIONSHIP.PRIORITY_BANDS.TITLE') }}
          <select
            :value="scope.priority_band"
            :class="inputClass"
            @change="
              patchQuery({ priority_band: $event.target.value || undefined })
            "
          >
            <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
            <option
              v-for="code in priorityCodes"
              :key="code"
              :value="code"
            >
              {{ code }} · {{ t(`RELATIONSHIP.PRIORITY_BANDS.${code}`) }}
            </option>
          </select>
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            :checked="scope.returns_overdue"
            @change="
              patchQuery({
                returns_overdue: $event.target.checked ? 'true' : undefined,
              })
            "
          />{{ t('RELATIONSHIP.V2.CARDS.overdue_returns') }}
        </label>
        <button
          type="submit"
          :class="buttonClass"
        >
          {{ t('RELATIONSHIP.FILTER') }}
        </button>
      </form>
      <section
        class="overflow-hidden rounded-xl border border-n-violet-5 bg-n-solid-2"
      >
        <header
          class="flex items-center justify-between border-b border-n-weak p-4"
        >
          <h3 class="font-semibold">
            {{
              t(
                isDashboard
                  ? 'RELATIONSHIP.V2.PRIORITIES'
                  : 'RELATIONSHIP.V2.MY_ACTIONS'
              )
            }}
          </h3>
          <RouterLink
            v-if="isDashboard"
            class="text-sm font-semibold text-n-violet-11 underline"
            :to="{
              name: 'jrc_relationship_actions',
              params: route.params,
              query: {
                mine: String(scope.mine),
                customer_segment_id: scope.customer_segment_id,
              },
            }"
          >
            {{ t('RELATIONSHIP.V2.SEE_ALL') }}
          </RouterLink>
        </header>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm">
            <thead class="bg-n-violet-2">
              <tr>
                <th
                  v-for="key in [
                    'customer',
                    'reason',
                    'priority',
                    'due_at',
                    'status',
                    'next_step',
                  ]"
                  :key="key"
                  class="p-3"
                >
                  {{ t(`RELATIONSHIP.FIELDS.${key}`) }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="row in rows"
                :key="row.id"
                class="hover:bg-n-alpha-1"
              >
                <td class="p-3 font-semibold">
                  {{ row.customer_name || row.customer }}
                </td>
                <td class="min-w-56 p-3">
                  <button
                    type="button"
                    class="text-left font-semibold text-blue-700 underline dark:text-blue-300"
                    @click="open(row.id)"
                  >
                    {{ row.reason }}
                  </button>
                  <p
                    v-if="row.owner_name"
                    class="mt-1 text-xs text-n-slate-11"
                  >
                    {{ row.owner_name }}
                  </p>
                </td>
                <td class="p-3">
                  <span
                    class="rounded-lg border px-2 py-1 font-semibold"
                    :class="
                      row.priority >= 80
                        ? 'border-rose-300 bg-rose-50 text-rose-900 dark:border-rose-800 dark:bg-rose-950 dark:text-rose-200'
                        : 'border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-200'
                    "
                    >{{ row.priority }}</span
                  >
                  <PriorityBandBadge
                    :record="row"
                    class="mt-1"
                  />
                </td>
                <td class="whitespace-nowrap p-3">{{ date(row.due_at) }}</td>
                <td class="p-3">
                  {{ t(`RELATIONSHIP.STATES.${row.status}`) }}
                </td>
                <td class="min-w-48 p-3">
                  <p>
                    {{ row.next_step || t('RELATIONSHIP.V2.NO_NEXT_STEP') }}
                  </p>
                  <p class="mt-1 text-xs text-n-slate-11">
                    {{ date(row.return_at) }}
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p
          v-if="!rows.length && !loading"
          class="p-5 text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.V2.EMPTY_ACTIONS') }}
        </p>
      </section>
      <nav
        v-if="!isDashboard"
        class="flex items-center justify-between gap-3"
        :aria-label="t('RELATIONSHIP.V2.PAGINATION')"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="pagination.page <= 1 || loading"
          @click="patchQuery({ page: pagination.page - 1 })"
        >
          {{ t('RELATIONSHIP.V2.PREVIOUS') }}</button
        ><span class="text-sm">{{
          t('RELATIONSHIP.V2.PAGE', {
            page: pagination.page,
            total: pagination.total,
          })
        }}</span
        ><button
          type="button"
          :class="buttonClass"
          :disabled="
            pagination.page * pagination.per_page >= pagination.total || loading
          "
          @click="patchQuery({ page: pagination.page + 1 })"
        >
          {{ t('RELATIONSHIP.V2.NEXT') }}
        </button>
      </nav>
      <ActionCasePanel
        v-if="route.query.action_id"
        :action-id="route.query.action_id"
        :metadata="metadata"
        @close="close"
        @changed="load"
        @invalidated="load"
      />
    </template>
  </div>
</template>
