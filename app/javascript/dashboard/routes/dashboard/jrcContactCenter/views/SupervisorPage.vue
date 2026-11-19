<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import { useMapGetter } from 'dashboard/composables/store';
import { agentStateLabels } from '../agentStateLabels';
import { formatDuration } from 'shared/helpers/timeHelper';
import { acwLabels } from '../../inbox/acwLabels';
import VisualShowcasePage from '../components/visual/VisualShowcasePage.vue';
import VisualSectionCard from '../components/visual/VisualSectionCard.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import { contactCenterScreen } from '../demo/contactCenterVisualCatalog';

const route = useRoute();
const { t } = useI18n();
const labels = computed(() => agentStateLabels(t));
const closingLabels = computed(() => acwLabels(t));
const loading = ref(true);
const failed = ref(false);
const units = ref([]);
const queues = ref([]);
const snapshot = ref(null);
const accountId = computed(() => route.params.accountId);
const currentUser = useMapGetter('getCurrentUser');
const polling = ref(false);
const contextKey = computed(() => {
  const account = currentUser.value?.accounts?.find(
    row => String(row.id) === String(accountId.value)
  );
  return JSON.stringify([
    accountId.value,
    currentUser.value?.id,
    currentUser.value?.type,
    account?.role,
    account?.custom_role_id,
    account?.permissions?.slice().sort(),
  ]);
});
const clearObserved = () => {
  snapshot.value = null;
  units.value = [];
  queues.value = [];
};

const agentTone = state => {
  if (state === 'available') return 'emerald';
  if (state === 'in_call') return 'blue';
  return 'amber';
};

const supervisorScreen = computed(() => {
  const source = contactCenterScreen('supervisor', t);
  const observed = !loading.value && !failed.value && snapshot.value;
  const agents = observed ? snapshot.value.agents : [];
  const waiting = observed
    ? snapshot.value.queues.reduce(
        (total, queue) => total + Number(queue.waiting),
        0
      )
    : '—';
  const values = [observed ? agents.length : '—', waiting, '—', '—'];
  const details = [
    observed
      ? t('JRC_CONTACT_CENTER.SUPERVISOR.OBSERVED_AGENTS', {
          available: agents.filter(agent => agent.state === 'available').length,
          inCall: agents.filter(agent => agent.state === 'in_call').length,
        })
      : t('JRC_CONTACT_CENTER.SUPERVISOR.UNOBSERVED'),
    observed
      ? t('JRC_CONTACT_CENTER.SUPERVISOR.LOCAL_SOURCE')
      : t('JRC_CONTACT_CENTER.SUPERVISOR.UNOBSERVED'),
    t('JRC_CONTACT_CENTER.SUPERVISOR.SLA_PENDING'),
    t('JRC_CONTACT_CENTER.SUPERVISOR.RATE_PENDING'),
  ];
  let status = {
    label: t('JRC_CONTACT_CENTER.SUPERVISOR.LOCAL_SOURCE'),
    tone: 'blue',
  };
  if (loading.value || polling.value)
    status = { label: t('JRC_CONTACT_CENTER.COMMON.LOADING'), tone: 'slate' };
  if (failed.value)
    status = { label: t('JRC_CONTACT_CENTER.COMMON.ERROR'), tone: 'ruby' };
  return {
    ...source,
    status,
    primary: null,
    secondary: null,
    metrics: source.metrics.map((item, index) => ({
      ...item,
      value: values[index],
      detail: details[index],
      trend: '',
    })),
  };
});

