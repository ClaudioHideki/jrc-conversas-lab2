<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import PolicyEditor from './PolicyEditor.vue';
import RequestDetail from './RequestDetail.vue';
import SimulatorView from './SimulatorView.vue';
import DelegationView from './DelegationView.vue';
import OwnDelegationView from './OwnDelegationView.vue';
import ResourcePicker from './ResourcePicker.vue';
import Icon from 'next/icon/Icon.vue';
import ApprovalInbox from './ApprovalInbox.vue';
import ApprovalSummary from './ApprovalSummary.vue';
import ApprovalStatus from './ApprovalStatus.vue';
import { minorAmountText } from './tierPresentation';
import { useApprovals } from './useApprovals';
import {
  capability,
  STATES,
  intent,
  auditPresentation,
  scopeLabel,
} from './model';
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const store = useStore();
const accessIdentity = computed(() =>
  JSON.stringify([route.params.accountId, authorityScope(store.getters)])
);
const viewIdentity = computed(() =>
  JSON.stringify([accessIdentity.value, route.fullPath])
);
const { state, reset, run, loadContext, list, invalidate, dispose } =
  useApprovals(() => viewIdentity.value);
let disposed = false;
let viewGeneration = 0;
let loadGeneration = 0;
let loadedAccess = null;
const captureView = () => ({
  identity: viewIdentity.value,
  generation: viewGeneration,
});
const isCurrent = context =>
  !disposed &&
  context.identity === viewIdentity.value &&
  context.generation === viewGeneration;
onBeforeUnmount(() => {
  disposed = true;
  viewGeneration += 1;
  dispose();
});
const record = ref(null);
const templatePolicy = ref(null);
const versions = ref(null);
const catalogs = ref([]);
const simulation = ref(null);
const notice = ref('');
const can = action => capability(state.context, action);
const inbox = computed(() => {
  if (
    [
      'assigned',
      'requested',
      'returned',
      'escalated',
      'all',
      'pending_scope',
    ].includes(route.query.box)
  )
    return route.query.box;
  return can('decide') ? 'assigned' : 'pending_scope';
});
const summary = ref(null);
const requestKey = ref('');
const resourceId = ref('');
const filters = ref({
  q: '',
  order: 'recent',
  state: '',
  module_key: '',
  event_key: '',
  issuer_company_id: '',
  business_unit_id: '',
  resource_type: '',
  resource_id: '',
});
const decisionIntent = intent();
const requestIntent = intent();
const adjustmentIntent = intent();
const ownDelegationIntent = intent();
const screen = computed(() => route.params.screen || 'inbox');
const id = computed(() => route.params.id);
const allowed = computed(() => {
  if (!state.context) return false;
  if (['policies', 'simulate', 'delegations'].includes(screen.value))
    return can('policy_manage');
  if (screen.value === 'history') return can('view_audit');
  if (screen.value === 'own-delegations')
    return can('delegate') || can('decide') || can('policy_manage');
  return ['request_create', 'decide', 'view_audit'].some(can);
});
const tabs = computed(() =>
  [
    { key: 'policies', show: can('policy_manage') },
    {
      key: 'inbox',
      show: ['request_create', 'decide', 'view_audit'].some(can),
    },
    { key: 'simulate', show: can('policy_manage') },
    { key: 'delegations', show: can('policy_manage') },
    {
      key: 'own-delegations',
      show: can('delegate') || can('decide') || can('policy_manage'),
    },
    { key: 'history', show: can('view_audit') },
  ].filter(tab => tab.show)
);
const navigate = (target, targetId, query = {}) =>
  router.push({
    name: 'jrc_approvals',
    params: { accountId: state.accountId, screen: target, id: targetId },
    query,
  });

const workspaceTabs = computed(() =>
  [
    {
      key: 'pending',
      target: 'inbox',
      box: can('decide') ? 'assigned' : 'pending_scope',
      icon: 'i-lucide-inbox',
      show: ['request_create', 'decide', 'view_audit'].some(can),
    },
    {
      key: 'requested',
      target: 'inbox',
      box: 'requested',
      icon: 'i-lucide-send',
      show: ['request_create', 'decide', 'view_audit'].some(can),
    },
    {
      key: 'history',
      target: 'history',
      icon: 'i-lucide-history',
      show: can('view_audit'),
    },
    {
      key: 'policies',
      target: 'policies',
      icon: 'i-lucide-list-checks',
      show: can('policy_manage'),
    },
    {
      key: 'delegations',
      target: 'own-delegations',
      icon: 'i-lucide-users',
      show: can('delegate') || can('decide') || can('policy_manage'),
    },
  ].filter(tab => tab.show)
);
const activeTab = computed(() => {
  if (screen.value === 'inbox')
    return inbox.value === 'requested' ? 'requested' : 'pending';
  if (['own-delegations', 'delegations'].includes(screen.value))
    return 'delegations';
  return screen.value === 'simulate' ? 'policies' : screen.value;
});
const loadSummary = async () => {
  const params = {
    ...filters.value,
    time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  };
  delete params.state;
  if (state.error) {
    summary.value = null;
    return;
  }
  const result = await run(api => api.get('requests/summary', params));
  if (result) {
    summary.value = result.data;
  } else if ([401, 403, 404].includes(state.error?.status)) {
    summary.value = null;
    state.rows = [];
    record.value = null;
  }
};
const selectRequest = value =>
  navigate('inbox', value, {
    ...route.query,
    page: state.page.page,
    box: inbox.value,
  });
