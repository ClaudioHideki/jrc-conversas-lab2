<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import PolicyEditor from './PolicyEditor.vue';
import RequestDetail from './RequestDetail.vue';
import SimulatorView from './SimulatorView.vue';
import DelegationView from './DelegationView.vue';
import ResourcePicker from './ResourcePicker.vue';
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
const { state, reset, run, loadContext, list } = useApprovals();
const record = ref(null);
const versions = ref(null);
const catalogs = ref([]);
const simulation = ref(null);
const notice = ref('');
const inbox = ref('assigned');
const requestKey = ref('');
const resourceId = ref('');
const filters = ref({
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
const screen = computed(() => route.params.screen || 'inbox');
const id = computed(() => route.params.id);
const can = action => capability(state.context, action);
const allowed = computed(() => {
  if (!state.context) return false;
  if (['policies', 'simulate', 'delegations'].includes(screen.value))
    return can('policy_manage');
  if (screen.value === 'history') return can('view_audit');
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
    { key: 'history', show: can('view_audit') },
  ].filter(tab => tab.show)
);
const navigate = (target, targetId, query = {}) =>
  router.push({
    name: 'jrc_approvals',
    params: { accountId: state.accountId, screen: target, id: targetId },
    query,
  });
const load = async () => {
  record.value = null;
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
  Object.keys(params).forEach(key => {
    if (params[key] === '') delete params[key];
  });
  if (screen.value === 'policies') {
    if (id.value && id.value !== 'new') {
      const result = await run(api => api.get(`policies/${id.value}`));
      if (result) record.value = result.data;
    } else if (!id.value) await list('policies', params);
  } else if (screen.value === 'inbox') {
    if (id.value) {
      const result = await run(api => api.get(`requests/${id.value}`));
      if (result) record.value = result.data;
    } else {
      if (inbox.value === 'assigned') {
        params.assigned_to_me = true;
        params.state = 'pending';
      }
      if (inbox.value === 'requested') params.requested_by_me = true;
      if (inbox.value === 'returned') params.state = 'returned';
      if (inbox.value === 'escalated') params.state = 'escalated';
      await list('requests', params);
    }
  } else if (screen.value === 'history') {
    if (id.value) await list(`requests/${id.value}/audit`, params);
    else await list('requests', params);
  } else if (screen.value === 'delegations') await list('delegations', params);
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
watch(
  () => route.fullPath,
  async () => {
    const account = Number(route.params.accountId);
    notice.value = '';
    catalogs.value = [];
    if (state.accountId !== account) {
      reset(account);
      filters.value = {
        state: '',
        module_key: '',
        event_key: '',
        issuer_company_id: '',
        business_unit_id: '',
        resource_type: '',
        resource_id: '',
      };
      await loadContext();
    }
    await load();
  },
  { immediate: true }
);
const savePolicy = async policy => {
  const result = await run(api =>
    id.value === 'new'
      ? api.post('policies', { policy })
      : api.patch(`policies/${id.value}`, {
          policy,
          expected_version: record.value.lock_version,
        })
  );
  if (result) {
    record.value = result.data;
    notice.value = t('JRC_APPROVALS.saved');
    if (id.value === 'new') await navigate('policies', result.data.id);
  }
};
const operate = async operation => {
  const result = await run(api =>
    api.post(`policies/${id.value}/${operation}`, {
      expected_version: record.value.lock_version,
    })
  );
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
  const result = await run(api =>
    api.post(`requests/${id.value}/decide`, {
      decision: decisionIntent(
        decision,
        `${state.accountId}:request:${id.value}`
      ),
    })
  );
  if (result) {
    await load();
    notice.value = t('JRC_APPROVALS.saved');
  } else if (state.error?.status === 409) {
    const error = state.error;
    await load();
    state.error = error;
    notice.value = t('JRC_APPROVALS.concurrent');
  }
};
const simulate = async body => {
  const result = await run(api => api.post('requests/simulate', body));
  if (result) simulation.value = result.data;
};
const grant = async delegation => {
  const result = await run(api => api.post('delegations', { delegation }));
  if (result) {
    await load();
    notice.value = t('JRC_APPROVALS.saved');
  }
};
const revoke = async grantId => {
  const result = await run(api => api.revoke(grantId));
  if (result) {
    await load();
    notice.value = t('JRC_APPROVALS.revoked');
  }
};
const createRequest = async () => {
  const result = await run(api =>
    api.post('requests', {
      approval_request: requestIntent(
        {
          key: requestKey.value,
          resource_id: resourceId.value,
        },
        String(state.accountId)
      ),
    })
  );
  if (result) {
    await load();
    notice.value = result.data.length
      ? t('JRC_APPROVALS.saved')
      : t('JRC_APPROVALS.notRequired');
  }
};
const auditRows = computed(() => state.rows.map(auditPresentation));
const pageTo = page =>
  navigate(screen.value, id.value, { ...route.query, page });
const errorText = computed(() =>
  t(`JRC_APPROVALS.error${state.error?.status || 'Network'}`)
);
</script>

<template>
  <section
    aria-labelledby="approval-center-title"
    class="h-full overflow-auto bg-n-background p-4 text-n-slate-12 md:p-6"
  >
    <div class="mx-auto max-w-6xl space-y-5">
      <header class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p class="text-xs text-n-slate-11">
            {{ t('JRC_APPROVALS.administration') }}
          </p>
          <h1
            id="approval-center-title"
            class="text-2xl font-bold"
          >
            {{ t('JRC_APPROVALS.title') }}
          </h1>
        </div>
        <Button
          :label="t('JRC_APPROVALS.refresh')"
          variant="faded"
          :disabled="state.loading"
          @click="load"
        />
      </header>
      <nav
        :aria-label="t('JRC_APPROVALS.title')"
        class="flex flex-wrap gap-2"
      >
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm focus-visible:outline-blue-500"
          :class="
            screen === tab.key ? 'bg-n-blue-3 text-n-blue-11' : 'bg-n-solid-2'
          "
          @click="navigate(tab.key)"
        >
          {{ t(`JRC_APPROVALS.${tab.key}`) }}
        </button>
      </nav>
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
          :context="state.context"
          :busy="state.loading"
          @save="savePolicy"
          @operation="operate"
          @versions="loadVersions(1)"
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
        <RequestDetail
          v-if="screen === 'inbox' && record"
          :key="record.id"
          :request="record"
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
          @audit="navigate('history', record.id)"
        />
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
        <template
          v-if="!id && ['policies', 'inbox', 'history'].includes(screen)"
        >
          <div class="flex flex-wrap gap-2">
            <Button
              v-if="screen === 'policies'"
              :label="t('JRC_APPROVALS.newPolicy')"
              @click="navigate('policies', 'new')"
            /><template v-if="screen === 'inbox'">
              <button
                v-for="name in [
                  'assigned',
                  'requested',
                  'returned',
                  'escalated',
                  'all',
                ]"
                :key="name"
                class="rounded-lg border border-n-weak px-3 py-2 text-sm"
                :class="inbox === name ? 'bg-n-blue-3' : 'bg-n-solid-2'"
                @click="
                  inbox = name;
                  pageTo(1);
                  load();
                "
              >
                {{ t(`JRC_APPROVALS.${name}`) }}
              </button>
            </template>
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
                    <span class="rounded-full bg-n-alpha-2 px-2 py-1">{{
                      row.state
                    }}</span>
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
          <form
            v-if="screen === 'inbox' && can('request_create')"
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
        </template>
        <footer
          v-if="!id || screen === 'history'"
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
