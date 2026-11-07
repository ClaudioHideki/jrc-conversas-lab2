<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, date, message } from './definitions';
const props = defineProps({
  group: { type: Object, required: true },
  metadata: { type: Object, required: true },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const rows = ref([]);
const loading = ref(false);
const exporting = ref(false);
const error = ref('');
const prepared = ref(false);
const pagination = ref({
  page: 1,
  per_page: 25,
  total: 0,
  can_read_rules: false,
});
const filters = reactive({ kind: '', from: '', to: '' });
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.group.id,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ])
);
const kinds = computed(() => ({
  created: t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.KINDS.created'),
  updated: t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.KINDS.updated'),
  customers: t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.KINDS.customers'),
  rules: t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.KINDS.rules'),
  exported: t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.KINDS.exported'),
  restored: t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.KINDS.restored'),
}));
const visibleKinds = computed(() =>
  Object.fromEntries(
    Object.entries(kinds.value).filter(
      ([kind]) =>
        !['rules', 'restored'].includes(kind) || pagination.value.can_read_rules
    )
  )
);
const fields = computed(() => ({
  name: t('RELATIONSHIP.NAMED_PORTFOLIOS.NAME'),
  objective: t('RELATIONSHIP.NAMED_PORTFOLIOS.OBJECTIVE'),
  owner_id: t('RELATIONSHIP.NAMED_PORTFOLIOS.COORDINATOR'),
  team_id: t('RELATIONSHIP.NAMED_PORTFOLIOS.TEAM'),
  business_unit_id: t('RELATIONSHIP.NAMED_PORTFOLIOS.UNIT'),
  segment_id: t('RELATIONSHIP.NAMED_PORTFOLIOS.SEGMENT'),
  visibility: t('RELATIONSHIP.NAMED_PORTFOLIOS.VISIBILITY'),
  status: t('RELATIONSHIP.NAMED_PORTFOLIOS.STATUS'),
  goals: t('RELATIONSHIP.NAMED_PORTFOLIOS.TABS.goals'),
  customers: t('RELATIONSHIP.NAMED_PORTFOLIOS.CUSTOMERS'),
  portfolio_capacity_limits: t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.CAPACITY'),
  portfolio_transfer_approval_required: t(
    'RELATIONSHIP.NAMED_PORTFOLIOS.RULES.APPROVAL'
  ),
  portfolio_review_validity_minutes: t(
    'RELATIONSHIP.NAMED_PORTFOLIOS.RULES.VALIDITY'
  ),
}));
const pages = computed(() =>
  Math.max(1, Math.ceil(pagination.value.total / pagination.value.per_page))
);
let generation = 0;
let controller;
const query = () =>
  Object.fromEntries(
    Object.entries(filters).filter(([, value]) => value !== '')
  );