const load = async () => {
  if (disposed) return;
  const context = captureView();
  loadGeneration += 1;
  const request = loadGeneration;
  record.value = null;
  templatePolicy.value = null;
  versions.value = null;
  simulation.value = null;
  state.rows = [];
  state.error = null;
  if (!allowed.value) return;
  const params = {
    ...filters.value,
    page: Number(route.query.page || 1),
    per_page: 25,
  };
  if (screen.value !== 'inbox') {
    delete params.q;
    delete params.order;
  }
  Object.keys(params).forEach(key => {
    if (params[key] === '') delete params[key];
  });
  if (screen.value === 'policies') {
    if (id.value && id.value !== 'new') {
      const result = await run(api => api.get(`policies/${id.value}`));
      if (result) record.value = result.data;
    } else if (id.value === 'new' && route.query.copy !== undefined) {
      const source = route.query.copy;
      if (
        typeof source !== 'string' ||
        !/^[1-9]\d*$/.test(source) ||
        !Number.isSafeInteger(Number(source))
      ) {
        state.error = { status: 422, code: 'INVALID_INPUT' };
        return;
      }
      const result = await run(api => api.get(`policies/${source}`));
      if (!result) return;
      templatePolicy.value = result.data;
    } else if (!id.value) await list('policies', params);
  } else if (screen.value === 'inbox') {
    if (inbox.value === 'assigned') {
      params.assigned_to_me = true;
      params.state = 'pending';
    }
    if (inbox.value === 'pending_scope') params.state = 'pending';
    if (inbox.value === 'requested') params.requested_by_me = true;
    if (inbox.value === 'returned') params.state = 'returned';
    if (inbox.value === 'escalated') params.state = 'escalated';
    await list('requests', params);
    if (!isCurrent(context) || request !== loadGeneration) return;
    if (state.error) {
      summary.value = null;
      return;
    }
    if (id.value) {
      const result = await run(api => api.get('requests/' + id.value));
      if (result) record.value = result.data;
    }
    if (isCurrent(context) && request === loadGeneration) await loadSummary();
  } else if (screen.value === 'history') {
    if (id.value) await list(`requests/${id.value}/audit`, params);
    else await list('requests', params);
  } else if (screen.value === 'delegations') await list('delegations', params);
  else if (screen.value === 'own-delegations')
    await list('own_delegations', params);
  if (!isCurrent(context) || request !== loadGeneration) return;
  if (['simulate', 'policies'].includes(screen.value) && can('policy_manage')) {
    const scope = state.context.scopes.find(row =>
      row.capabilities.includes('policy_manage')
    );
    const result = await run(api =>
      api.get('catalogs', {
        issuer_company_id: scope.issuer_company_id,
        business_unit_id: scope.business_unit_id,
      })
    );
    if (result) catalogs.value = result.data;
  }
};
const applyInboxFilters = async () => {
  const query = { box: inbox.value, page: 1 };
  Object.entries(filters.value).forEach(([key, value]) => {
    if (value !== '') query[key] = value;
  });
  const destination = {
    name: 'jrc_approvals',
    params: { accountId: state.accountId, screen: 'inbox' },
    query,
  };
  if (router.resolve(destination).fullPath === route.fullPath) {
    await load();
  } else await router.push(destination);
};
const clearInboxFilters = () => {
  Object.keys(filters.value).forEach(key => {
    filters.value[key] = key === 'order' ? 'recent' : '';
  });
  return applyInboxFilters();
};

