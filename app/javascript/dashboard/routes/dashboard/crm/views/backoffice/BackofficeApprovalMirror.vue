<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { approvalClient } from 'dashboard/api/approvals';
import {
  capability,
  pagination,
} from 'dashboard/routes/dashboard/approvals/model';
import RequestDetail from 'dashboard/routes/dashboard/approvals/RequestDetail.vue';

const props = defineProps({ record: { type: Object, required: true } });
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const text = key => t(`CRM.BACKOFFICE_WORKSPACE.APPROVAL_MIRROR.${key}`);
const sources = computed(() => [
  { key: 'REQUEST', type: 'JrcCrm::BackofficeRequest', id: props.record.id },
  { key: 'ORDER', type: 'JrcCrm::SalesOrder', id: props.record.order.id },
  ...(props.record.contract
    ? [
        {
          key: 'CONTRACT',
          type: 'JrcCrm::Contract',
          id: props.record.contract.id,
        },
      ]
    : []),
]);
const sourceKey = ref('REQUEST');
const source = computed(() =>
  sources.value.find(row => row.key === sourceKey.value)
);
const page = ref(1);
const total = ref(0);
const rows = ref([]);
const context = ref(null);
const detail = ref(null);
const busy = ref(false);
const detailBusy = ref(false);
const error = ref(false);
let generation = 0;
let selection = 0;
const enabled = computed(
  () =>
    store.getters['accounts/isFeatureEnabledonAccount'](
      Number(route.params.accountId),
      'jrc_approvals'
    ) === true
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.record.id,
    props.record.updated_at,
    sources.value,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
    enabled.value,
  ])
);
const load = async () => {
  generation += 1;
  selection += 1;
  const token = generation;
  rows.value = [];
  detail.value = null;
  context.value = null;
  total.value = 0;
  error.value = false;
  busy.value = false;
  detailBusy.value = false;
  if (!enabled.value || !source.value) return;
  busy.value = true;
  try {
    const api = approvalClient(route.params.accountId);
    const [permissions, result] = await Promise.all([
      api.get('context'),
      api.get('requests', {
        resource_type: source.value.type,
        resource_id: source.value.id,
        page: page.value,
        per_page: 10,
      }),
    ]);
    if (token !== generation) return;
    context.value = permissions.data;
    rows.value = result.data;
    total.value = pagination(result).total;
  } catch {
    if (token === generation) error.value = true;
  } finally {
    if (token === generation) busy.value = false;
  }
};
const inspect = async row => {
  selection += 1;
  const chosen = selection;
  const token = generation;
  const origin = source.value;
  detail.value = null;
  error.value = false;
  detailBusy.value = true;
  try {
    const { data } = await approvalClient(route.params.accountId).get(
      `requests/${row.id}`
    );
    if (token !== generation || chosen !== selection) return;
    if (
      data.id !== row.id ||
      data.resource_type !== origin.type ||
      data.resource_id !== origin.id
    )
      throw new Error('APPROVAL_ORIGIN_MISMATCH');
    detail.value = data;
  } catch {
    if (token === generation && chosen === selection) error.value = true;
  } finally {
    if (token === generation && chosen === selection) detailBusy.value = false;
  }
};
const chooseSource = key => {
  sourceKey.value = key;
  page.value = 1;
};
watch(identity, () => {
  sourceKey.value = 'REQUEST';
  page.value = 1;
});
watch([identity, sourceKey, page], load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
  selection += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-4"
    :aria-label="text('TITLE')"
    :aria-busy="busy || detailBusy"
  >
    <h3 class="font-semibold">{{ text('TITLE') }}</h3>
    <p class="text-sm text-n-slate-11">{{ text('NOTICE') }}</p>
    <p
      v-if="!enabled"
      role="status"
    >
      {{ text('DISABLED') }}
    </p>
    <template v-else>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="item in sources"
          :key="item.key"
          type="button"
          :aria-pressed="sourceKey === item.key"
          :disabled="busy"
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm font-semibold text-n-blue-12 disabled:opacity-50"
          @click="chooseSource(item.key)"
        >
          {{ text(item.key) }}
        </button>
        <button
          type="button"
          :disabled="busy || detailBusy"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="load"
        >
          {{ t('JRC_APPROVALS.refresh') }}
        </button>
      </div>
      <p
        v-if="busy || detailBusy"
        role="status"
      >
        {{ t('JRC_APPROVALS.loading') }}
      </p>
      <p
        v-if="error"
        role="alert"
      >
        {{ t('JRC_APPROVALS.loadError') }}
      </p>
      <p v-if="!busy && !error && !rows.length">{{ text('EMPTY') }}</p>
      <div class="grid min-w-0 gap-2 md:grid-cols-2">
        <button
          v-for="row in rows"
          :key="row.id"
          type="button"
          :disabled="busy || detailBusy"
          class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-3 text-left text-sm disabled:opacity-50"
          @click="inspect(row)"
        >
          <span class="block break-words font-semibold">
            #{{ row.id }} · {{ row.policy_name }}
          </span>
          <span class="block">
            {{ t(`JRC_APPROVALS.status_${row.state}`, row.state) }} ·
            {{ t('JRC_APPROVALS.policy_version') }} {{ row.policy_version }}
          </span>
        </button>
      </div>
      <nav
        class="flex flex-wrap items-center gap-3"
        :aria-label="text('PAGES')"
      >
        <button
          type="button"
          :disabled="busy || page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="page -= 1"
        >
          {{ text('PREVIOUS') }}
        </button>
        <span class="text-sm">{{ text('PAGE') }} {{ page }} · {{ total }}</span>
        <button
          type="button"
          :disabled="busy || page * 10 >= total"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="page += 1"
        >
          {{ text('NEXT') }}
        </button>
      </nav>
      <section
        v-if="detail && context"
        class="min-w-0 space-y-4 rounded-xl border border-n-weak p-4"
        data-testid="approval-mirror-detail"
      >
        <RouterLink
          :to="{
            name: 'jrc_approvals',
            params: {
              accountId: route.params.accountId,
              screen: 'inbox',
              id: detail.id,
            },
          }"
          class="inline-flex rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm font-semibold text-n-blue-12"
        >
          {{ text('OPEN_CENTRAL') }}
        </RouterLink>
        <RequestDetail
          :request="detail"
          :context="context"
          read-only
          :audit-allowed="
            capability(
              context,
              'view_audit',
              detail.issuer_company_id,
              detail.business_unit_id
            )
          "
        />
      </section>
    </template>
  </section>
</template>
