<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import { agentStateLabels } from '../agentStateLabels';
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

const agentTone = state => {
  if (state === 'available') return 'emerald';
  if (state === 'in_call') return 'blue';
  return 'amber';
};

const supervisorScreen = computed(() => {
  const source = contactCenterScreen('supervisor', t);
  const agents = snapshot.value?.agents || [];
  const queueRows = snapshot.value?.queues || [];
  const waiting = queueRows.reduce(
    (total, queue) => total + Number(queue.waiting || 0),
    0
  );
  const available = agents.filter(agent => agent.state === 'available').length;
  const inCall = agents.filter(agent => agent.state === 'in_call').length;
  const metrics = source.metrics.map((item, index) => {
    const values = [
      agents.length || item.value,
      waiting,
      item.value,
      item.value,
    ];
    const details = [
      `${available} disponíveis · ${inCall} em chamada`,
      item.detail,
      item.detail,
      item.detail,
    ];
    return { ...item, value: values[index], detail: details[index] };
  });
  return { ...source, metrics };
});

let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  snapshot.value = null;
  units.value = [];
  queues.value = [];
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
watch(accountId, load, { immediate: true });
const acwPoll = setInterval(async () => {
  if (loading.value) return;
  const version = generation;
  try {
    const response = await JrcContactCenterAPI.supervisor(accountId.value);
    if (version === generation) snapshot.value = response.data;
  } catch {
    if (version === generation) failed.value = true;
  }
}, 5000);
onBeforeUnmount(() => {
  generation += 1;
  clearInterval(acwPoll);
});
</script>

<template>
  <div>
    <VisualShowcasePage :screen="supervisorScreen" />

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
                  queue.waiting > 3
                    ? $t('JRC_CONTACT_CENTER.VISUAL.ATENCAO')
                    : $t('JRC_CONTACT_CENTER.VISUAL.OPERACAO_NORMAL')
                "
                :tone="queue.waiting > 3 ? 'amber' : 'emerald'"
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
            class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
          >
            <div class="flex items-start justify-between gap-3">
              <span
                class="grid size-10 place-content-center rounded-xl bg-n-teal-2 text-n-teal-11"
              >
                <Icon icon="i-lucide-building-2" class="size-5" />
              </span>
              <VisualStatusBadge :label="unit.status" tone="teal" />
            </div>
            <h3 class="mt-4 text-sm font-semibold text-n-slate-12">
              {{ unit.name }}
            </h3>
            <p class="mt-1 text-xs text-n-slate-10">
              {{ unit.code }}{{ $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1145')
              }}{{ unit.kind }}
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