const refresh = async () => {
  if (disposed || state.loading) return;
  const context = captureView();
  if (!state.context) await loadContext();
  if (isCurrent(context) && state.context) await load();
};
watch(
  viewIdentity,
  async () => {
    viewGeneration += 1;
    const context = captureView();
    const account = Number(route.params.accountId);
    invalidate();
    notice.value = '';
    catalogs.value = [];
    record.value = null;
    templatePolicy.value = null;
    versions.value = null;
    simulation.value = null;
    state.rows = [];
    if (loadedAccess !== accessIdentity.value || !state.context) {
      const changedAccess = loadedAccess !== accessIdentity.value;
      loadedAccess = accessIdentity.value;
      reset(account);
      if (changedAccess) {
        summary.value = null;
        filters.value = {
          q: '',
          order: 'recent',
          state: '',
          module_key: '',
          event_key: '',
          issuer_company_id: '',
          business_unit_id: '',
          resource_type: '',
          resource_id: '',
        };
        requestKey.value = '';
        resourceId.value = '';
      }
      await loadContext();
    }
    if (!isCurrent(context)) return;
    Object.keys(filters.value).forEach(key => {
      if (typeof route.query[key] === 'string')
        filters.value[key] = route.query[key];
      else if (screen.value === 'inbox')
        filters.value[key] = key === 'order' ? 'recent' : '';
    });
    if (isCurrent(context) && state.context) await load();
  },
  { immediate: true, flush: 'sync' }
);
const canSubmit = () => !disposed && allowed.value && !state.loading;
const savePolicy = async policy => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api =>
    id.value === 'new'
      ? api.post('policies', { policy })
      : api.patch(`policies/${id.value}`, {
          policy,
          expected_version: record.value.lock_version,
        })
  );
  if (!isCurrent(context)) return;
  if (result) {
    record.value = result.data;
    notice.value = t('JRC_APPROVALS.saved');
    if (id.value === 'new') await navigate('policies', result.data.id);
  }
};
const operate = async operation => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api =>
    api.post(`policies/${id.value}/${operation}`, {
      expected_version: record.value.lock_version,
    })
  );
  if (!isCurrent(context)) return;
  if (result) {
    record.value = result.data;
    notice.value = t('JRC_APPROVALS.saved');
  }
};
const loadVersions = async page => {
  const result = await run(api =>
    api.get(`policies/${id.value}/versions`, { page, per_page: 25 })
  );
  if (result)
    versions.value = {
      rows: result.data,
      total: Number(result.headers['x-total-count']),
      page,
    };
};
const decide = async decision => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api =>
    api.post(`requests/${id.value}/decide`, {
      decision: decisionIntent(
        decision,
        `${accessIdentity.value}:request:${id.value}`
      ),
    })
  );
  if (!isCurrent(context)) return;
  if (result) {
    await load();
    if (!isCurrent(context)) return;
    notice.value = t('JRC_APPROVALS.saved');
  } else if (state.error?.status === 409) {
    const error = state.error;
    await load();
    if (!isCurrent(context)) return;
    state.error = error;
    notice.value = t('JRC_APPROVALS.concurrent');
  } else if ([401, 403, 404].includes(state.error?.status)) {
    record.value = null;
    state.rows = [];
  }
};
const simulate = async body => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api => api.post('requests/simulate', body));
  if (result && isCurrent(context)) simulation.value = result.data;
};
const adjust = async body => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api =>
    api.post(`requests/${id.value}/adjust`, {
      adjustment: adjustmentIntent(
        body,
        `${accessIdentity.value}:adjust:${id.value}`
      ),
    })
  );
  if (!isCurrent(context)) return;
  if (result) {
    const access = accessIdentity.value;
    const target = result.data.request?.id;
    await navigate('inbox', target);
    if (
      disposed ||
      access !== accessIdentity.value ||
      screen.value !== 'inbox' ||
      String(id.value) !== String(target)
    )
      return;
    const destination = captureView();
    await load();
    if (isCurrent(destination))
      notice.value = t('JRC_APPROVALS.adjustment.saved');
  } else if (state.error?.status === 409) {
    const error = state.error;
    await load();
    if (!isCurrent(context)) return;
    state.error = error;
  } else if ([401, 403, 404].includes(state.error?.status)) {
    record.value = null;
    state.rows = [];
  }
};
const grant = async delegation => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api => api.post('delegations', { delegation }));
  if (!isCurrent(context)) return;
  if (result) {
    await load();
    if (!isCurrent(context)) return;
    notice.value = t('JRC_APPROVALS.saved');
  }
};
const revoke = async grantId => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api => api.revoke(grantId));
  if (!isCurrent(context)) return;
  if (result) {
    await load();
    if (!isCurrent(context)) return;
    notice.value = t('JRC_APPROVALS.revoked');
  }
};
const grantOwn = async delegation => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api =>
    api.post('own_delegations', {
      delegation: ownDelegationIntent(
        delegation,
        `${accessIdentity.value}:own-delegation`
      ),
    })
  );
  if (!isCurrent(context)) return;
  if (result) {
    await load();
    if (!isCurrent(context)) return;
    notice.value = t('JRC_APPROVALS.saved');
  }
};
const revokeOwn = async grantId => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api => api.revokeOwn(grantId));
  if (!isCurrent(context)) return;
  if (result) {
    await load();
    if (!isCurrent(context)) return;
    notice.value = t('JRC_APPROVALS.revoked');
  }
};
const createRequest = async () => {
  if (!canSubmit()) return;
  const context = captureView();
  const result = await run(api =>
    api.post('requests', {
      approval_request: requestIntent(
        {
          key: requestKey.value,
          resource_id: resourceId.value,
        },
        accessIdentity.value
      ),
    })
  );
  if (!isCurrent(context)) return;
  if (result) {
    await load();
    if (!isCurrent(context)) return;
    notice.value = result.data.length
      ? t('JRC_APPROVALS.saved')
      : t('JRC_APPROVALS.notRequired');
  }
};
const auditRows = computed(() => state.rows.map(auditPresentation));
const pageTo = page =>
  navigate(screen.value, id.value, { ...route.query, page });