const load = async (page = 1) => {
  generation += 1;
  const current = generation;
  controller?.abort();
  controller = new AbortController();
  const signal = controller.signal;
  rows.value = [];
  pagination.value = { page, per_page: 25, total: 0, can_read_rules: false };
  loading.value = true;
  error.value = '';
  prepared.value = false;
  if (!props.group.can_read_history) {
    loading.value = false;
    return;
  }
  try {
    const { data } = await API.portfolioGroupHistory(
      route.params.accountId,
      props.group.id,
      { ...query(), page },
      { signal }
    );
    if (signal.aborted || current !== generation) return;
    if (
      String(data.meta?.group_id) !== String(props.group.id) ||
      data.meta.projection !== 'operational_summary'
    ) {
      throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.UNCONFIRMED'));
    }
    rows.value = data.payload;
    pagination.value = data.meta;
  } catch (err) {
    if (!signal.aborted && current === generation)
      error.value =
        message(err) || t('RELATIONSHIP.NAMED_PORTFOLIOS.NOT_AVAILABLE');
  } finally {
    if (current === generation && !signal.aborted) loading.value = false;
  }
};
const download = async () => {
  if (loading.value || exporting.value || !props.group.can_export_history)
    return;
  const current = generation;
  const groupId = props.group.id;
  exporting.value = true;
  error.value = '';
  prepared.value = false;
  try {
    const { data } = await API.exportPortfolioGroupHistory(
      route.params.accountId,
      groupId,
      query(),
      { signal: controller?.signal }
    );
    if (current !== generation) return;
    if (
      String(data.group?.id) !== String(groupId) ||
      data.projection !== 'operational_summary' ||
      !Array.isArray(data.events)
    ) {
      throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.UNCONFIRMED'));
    }
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
    );
    const link = document.createElement('a');
    link.href = url;
    link.download = 'relationship-portfolio-history.json';
    link.click();
    URL.revokeObjectURL(url);
    prepared.value = true;
  } catch (err) {
    if (current === generation)
      error.value =
        message(err) || t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.UNCONFIRMED');
  } finally {
    if (current === generation) exporting.value = false;
  }
};
watch(
  [identity, () => props.group],
  (_, previous) => {
    if (!previous || previous[0] !== identity.value) {
      filters.kind = '';
      filters.from = '';
      filters.to = '';
    }
    exporting.value = false;
    pagination.value = {
      page: 1,
      per_page: 25,
      total: 0,
      can_read_rules: false,
    };
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-xl border border-n-violet-6 bg-n-solid-2 p-4"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <h3 class="font-semibold">
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.TITLE') }}
      </h3>
      <button
        v-if="group.can_export_history"
        type="button"
        :class="buttonClass"
        :disabled="loading || exporting"
        @click="download"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.EXPORT') }}
      </button>
    </header>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.HELP') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="break-words text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="loading"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="prepared"
      role="status"
      class="text-n-teal-11"
    >
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.PREPARED') }}
    </p>
    <form
      class="grid min-w-0 gap-3 sm:grid-cols-2 lg:grid-cols-4"
      @submit.prevent="load(1)"
    >
      <label class="grid min-w-0 gap-1">
        <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.KIND') }}</span>
        <select
          v-model="filters.kind"
          :class="inputClass"
          :disabled="loading || exporting"
        >
          <option value="">{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.ALL') }}</option>
          <option
            v-for="(label, kind) in visibleKinds"
            :key="kind"
            :value="kind"
          >
            {{ label }}
          </option>
        </select>
      </label>
      <label class="grid min-w-0 gap-1">
        <span>{{ t('RELATIONSHIP.FIELDS.from') }}</span>
        <input
          v-model="filters.from"
          type="date"
          :class="inputClass"
          :disabled="loading || exporting"
        />
      </label>
      <label class="grid min-w-0 gap-1">
        <span>{{ t('RELATIONSHIP.FIELDS.to') }}</span>
        <input
          v-model="filters.to"
          type="date"
          :class="inputClass"
          :disabled="loading || exporting"
        />
      </label>
      <div class="flex flex-wrap items-end gap-2">
        <button
          type="submit"
          :class="buttonClass"
          :disabled="loading || exporting"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.APPLY') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="loading || exporting"
          @click="
            filters.kind = '';
            filters.from = '';
            filters.to = '';
            load(1);
          "
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CLEAR') }}
        </button>
      </div>
    </form>
    <ol class="min-w-0 divide-y divide-n-weak rounded-lg border border-n-weak">
      <li
        v-for="row in rows"
        :key="row.id"
        class="grid min-w-0 gap-2 p-3 text-sm sm:grid-cols-3"
      >
        <div class="min-w-0">
          <p class="font-semibold">{{ kinds[row.kind] }}</p>
          <time class="text-xs text-n-slate-11">{{
            date(row.at, metadata.formatting)
          }}</time>
        </div>
        <p class="min-w-0 break-words">
          {{
            row.actor?.name ||
            t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.UNKNOWN_OPERATOR')
          }}
        </p>
        <div class="min-w-0">
          <p class="break-words">
            {{
              row.changed_fields
                .map(field => fields[field])
                .filter(Boolean)
                .join(' · ')
            }}
          </p>
          <p
            v-if="row.reason_recorded"
            class="text-xs text-n-slate-11"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.REASON_RECORDED') }}
          </p>
        </div>
      </li>
    </ol>
    <p
      v-if="!loading && !error && !rows.length"
      class="text-sm text-n-slate-11"
    >
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.EMPTY') }}
    </p>
    <footer class="flex flex-wrap items-center justify-end gap-2">
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading || exporting || pagination.page <= 1"
        @click="load(pagination.page - 1)"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.PREVIOUS') }}
      </button>
      <span class="text-sm">{{
        t('RELATIONSHIP.NAMED_PORTFOLIOS.PAGE', {
          page: pagination.page,
          pages,
        })
      }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading || exporting || pagination.page >= pages"
        @click="load(pagination.page + 1)"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NEXT_PAGE') }}
      </button>
    </footer>
  </section>
</template>