let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  clearObserved();
  if (!currentUser.value?.id) {
    loading.value = false;
    failed.value = true;
    return;
  }
  try {
    const [unitResponse, queueResponse, supervisorResponse] = await Promise.all(
      [
        JrcContactCenterAPI.units(accountId.value),
        JrcContactCenterAPI.queues(accountId.value),
        JrcContactCenterAPI.supervisor(accountId.value),
      ]
    );
    if (version !== generation) return;
    units.value = unitResponse.data.items || [];
    queues.value = queueResponse.data.items || [];
    snapshot.value = supervisorResponse.data;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(contextKey, load, { immediate: true });
const acwPoll = setInterval(async () => {
  if (loading.value || polling.value || !currentUser.value?.id) return;
  const version = generation;
  polling.value = true;
  try {
    const [unitResponse, response] = await Promise.all([
      JrcContactCenterAPI.units(accountId.value),
      JrcContactCenterAPI.supervisor(accountId.value),
    ]);
    if (version === generation) {
      snapshot.value = response.data;
      units.value = unitResponse.data.items || [];
      failed.value = false;
    }
  } catch {
    if (version === generation) {
      clearObserved();
      failed.value = true;
    }
  } finally {
    polling.value = false;
  }
}, 5000);
onBeforeUnmount(() => {
  generation += 1;
  clearInterval(acwPoll);
});
</script>

<template>
  <div>
    <VisualShowcasePage
      :screen="supervisorScreen"
      :show-demo-badge="false"
      overview-only
      data-supervisor-observed-metrics
    />

    <section class="space-y-5 px-4 pb-6 sm:px-6">
      <div class="flex items-center justify-between gap-3">
        <p class="text-sm text-n-amber-11">
          {{ t('JRC_CONTACT_CENTER.SUPERVISOR.SLA_PENDING') }}
        </p>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2 text-sm font-semibold text-n-slate-11 shadow-sm"
          @click="load"
        >
          <Icon icon="i-lucide-refresh-cw" class="size-4" />
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </div>

      <div
        v-if="failed"
        class="rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
      >
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </div>

      <div class="grid gap-5 xl:grid-cols-2">
        <VisualSectionCard
          :title="t('JRC_CONTACT_CENTER.SUPERVISOR.QUEUES')"
          :subtitle="loading ? t('JRC_CONTACT_CENTER.COMMON.LOADING') : ''"
          icon="i-lucide-layers-3"
          flush
        >
          <div
            v-if="(snapshot?.queues || []).length === 0"
            class="p-5 text-sm text-n-slate-10"
          >
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </div>
          <div v-else class="divide-y divide-n-weak">
            <div
              v-for="queue in snapshot?.queues || []"
              :key="queue.id"
              class="flex flex-wrap items-center gap-3 px-4 py-4 sm:px-5"
            >
              <span
                class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11"
              >
                <Icon icon="i-lucide-headphones" class="size-5" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ queue.name }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ t('JRC_CONTACT_CENTER.SUPERVISOR.QUEUE_LOAD', queue) }}
                </p>
              </div>
              <VisualStatusBadge
                :label="
                  t(
                    `JRC_CONTACT_CENTER.ADMIN.${queue.status === 'active' ? 'ACTIVE' : 'INACTIVE'}`
                  )
                "
                :tone="queue.status === 'active' ? 'blue' : 'slate'"
              />
            </div>
          </div>
        </VisualSectionCard>

        <VisualSectionCard
          :title="$t('JRC_CONTACT_CENTER.VISUAL.AGENTES_EM_TEMPO_REAL')"
          :subtitle="
            $t(
              'JRC_CONTACT_CENTER.VISUAL.ESTADO_LOCAL_ELEGIBILIDADE_E_FILA_CONFIRMADA'
            )
          "
          icon="i-lucide-users-round"
          flush
        >
          <div
            v-if="(snapshot?.agents || []).length === 0"
            class="p-5 text-sm text-n-slate-10"
          >
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </div>
          <div v-else class="divide-y divide-n-weak">
            <div
              v-for="agent in snapshot?.agents || []"
              :key="agent.account_user_id"
              class="flex flex-wrap items-center gap-3 px-4 py-4 sm:px-5"
            >
              <span
                class="grid size-10 shrink-0 place-content-center rounded-full bg-n-iris-2 font-bold text-n-iris-11"
              >
                {{
                  String(agent.name || 'A')
                    .slice(0, 1)
                    .toUpperCase()
                }}
              </span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ agent.name }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{
                    agent.eligible
                      ? t('JRC_CONTACT_CENTER.AGENT.ELIGIBLE')
                      : t('JRC_CONTACT_CENTER.AGENT.NOT_ELIGIBLE')
                  }}
                </p>
              </div>
              <VisualStatusBadge
                :label="labels[agent.state]"
                :tone="agentTone(agent.state)"
                dot
              />
              <div
                v-if="agent.pause_notice"
                class="w-full min-w-0 rounded-lg border border-n-weak p-3 text-sm text-n-slate-12"
                data-supervisor-pause-notice
              >
                <p>
                  {{
                    t('JRC_CONTACT_CENTER.PAUSE_CATALOG.SUPERVISOR_DURATION', {
                      elapsed: formatDuration(
                        agent.pause_notice.elapsed_seconds
                      ),
                    })
                  }}
                </p>
                <p
                  v-if="agent.pause_notice.exceeded"
                  role="status"
                  class="mt-1 text-n-amber-11"
                >
                  {{ t('JRC_CONTACT_CENTER.PAUSE_CATALOG.EXCEEDED') }}
                </p>
              </div>
              <p
                v-if="agent.deferred_pause_notice"
                role="status"
                class="w-full min-w-0 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
                data-supervisor-deferred-pause-notice
              >
                {{
                  agent.deferred_pause_notice.state === 'blocked'
                    ? t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.SUPERVISOR_BLOCKED')
                    : t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.SUPERVISOR_PENDING')
                }}
              </p>
              <div
                v-for="record in agent.pending_qualifications || []"
                :key="record.id"
                class="w-full rounded-lg p-3 text-sm"
                :class="
                  record.overdue
                    ? 'bg-n-ruby-2 text-n-ruby-11'
                    : 'bg-n-blue-2 text-n-blue-11'
                "
              >
                {{
                  t('JRC_CONTACT_CENTER.ACW_OPERATION.SUPERVISOR_DETAIL', {
                    channel: closingLabels.channels[record.channel],
                    id:
                      record.call_session_id || record.conversation_display_id,
                    elapsed: record.elapsed_seconds,
                    limit: record.acw_limit_seconds,
                  })
                }}
                <p class="mt-1 font-semibold">
                  {{
                    record.overdue
                      ? t('JRC_CONTACT_CENTER.ACW_OPERATION.OVERDUE')
                      : t('JRC_CONTACT_CENTER.INBOX_360.ACW')
                  }}
                </p>
              </div>
            </div>
          </div>
        </VisualSectionCard>
      </div>

      <VisualSectionCard
        :title="t('JRC_CONTACT_CENTER.SUPERVISOR.UNITS')"
        icon="i-lucide-building-2"
        flush
      >
        <div class="grid gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
          <article
            v-for="unit in units"
            :key="unit.id"
            data-supervisor-unit
            class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <span
                class="grid size-10 place-content-center rounded-xl bg-n-teal-2 text-n-teal-11"
              >
                <Icon icon="i-lucide-building-2" class="size-5" />
              </span>
              <VisualStatusBadge
                :label="
                  t(
                    `JRC_CONTACT_CENTER.ADMIN.${unit.status === 'active' ? 'ACTIVE' : 'INACTIVE'}`
                  )
                "
                :tone="unit.status === 'active' ? 'teal' : 'slate'"
              />
            </div>
            <h3 class="mt-4 text-sm font-semibold text-n-slate-12">
              {{ unit.name }}
            </h3>
            <p class="mt-1 text-xs text-n-slate-10">
              {{ unit.code }}{{ $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1145')
              }}{{
                t(
                  `JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.${unit.kind.toUpperCase()}`
                )
              }}
            </p>
          </article>
          <p v-if="units.length === 0" class="text-sm text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </p>
        </div>
      </VisualSectionCard>
    </section>
  </div>
</template>