const errorText = computed(() => {
  if (state.error?.status === 422) {
    if (state.error.code === 'INVALID_DELEGATION')
      return t('JRC_APPROVALS.invalidDelegation');
    if (
      [
        'INVALID_TIER_DEFINITION',
        'TIER_OVERLAP',
        'TIER_GAP',
        'TIER_NOT_APPLICABLE',
        'INVALID_ADJUSTMENT_FIELDS',
        'SOURCE_LOCKED',
        'NO_ADJUSTMENT_CHANGE',
        'ADJUSTMENT_OUTSIDE_POLICY',
        'ADJUSTMENT_NOT_SUPPORTED',
        'INVALID_COMMERCIAL_TERMS',
        'STEP_NOT_CURRENT',
      ].includes(state.error.code)
    )
      return t(`JRC_APPROVALS.domainErrors.${state.error.code}`);
  }
  return t(`JRC_APPROVALS.error${state.error?.status || 'Network'}`);
});
</script>

<template>
  <section
    aria-labelledby="approval-center-title"
    class="h-full min-w-0 overflow-auto bg-n-background p-3 text-n-slate-12 md:p-6"
  >
    <div class="mx-auto min-w-0 max-w-[1600px] space-y-5">
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div class="flex min-w-0 items-center gap-3">
          <span
            class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
            ><Icon
              icon="i-lucide-shield-check"
              class="size-7"
          /></span>
          <div class="min-w-0">
            <p class="mb-1 text-xs text-n-slate-11">
              {{ t('JRC_APPROVALS.administration') }} /
              {{ t('JRC_APPROVALS.title') }}
            </p>
            <h1
              id="approval-center-title"
              class="break-words text-xl font-bold sm:text-2xl"
            >
              {{ t('JRC_APPROVALS.title') }}
            </h1>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ t('JRC_APPROVALS.workspace.subtitle') }}
            </p>
          </div>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button
            v-if="can('policy_manage')"
            :label="t('JRC_APPROVALS.workspace.configure')"
            icon="i-lucide-settings"
            variant="faded"
            :disabled="state.loading"
            @click="navigate('policies')"
          />
          <Button
            :label="t('JRC_APPROVALS.refresh')"
            icon="i-lucide-refresh-cw"
            variant="ghost"
            :disabled="state.loading"
            @click="refresh"
          />
        </div>
      </header>
      <nav
        :aria-label="t('JRC_APPROVALS.title')"
        class="flex min-w-0 gap-2 overflow-x-auto rounded-xl border border-n-weak bg-n-solid-2 p-2"
      >
        <button
          v-for="tab in workspaceTabs"
          :key="tab.key"
          type="button"
          class="inline-flex shrink-0 items-center gap-2 rounded-lg border px-3 py-2.5 text-sm font-medium focus-visible:outline-blue-500"
          :class="
            activeTab === tab.key
              ? 'border-n-blue-9 bg-n-blue-9 text-white shadow-sm'
              : 'border-transparent bg-n-solid-2 text-n-slate-12 hover:bg-n-alpha-2'
          "
          :aria-current="activeTab === tab.key ? 'page' : undefined"
          @click="
            navigate(tab.target, undefined, tab.box ? { box: tab.box } : {})
          "
        >
          <Icon
            :icon="tab.icon"
            class="size-4"
          />{{ t('JRC_APPROVALS.workspace.tabs.' + tab.key) }}
        </button>
      </nav>
      <ApprovalSummary
        v-if="screen === 'inbox' && allowed"
        :summary="summary"
        :loading="state.loading"
      />

      <p
        v-if="state.loading"
        role="status"
        class="rounded-xl bg-n-alpha-2 p-3"
      >
        {{ t('JRC_APPROVALS.loading') }}
      </p>
      <div
        v-if="state.error"
        role="alert"
        class="space-y-2 rounded-xl border border-n-ruby-6 bg-n-ruby-2 p-3"
      >
        <p>{{ errorText }}</p>
        <p
          v-if="state.error.code"
          class="text-xs"
        >
          {{ t('JRC_APPROVALS.reference') }}: {{ state.error.code }}
        </p>
        <ul>
          <li
            v-for="error in state.error.details || []"
            :key="error"
          >
            {{ error }}
          </li>
        </ul>
        <Button
          v-if="state.error.status === 409"
          :label="t('JRC_APPROVALS.refresh')"
          variant="faded"
          @click="load"
        />
      </div>
      <p
        v-if="notice"
        role="status"
        class="rounded-xl bg-n-teal-3 p-3 text-sm"
      >
        {{ notice }}
      </p>
      <p
        v-if="state.context && !allowed"
        role="alert"
      >
        {{ t('JRC_APPROVALS.denied') }}
      </p>
      <p v-if="state.context && !tabs.length">
        {{ t('JRC_APPROVALS.denied') }}
      </p>
      <template v-if="allowed">
        <div
          v-if="
            ['policies', 'simulate', 'delegations', 'own-delegations'].includes(
              screen
            )
          "
          class="flex flex-wrap gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-3"
        >
          <Button
            v-if="can('policy_manage')"
            :label="t('JRC_APPROVALS.simulate')"
            variant="faded"
            @click="navigate('simulate')"
          />
          <Button
            v-if="can('policy_manage')"
            :label="t('JRC_APPROVALS.workspace.ruleDelegations')"
            variant="faded"
            @click="navigate('delegations')"
          />
          <Button
            v-if="can('delegate') || can('decide') || can('policy_manage')"
            :label="t('JRC_APPROVALS.own-delegations')"
            variant="faded"
            @click="navigate('own-delegations')"
          />
        </div>
        <Button
          v-if="id"
          :label="t('JRC_APPROVALS.back')"
          variant="faded"
          @click="navigate(screen)"
        />
        <PolicyEditor
          v-if="screen === 'policies' && (id === 'new' || record)"
          :key="`${state.accountId}:${id}`"
          :policy="record"
          :template-policy="templatePolicy"
          :context="state.context"
          :busy="state.loading"
          @save="savePolicy"
          @operation="operate"
          @versions="loadVersions(1)"
          @duplicate="navigate('policies', 'new', { copy: String(record.id) })"
        />
        <section
          v-if="versions"
          class="space-y-3"
        >
          <h2 class="text-xl font-semibold">
            {{ t('JRC_APPROVALS.versions') }}
          </h2>
          <article
            v-for="version in versions.rows"
            :key="version.id"
            class="space-y-2 rounded-xl border border-n-weak p-4"
          >
            <h3 class="font-semibold">
              {{ t('JRC_APPROVALS.versionPrefix') }}{{ version.version }} ·
              {{ version.publisher_name }}
            </h3>
            <p class="text-xs">{{ version.created_at }}</p>
            <p class="break-all font-mono text-xs">
              {{ t('JRC_APPROVALS.hash') }} {{ version.digest }}
            </p>
            <p class="text-sm">
              {{ version.definition.execution }} ·
              {{ version.definition.selection.mode }} ·
              {{ version.definition.selection.priority }}
            </p>
            <p
              v-for="step in version.definition.steps"
              :key="step.code"
              class="text-sm"
            >
              {{ step.code }} · {{ step.mode }} ·
              {{ t('JRC_APPROVALS.quorum') }} {{ step.quorum }}
            </p>
          </article>
          <div class="flex gap-3">
            <Button
              :label="t('JRC_APPROVALS.previous')"
              :disabled="versions.page <= 1"
              @click="loadVersions(versions.page - 1)"
            /><Button
              :label="t('JRC_APPROVALS.next')"
              :disabled="versions.page * 25 >= versions.total"
              @click="loadVersions(versions.page + 1)"
            />
          </div>
        </section>
        <section
          v-if="screen === 'inbox'"
          class="space-y-4"
        >
          <form
            class="grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-3 sm:grid-cols-2 xl:grid-cols-4"
            @submit.prevent="applyInboxFilters"
          >
            <label class="min-w-0 text-xs font-medium text-n-slate-11"
              >{{ t('JRC_APPROVALS.workspace.search')
              }}<input
                v-model="filters.q"
                type="search"
                maxlength="200"
                :placeholder="t('JRC_APPROVALS.workspace.searchPlaceholder')"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-background px-3 py-2.5 text-sm text-n-slate-12"
            /></label>
            <label class="min-w-0 text-xs font-medium text-n-slate-11"
              >{{ t('JRC_APPROVALS.workspace.module')
              }}<select
                v-model="filters.module_key"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-background px-3 py-2.5 text-sm text-n-slate-12"
              >
                <option value="">
                  {{ t('JRC_APPROVALS.workspace.allModules') }}
                </option>
                <option
                  v-for="key in [
                    'crm',
                    'contracts',
                    'backoffice',
                    'relationship',
                    'service_desk',
                  ]"
                  :key="key"
                  :value="key"
                >
                  {{ t('JRC_APPROVALS.workspace.modules.' + key) }}
                </option>
              </select></label
            >
            <label class="min-w-0 text-xs font-medium text-n-slate-11"
              >{{ t('JRC_APPROVALS.scope')
              }}<select
                v-model="filters.issuer_company_id"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-background px-3 py-2.5 text-sm text-n-slate-12"
              >
                <option value="">
                  {{ t('JRC_APPROVALS.workspace.authorizedScope') }}
                </option>
                <option
                  v-for="scope in state.context.scopes.filter(
                    row => row.issuer_company_id && !row.business_unit_id
                  )"
                  :key="scope.issuer_company_id"
                  :value="scope.issuer_company_id"
                >
                  {{ scope.company_name }}
                </option>
              </select></label
            >
            <label class="min-w-0 text-xs font-medium text-n-slate-11"
              >{{ t('JRC_APPROVALS.workspace.order')
              }}<select
                v-model="filters.order"
                class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-background px-3 py-2.5 text-sm text-n-slate-12"
              >
                <option value="recent">
                  {{ t('JRC_APPROVALS.workspace.recent') }}
                </option>
                <option value="oldest">
                  {{ t('JRC_APPROVALS.workspace.oldest') }}
                </option>
              </select></label
            >
            <div
              class="flex flex-wrap items-center gap-2 sm:col-span-2 xl:col-span-4"
            >
              <Button
                type="submit"
                :label="t('JRC_APPROVALS.apply')"
                :disabled="state.loading"
              />
              <Button
                :label="t('JRC_APPROVALS.workspace.clearFilters')"
                variant="ghost"
                :disabled="state.loading"
                @click="clearInboxFilters"
              />
              <label
                class="flex min-w-0 flex-wrap items-center gap-2 text-xs text-n-slate-11 sm:ml-auto"
                >{{ t('JRC_APPROVALS.workspace.queue')
                }}<select
                  :value="inbox"
                  class="min-w-0 rounded-lg border border-n-weak bg-n-background p-2 text-n-slate-12"
                  @change="
                    navigate('inbox', undefined, {
                      ...route.query,
                      page: 1,
                      box: $event.target.value,
                    })
                  "
                >
                  <option
                    v-for="name in [
                      'assigned',
                      'requested',
                      'returned',
                      'escalated',
                      'all',
                      'pending_scope',
                    ]"
                    :key="name"
                    :value="name"
                  >
                    {{
                      name === 'pending_scope'
                        ? t('JRC_APPROVALS.workspace.authorizedPending')
                        : t('JRC_APPROVALS.' + name)
                    }}
                  </option>
                </select></label
              >
            </div>
            <details class="min-w-0 sm:col-span-2 xl:col-span-4">
              <summary
                class="cursor-pointer text-xs font-medium text-n-slate-11"
              >
                {{ t('JRC_APPROVALS.workspace.moreFilters') }}
              </summary>
              <div class="mt-3 grid gap-3 sm:grid-cols-2">
                <label
                  v-for="field in [
                    'event_key',
                    'business_unit_id',
                    'resource_type',
                    'resource_id',
                  ]"
                  :key="field"
                  class="text-xs"
                  >{{ t('JRC_APPROVALS.' + field)
                  }}<input
                    v-model="filters[field]"
                    class="mt-1 w-full rounded-lg border border-n-weak bg-n-background p-2 text-sm"
                /></label>
              </div>
            </details>
          </form>
          <ApprovalInbox
            :rows="state.rows"
            :request="record"
            :context="state.context"
            :loading="state.loading"
            :show-detail="!!id"
            @select="selectRequest"
            @back="navigate('inbox', undefined, { ...route.query, box: inbox })"
          >
            <template #detail>
              <RequestDetail
                v-if="record"
                :key="`${accessIdentity}:${record.id}`"
                :request="record"
                :error="state.error ? errorText : ''"
                :error-state="state.error"
                :context="state.context"
                :busy="state.loading"
                :audit-allowed="
                  capability(
                    state.context,
                    'view_audit',
                    record.issuer_company_id,
                    record.business_unit_id
                  )
                "
                @decide="decide"
                @adjust="adjust"
                @audit="navigate('history', record.id)"
                @refresh="refresh"
              />
            </template>
          </ApprovalInbox>
          <details
            v-if="can('request_create')"
            class="rounded-xl border border-n-weak bg-n-solid-2 p-4"
          >
            <summary class="cursor-pointer text-sm font-semibold">
              {{ t('JRC_APPROVALS.newRequest') }}
            </summary>
            <form
              v-if="can('request_create')"
              class="space-y-3 rounded-xl border border-n-weak p-4"
              @submit.prevent="createRequest"
            >
              <h3 class="font-semibold">{{ t('JRC_APPROVALS.newRequest') }}</h3>
              <label class="block text-sm"
                >{{ t('JRC_APPROVALS.event')
                }}<select
                  v-model="requestKey"
                  class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
                >
                  <option value="">{{ t('JRC_APPROVALS.select') }}</option>
                  <option
                    v-for="key in [
                      'crm.deal_price',
                      'crm.proposal_send',
                      'crm.proposal_convert',
                      'crm.order_price',
                      'backoffice.release',
                      'contracts.company_signature',
                    ]"
                    :key="key"
                  >
                    {{ key }}
                  </option>
                </select></label
              ><ResourcePicker
                v-model="resourceId"
                :account-id="state.accountId"
                :resource-key="requestKey"
              /><Button
                type="submit"
                :disabled="state.loading || !resourceId || !requestKey"
                :label="t('JRC_APPROVALS.newRequest')"
              />
            </form>
          </details>
        </section>
        <SimulatorView
          v-if="screen === 'simulate'"
          :context="state.context"
          :catalogs="catalogs"
          :result="simulation"
          :busy="state.loading"
          @simulate="simulate"
        />
        <DelegationView
          v-if="screen === 'delegations'"
          :context="state.context"
          :rows="state.rows"
          :busy="state.loading"
          @create="grant"
          @revoke="revoke"
        />
        <OwnDelegationView
          v-if="screen === 'own-delegations'"
          :context="state.context"
          :rows="state.rows"
          :busy="state.loading"
          @create="grantOwn"
          @revoke="revokeOwn"
        />
        <section
          v-if="screen === 'history' && id"
          class="space-y-3"
        >
          <h2 class="text-xl font-semibold">
            {{ t('JRC_APPROVALS.history') }} #{{ id }}
          </h2>
          <article
            v-for="event in auditRows"
            :key="event.id"
            class="space-y-1 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm"
          >
            <h3 class="font-medium">{{ event.event }}</h3>
            <p>
              {{ t('JRC_APPROVALS.actor') }} #{{ event.actor }} · {{ event.at }}
            </p>
            <p v-if="event.state">{{ event.state }}</p>
            <p
              v-if="event.adjustment"
              class="break-words rounded-lg bg-n-teal-3 p-3 text-n-teal-11"
            >
              {{ t('JRC_APPROVALS.adjustment.summary') }}:
              {{
                t('JRC_APPROVALS.adjustment.values', {
                  before: minorAmountText(event.adjustment.before),
                  after: minorAmountText(event.adjustment.after),
                  currency: event.adjustment.currency || '',
                })
              }}
            </p>
            <p
              v-if="event.reason"
              class="whitespace-pre-wrap"
            >
              {{ event.reason }}
            </p>
            <p v-if="event.cycle">
              {{ t('JRC_APPROVALS.cycle') }} {{ event.cycle }}
            </p>
          </article>
          <p v-if="!state.rows.length && !state.loading">
            {{ t('JRC_APPROVALS.empty') }}
          </p>
        </section>
        <template v-if="!id && ['policies', 'history'].includes(screen)">
          <div class="flex flex-wrap gap-2">
            <Button
              v-if="screen === 'policies'"
              :label="t('JRC_APPROVALS.newPolicy')"
              @click="navigate('policies', 'new')"
            />
          </div>
          <form
            class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 sm:grid-cols-2 lg:grid-cols-4"
            @submit.prevent="
              pageTo(1);
              load();
            "
          >
            <label class="text-sm"
              >{{ t('JRC_APPROVALS.state')
              }}<select
                v-model="filters.state"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
              >
                <option value="">{{ t('JRC_APPROVALS.all') }}</option>
                <option
                  v-for="value in screen === 'policies'
                    ? ['draft', 'validated', 'published', 'retired']
                    : STATES"
                  :key="value"
                >
                  {{ value }}
                </option>
              </select></label
            ><label
              v-for="field in [
                'module_key',
                'event_key',
                'issuer_company_id',
                'business_unit_id',
                ...(screen === 'policies'
                  ? []
                  : ['resource_type', 'resource_id']),
              ]"
              :key="field"
              class="text-sm"
              >{{ t(`JRC_APPROVALS.${field}`)
              }}<input
                v-model="filters[field]"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2" /></label
            ><Button
              type="submit"
              :label="t('JRC_APPROVALS.apply')"
              :disabled="state.loading"
            />
          </form>
          <p v-if="!state.rows.length && !state.loading">
            {{ t('JRC_APPROVALS.empty') }}
          </p>
          <div class="overflow-x-auto rounded-xl border border-n-weak">
            <table
              v-if="state.rows.length"
              class="w-full text-left text-sm"
            >
              <caption class="sr-only">
                {{
                  t(`JRC_APPROVALS.${screen}`)
                }}
              </caption>
              <thead class="bg-n-alpha-2">
                <tr>
                  <th class="p-3">{{ t('JRC_APPROVALS.name') }}</th>
                  <th class="p-3">{{ t('JRC_APPROVALS.scope') }}</th>
                  <th class="p-3">{{ t('JRC_APPROVALS.event') }}</th>
                  <th class="p-3">{{ t('JRC_APPROVALS.state') }}</th>
                  <th class="p-3">{{ t('JRC_APPROVALS.version') }}</th>
                  <th class="p-3">{{ t('JRC_APPROVALS.actions') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in state.rows"
                  :key="row.id"
                  class="border-t border-n-weak"
                >
                  <td class="p-3">
                    <p>{{ row.name || row.policy_name }} #{{ row.id }}</p>
                    <p class="text-xs text-n-slate-11">
                      {{
                        row.code || `${row.resource_type} #${row.resource_id}`
                      }}
                    </p>
                    <p
                      v-if="row.author_name"
                      class="text-xs text-n-slate-11"
                    >
                      {{ t('JRC_APPROVALS.author') }}: {{ row.author_name }}
                    </p>
                    <p
                      v-if="row.requester_name"
                      class="text-xs"
                    >
                      {{ row.requester_name }}
                    </p>
                  </td>
                  <td class="p-3">
                    {{
                      scopeLabel(state.context, row) ||
                      t('JRC_APPROVALS.groupScope')
                    }}
                  </td>
                  <td class="p-3">{{ row.module_key }}.{{ row.event_key }}</td>
                  <td class="p-3">
                    <span class="rounded-full bg-n-alpha-2 px-2 py-1"
                      ><ApprovalStatus :state="row.state"
                    /></span>
                    <p
                      v-if="screen === 'policies'"
                      class="mt-1 text-xs"
                    >
                      {{
                        row.enabled
                          ? t('JRC_APPROVALS.active')
                          : t('JRC_APPROVALS.inactive')
                      }}
                    </p>
                    <p
                      v-else
                      class="mt-1 text-xs"
                    >
                      {{ row.expires_at }}
                      <span
                        v-for="stage in row.stages || []"
                        :key="stage.code"
                        class="block"
                        >{{ stage.code }} · {{ stage.approved_count }}/{{
                          stage.quorum
                        }}</span
                      >
                    </p>
                  </td>
                  <td class="p-3">
                    {{ row.current_version || row.policy_version || '—' }}
                    <p
                      v-if="row.draft_definition"
                      class="text-xs"
                    >
                      {{ row.draft_definition.selection.priority }} ·
                      {{ row.draft_definition.selection.mode }}
                    </p>
                  </td>
                  <td class="p-3">
                    <Button
                      :label="t('JRC_APPROVALS.open')"
                      variant="faded"
                      @click="
                        navigate(
                          screen === 'history' ? 'history' : screen,
                          row.id
                        )
                      "
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
        <footer
          v-if="!id || ['inbox', 'history'].includes(screen)"
          class="flex flex-wrap items-center gap-3 text-sm"
        >
          <span
            >{{ t('JRC_APPROVALS.total') }} {{ state.page.total }} ·
            {{ t('JRC_APPROVALS.page') }} {{ state.page.page }}</span
          ><Button
            variant="faded"
            :label="t('JRC_APPROVALS.previous')"
            :disabled="state.loading || state.page.page <= 1"
            @click="pageTo(state.page.page - 1)"
          /><Button
            variant="faded"
            :label="t('JRC_APPROVALS.next')"
            :disabled="
              state.loading ||
              state.page.page * state.page.limit >= state.page.total
            "
            @click="pageTo(state.page.page + 1)"
          />
        </footer>
      </template>
    </div>
  </section>
</template>
