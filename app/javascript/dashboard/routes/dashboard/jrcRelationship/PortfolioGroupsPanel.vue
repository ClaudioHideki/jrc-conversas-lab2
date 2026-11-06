<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import PortfolioGroupEditor from './PortfolioGroupEditor.vue';
import PortfolioGroupCustomersDialog from './PortfolioGroupCustomersDialog.vue';
import PortfolioGroupWorkloadPanel from './PortfolioGroupWorkloadPanel.vue';
import PortfolioGroupRulesPanel from './PortfolioGroupRulesPanel.vue';
import PortfolioGroupHistoryPanel from './PortfolioGroupHistoryPanel.vue';
import PortfolioGroupMasterDialog from './PortfolioGroupMasterDialog.vue';
import CustomerPanel from './CustomerPanel.vue';
import { buttonClass, inputClass, message } from './definitions';
import { confirmedMembership } from './portfolioGroupMembershipReceipt';
const props = defineProps({ metadata: { type: Object, required: true } });
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const filters = reactive({ query: '', status: 'active' });
const rows = ref([]);
const group = ref(null);
const customers = ref([]);
const pagination = ref({ page: 1, per_page: 25, total: 0 });
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const saveError = ref('');
const saved = ref(false);
const membershipResult = ref(null);
const membershipStates = computed(() => ({
  linked: t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.linked'),
  already_linked: t(
    'RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.already_linked'
  ),
  unlinked: t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.unlinked'),
  already_unlinked: t(
    'RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.already_unlinked'
  ),
}));
const conflict = ref(false);
const blocked = ref(false);
const editorOpen = ref(false);
const editorRecord = ref(null);
const customerDialog = ref(null);
const masterOpen = ref(false);
const selectedCustomer = ref(null);
const detailsTab = ref('customers');
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
  ])
);
const selectedId = computed(() => route.query.group_id);
const viewIdentity = computed(() =>
  JSON.stringify([identity.value, selectedId.value || null])
);
const pages = computed(() =>
  Math.max(1, Math.ceil(pagination.value.total / pagination.value.per_page))
);
const canCreate = computed(
  () => !blocked.value && props.metadata.can_manage && props.metadata.can_team
);
const editorMetadata = computed(() => ({
  ...props.metadata,
  can_configure: editorRecord.value
    ? editorRecord.value.can_configure
    : props.metadata.can_configure,
}));
let generation = 0;
let mutationGeneration = 0;
let controller;
let dialogContext;
const closeDrafts = () => {
  editorOpen.value = false;
  editorRecord.value = null;
  customerDialog.value = null;
  masterOpen.value = false;
  saveError.value = '';
  conflict.value = false;
};
const load = async (page = 1) => {
  controller?.abort();
  controller = new AbortController();
  const signal = controller.signal;
  generation += 1;
  const token = generation;
  const current = identity.value;
  const accountId = route.params.accountId;
  const id = selectedId.value;
  error.value = '';
  loading.value = true;
  try {
    if (id) {
      const [detail, list] = await Promise.all([
        API.portfolioGroup(accountId, id, { signal }),
        API.portfolioGroupCustomers(accountId, id, { page }, { signal }),
      ]);
      if (signal.aborted || token !== generation || current !== identity.value)
        return;
      group.value = detail.data;
      if (detailsTab.value === 'rules' && !detail.data.can_configure)
        detailsTab.value = 'customers';
      if (detailsTab.value === 'history' && !detail.data.can_read_history)
        detailsTab.value = 'customers';
      customers.value = list.data.payload;
      pagination.value = list.data.meta;
    } else {
      const { data } = await API.portfolioGroups(
        accountId,
        { page, q: filters.query, status: filters.status },
        { signal }
      );
      if (signal.aborted || token !== generation || current !== identity.value)
        return;
      rows.value = data.payload;
      pagination.value = data.meta;
    }
    blocked.value = false;
  } catch (err) {
    if (signal.aborted || token !== generation || current !== identity.value)
      return;
    group.value = null;
    rows.value = [];
    customers.value = [];
    selectedCustomer.value = null;
    blocked.value = [401, 403].includes(err.response?.status);
    error.value = message(err);
  } finally {
    if (token === generation && current === identity.value)
      loading.value = false;
  }
};
const openGroup = id =>
  router.replace({
    query: { ...route.query, section: 'groups', group_id: id || undefined },
  });
const openNativeCustomers = () =>
  router.replace({
    query: {
      ...route.query,
      section: 'customers',
      group_id: undefined,
      portfolio_group_id: group.value.id,
    },
  });
const openEditor = record => {
  if (loading.value || saving.value) return;
  closeDrafts();
  dialogContext = viewIdentity.value;
  editorRecord.value = record;
  editorOpen.value = true;
};
const openCustomers = customer => {
  if (!group.value?.can_manage || saving.value) return;
  closeDrafts();
  dialogContext = viewIdentity.value;
  customerDialog.value = { customer };
};
const reviewMasterCustomer = customer => {
  if (!group.value?.can_manage || saving.value) return;
  closeDrafts();
  dialogContext = viewIdentity.value;
  customerDialog.value = { customer: null, initialCustomer: customer };
};
const mutate = async (action, groupId, membershipRequest = null) => {
  if (saving.value || dialogContext !== viewIdentity.value) return;
  mutationGeneration += 1;
  const operation = mutationGeneration;
  const viewed = viewIdentity.value;
  const current = identity.value;
  saving.value = true;
  saveError.value = '';
  conflict.value = false;
  saved.value = false;
  membershipResult.value = null;
  try {
    const { data } = await action();
    if (operation !== mutationGeneration || viewed !== viewIdentity.value)
      return;
    if (
      !Number.isSafeInteger(data?.id) ||
      data.id <= 0 ||
      !Number.isSafeInteger(data.version) ||
      data.version < 0 ||
      (groupId && String(data.id) !== String(groupId)) ||
      (membershipRequest && !confirmedMembership(data, membershipRequest))
    ) {
      throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.SAVE_UNCONFIRMED'));
    }
    closeDrafts();
    if (membershipRequest) membershipResult.value = data.results;
    if (String(selectedId.value) !== String(groupId || data.id))
      await openGroup(groupId || data.id);
    else await load(1);
    if (
      current === identity.value &&
      String(selectedId.value) === String(groupId || data.id)
    )
      saved.value = true;
  } catch (err) {
    if (operation !== mutationGeneration || viewed !== viewIdentity.value)
      return;
    conflict.value = err.response?.status === 409;
    saveError.value = message(err);
  } finally {
    if (operation === mutationGeneration && current === identity.value)
      saving.value = false;
  }
};
const saveGroup = fields => {
  const accountId = route.params.accountId;
  const id = editorRecord.value?.id;
  return mutate(() => API.savePortfolioGroup(accountId, fields, id), id);
};
const saveCustomers = fields => {
  const accountId = route.params.accountId;
  const id = group.value?.id;
  return mutate(
    () => API.savePortfolioGroupCustomers(accountId, id, fields),
    id,
    fields
  );
};
const reloadDraft = () => {
  closeDrafts();
  load(pagination.value.page);
};
watch(
  [identity, selectedId],
  (_, previous) => {
    mutationGeneration += 1;
    if (!previous || previous[0] !== identity.value) {
      filters.query = '';
      filters.status = 'active';
    }
    closeDrafts();
    rows.value = [];
    group.value = null;
    customers.value = [];
    selectedCustomer.value = null;
    saved.value = false;
    membershipResult.value = null;
    saving.value = false;
    detailsTab.value = 'customers';
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  mutationGeneration += 1;
  controller?.abort();
});
</script>

<template>
  <section class="min-w-0 space-y-4">
    <header
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-teal-6 bg-n-teal-2 p-4"
    >
      <div class="min-w-0">
        <h2 class="break-words text-xl font-semibold">
          {{ group?.name || t('RELATIONSHIP.NAMED_PORTFOLIOS.TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HELP') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="group"
          type="button"
          :class="buttonClass"
          :disabled="loading || saving"
          @click="openNativeCustomers"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.OPEN_NATIVE_CUSTOMERS') }}
        </button>
        <button
          v-if="selectedId"
          type="button"
          :class="buttonClass"
          :disabled="saving"
          @click="openGroup()"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RETURN') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="loading || saving"
          @click="load(pagination.page)"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REFRESH') }}
        </button>
        <button
          v-if="!selectedId && canCreate"
          type="button"
          :disabled="loading || saving"
          class="rounded-lg bg-n-teal-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
          @click="openEditor(null)"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NEW') }}
        </button>
        <button
          v-if="group?.can_manage"
          type="button"
          :class="buttonClass"
          :disabled="loading || saving"
          @click="openEditor(group)"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.EDIT') }}
        </button>
      </div>
    </header>
    <p
      v-if="error"
      role="alert"
      class="break-words text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="saved"
      role="status"
      class="rounded-lg bg-n-teal-2 p-3 text-n-teal-11"
    >
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.SAVED') }}
    </p>
    <p
      v-if="loading"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <section
      v-if="saved && membershipResult && group && !error"
      class="min-w-0 rounded-xl border border-n-teal-6 bg-n-teal-2 p-4"
    >
      <h3 class="font-semibold">
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.RESULT_TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11">
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.ATOMIC_HELP') }}
      </p>
      <ul class="mt-3 grid min-w-0 gap-2 sm:grid-cols-2">
        <li
          v-for="item in membershipResult"
          :key="item.assignment_id"
          class="break-words text-sm"
        >
          {{
            t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.RESULT_ITEM', {
              id: item.assignment_id,
              state: membershipStates[item.state],
            })
          }}
        </li>
      </ul>
    </section>
    <form
      v-if="!selectedId"
      class="flex min-w-0 flex-wrap items-end gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      @submit.prevent="load(1)"
    >
      <label class="min-w-0 flex-1">
        <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.SEARCH') }}</span>
        <input
          v-model="filters.query"
          :class="inputClass"
          maxlength="100"
          :disabled="loading || saving"
      /></label>
      <label>
        <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.STATUS') }}</span>
        <select
          v-model="filters.status"
          :class="inputClass"
          :disabled="loading || saving"
        >
          <option value="active">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.STATES.active') }}
          </option>
          <option value="archived">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.STATES.archived') }}
          </option>
          <option value="all">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.ALL') }}
          </option>
        </select>
      </label>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="loading || saving"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.APPLY') }}
      </button>
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading || saving"
        @click="
          filters.query = '';
          filters.status = 'active';
          load(1);
        "
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CLEAR') }}
      </button>
    </form>
    <div
      v-if="!selectedId"
      class="grid min-w-0 gap-3 md:grid-cols-2 xl:grid-cols-3"
    >
      <article
        v-for="row in rows"
        :key="row.id"
        class="min-w-0 space-y-3 rounded-xl border border-n-teal-6 bg-n-solid-2 p-4"
      >
        <h3 class="break-words font-semibold">{{ row.name }}</h3>
        <p class="break-words text-sm text-n-slate-11">{{ row.owner_name }}</p>
        <p class="text-sm">
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.TOTAL') }}
          {{ row.customer_count ?? t('RELATIONSHIP.UNAVAILABLE') }}
        </p>
        <p
          v-if="row.access_limited"
          class="text-sm text-n-amber-11"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.LIMITED') }}
        </p>
        <button
          type="button"
          :class="buttonClass"
          :disabled="saving"
          @click="openGroup(row.id)"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.OPEN') }}
        </button>
      </article>
      <p
        v-if="!loading && !error && !rows.length"
        class="text-sm text-n-slate-11"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.EMPTY') }}
      </p>
    </div>
    <template v-if="group">
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="t('RELATIONSHIP.NAMED_PORTFOLIOS.DETAILS')"
      >
        <button
          type="button"
          :class="[
            buttonClass,
            detailsTab === 'customers' &&
              'border-n-teal-7 bg-n-teal-2 text-n-teal-11',
          ]"
          @click="detailsTab = 'customers'"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CUSTOMERS') }}
        </button>
        <button
          type="button"
          :class="[
            buttonClass,
            detailsTab === 'details' &&
              'border-n-blue-7 bg-n-blue-2 text-n-blue-11',
          ]"
          @click="detailsTab = 'details'"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.DETAILS') }}
        </button>
        <button
          type="button"
          :class="[
            buttonClass,
            detailsTab === 'goals' &&
              'border-n-violet-7 bg-n-violet-2 text-n-violet-11',
          ]"
          @click="detailsTab = 'goals'"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.TABS.goals') }}
        </button>
        <button
          type="button"
          :class="[
            buttonClass,
            detailsTab === 'workload' &&
              'border-n-amber-7 bg-n-amber-2 text-n-amber-11',
          ]"
          @click="detailsTab = 'workload'"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.TITLE') }}
        </button>
        <button
          v-if="group.can_configure"
          type="button"
          :class="[
            buttonClass,
            detailsTab === 'rules' &&
              'border-n-blue-7 bg-n-blue-2 text-n-blue-11',
          ]"
          @click="detailsTab = 'rules'"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RULES.TITLE') }}
        </button>
        <button
          v-if="group.can_read_history"
          type="button"
          :class="[
            buttonClass,
            detailsTab === 'history' &&
              'border-n-violet-7 bg-n-violet-2 text-n-violet-11',
          ]"
          @click="detailsTab = 'history'"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.HISTORY.TITLE') }}
        </button>
      </nav>
      <PortfolioGroupHistoryPanel
        v-if="detailsTab === 'history' && group.can_read_history"
        :group="group"
        :metadata="metadata"
      />
      <PortfolioGroupRulesPanel
        v-if="detailsTab === 'rules' && group.can_configure"
        :group="group"
        :metadata="metadata"
      />
      <PortfolioGroupWorkloadPanel
        v-if="detailsTab === 'workload'"
        :group="group"
      />
      <section
        v-if="detailsTab === 'details'"
        class="grid min-w-0 gap-4 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4 sm:grid-cols-2"
      >
        <div>
          <h3 class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.COORDINATOR') }}
          </h3>
          <p class="break-words">{{ group.owner_name }}</p>
        </div>
        <div>
          <h3 class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.UNIT') }}
          </h3>
          <p class="break-words">
            {{
              group.business_unit_name ||
              t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_UNIT')
            }}
          </p>
        </div>
        <div>
          <h3 class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.TEAM') }}
          </h3>
          <p class="break-words">
            {{ group.team_name || t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_TEAM') }}
          </p>
        </div>
        <div>
          <h3 class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.SEGMENT') }}
          </h3>
          <p class="break-words">
            {{
              group.segment_name ||
              t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_SEGMENT')
            }}
          </p>
        </div>
        <div class="min-w-0 sm:col-span-2">
          <h3 class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.OBJECTIVE') }}
          </h3>
          <p class="max-h-64 overflow-y-auto whitespace-pre-wrap break-words">
            {{ group.objective || '—' }}
          </p>
        </div>
      </section>
      <section
        v-if="detailsTab === 'goals'"
        class="grid min-w-0 gap-3 md:grid-cols-2"
      >
        <article
          v-for="(goal, index) in group.goals"
          :key="index"
          class="min-w-0 break-words rounded-xl border border-n-violet-6 bg-n-solid-2 p-4"
        >
          {{
            t('RELATIONSHIP.NAMED_PORTFOLIOS.GOAL_SUMMARY', {
              metric: goal.metric,
              current: goal.current ?? t('RELATIONSHIP.UNAVAILABLE'),
              target: goal.target ?? t('RELATIONSHIP.UNAVAILABLE'),
              unit: goal.unit || '',
            })
          }}
        </article>
      </section>
      <section
        v-if="detailsTab === 'customers'"
        class="min-w-0 space-y-3 rounded-xl border border-n-teal-6 bg-n-solid-2 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="text-sm">
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.TOTAL') }}
            {{ group.customer_count ?? t('RELATIONSHIP.UNAVAILABLE') }}
          </p>
          <button
            v-if="
              group.can_manage &&
              group.status === 'active' &&
              metadata.can_manage &&
              metadata.can_team
            "
            type="button"
            :class="buttonClass"
            :disabled="saving || loading"
            @click="
              closeDrafts();
              masterOpen = true;
            "
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.TITLE') }}
          </button>
          <button
            v-if="group.can_manage && group.status === 'active'"
            type="button"
            :class="buttonClass"
            :disabled="saving || loading"
            @click="openCustomers(null)"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.ADD_CUSTOMERS') }}
          </button>
        </div>
        <p
          v-if="group.access_limited"
          role="status"
          class="text-sm text-n-amber-11"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.LIMITED') }}
        </p>
        <div class="min-w-0 overflow-x-auto">
          <table class="w-full text-left text-sm">
            <thead>
              <tr>
                <th class="p-2">{{ t('RELATIONSHIP.FIELDS.customer') }}</th>
                <th class="p-2">{{ t('RELATIONSHIP.FIELDS.owner_id') }}</th>
                <th class="p-2">
                  {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.STATUS') }}
                </th>
                <th class="p-2">
                  {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CUSTOMERS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in customers"
                :key="row.id"
                class="border-t border-n-weak"
              >
                <td class="max-w-64 break-words p-2">{{ row.name }}</td>
                <td class="p-2">{{ row.owner?.name || '—' }}</td>
                <td class="p-2">{{ row.status }}</td>
                <td class="p-2">
                  <div class="flex flex-wrap gap-2">
                    <button
                      type="button"
                      :class="buttonClass"
                      @click="selectedCustomer = row.id"
                    >
                      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.OPEN_CUSTOMER') }}
                    </button>
                    <button
                      v-if="group.can_manage && group.status === 'active'"
                      type="button"
                      :class="buttonClass"
                      :disabled="saving"
                      @click="openCustomers(row)"
                    >
                      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REMOVE_CUSTOMER') }}
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p
          v-if="!customers.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_CUSTOMERS') }}
        </p>
      </section>
    </template>
    <footer
      v-if="!selectedId || (group && detailsTab === 'customers')"
      class="flex flex-wrap items-center justify-end gap-2"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading || saving || pagination.page <= 1"
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
        :disabled="loading || saving || pagination.page >= pages"
        @click="load(pagination.page + 1)"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NEXT_PAGE') }}
      </button>
    </footer>
    <PortfolioGroupEditor
      v-if="editorOpen"
      :record="editorRecord"
      :metadata="editorMetadata"
      :busy="saving"
      :error="saveError"
      :conflict="conflict"
      @close="closeDrafts"
      @save="saveGroup"
      @reload="reloadDraft"
    />
    <PortfolioGroupCustomersDialog
      v-if="customerDialog && group"
      :group="group"
      :customer="customerDialog.customer"
      :initial-customer="customerDialog.initialCustomer"
      :busy="saving"
      :error="saveError"
      :conflict="conflict"
      @close="closeDrafts"
      @save="saveCustomers"
      @reviewed="
        conflict = false;
        saveError = '';
      "
    />
    <PortfolioGroupMasterDialog
      v-if="masterOpen && group"
      :group="group"
      :metadata="metadata"
      @close="masterOpen = false"
      @review="reviewMasterCustomer"
    />
    <CustomerPanel
      v-if="selectedCustomer"
      :assignment-id="selectedCustomer"
      :metadata="metadata"
      @close="selectedCustomer = null"
      @changed="load(pagination.page)"
    />
  </section>
</template>
