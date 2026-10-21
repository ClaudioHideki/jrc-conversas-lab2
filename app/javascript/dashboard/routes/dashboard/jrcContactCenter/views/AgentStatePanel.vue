<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import { agentStateLabels, pauseReasonLabels } from '../agentStateLabels';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  canOperate: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['stateChange']);
const { t } = useI18n();
const state = ref(null);
const now = ref(Date.now());
const clock = setInterval(() => {
  now.value = Date.now();
}, 1000);
const pauseElapsed = computed(() => {
  const seconds =
    Math.max(
      0,
      Math.floor(
        (now.value - new Date(state.value?.started_at).getTime()) / 1000
      )
    ) || 0;
  return [
    Math.floor(seconds / 3600),
    Math.floor(seconds / 60) % 60,
    seconds % 60,
  ]
    .map(value => String(value).padStart(2, '0'))
    .join(':');
});
const labels = computed(() => agentStateLabels(t));
const pauseReasons = computed(() =>
  Object.entries(pauseReasonLabels(t)).map(([code, label]) => ({ code, label }))
);
const busy = ref(false);
const failed = ref(false);
const reason = ref('');
const queueId = ref('');
const hasValidPauseReason = computed(() =>
  pauseReasons.value.some(item => item.code === reason.value)
);
let generation = 0;

const stateTone = computed(() => {
  const tones = {
    available: 'emerald',
    in_call: 'blue',
    ringing: 'amber',
    paused: 'violet',
    acw: 'teal',
    busy: 'amber',
    unavailable: 'ruby',
    offline: 'slate',
  };
  return tones[state.value?.state] || 'slate';
});

const transitions = computed(() => [
  {
    state: 'available',
    icon: 'i-lucide-circle-check-big',
    className: 'border-emerald-200 bg-emerald-50 text-emerald-700',
  },
  {
    state: 'paused',
    icon: 'i-lucide-pause',
    className: 'border-n-amber-5 bg-n-amber-2 text-n-amber-11',
  },
  {
    state: 'offline',
    icon: 'i-lucide-power',
    className: 'border-n-weak bg-n-alpha-2 text-n-slate-11',
  },
]);

const load = async () => {
  generation += 1;
  const version = generation;
  state.value = null;
  failed.value = false;
  busy.value = true;
  reason.value = '';
  queueId.value = '';
  try {
    const response = await JrcContactCenterAPI.agentState(props.accountId);
    if (version === generation) {
      state.value = response.data.item;
      reason.value =
        response.data.item?.state === 'paused'
          ? response.data.item.reason_code || ''
          : '';
    }
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) busy.value = false;
  }
};

const transition = async nextState => {
  if (!props.canOperate || busy.value || !state.value) return;
  if (nextState === 'paused' && !hasValidPauseReason.value) return;
  const version = generation;
  busy.value = true;
  failed.value = false;
  try {
    const response = await JrcContactCenterAPI.updateAgentState(
      props.accountId,
      {
        state: nextState,
        command_id: crypto.randomUUID(),
        expected_state_version: state.value.state_version,
        queue_id: queueId.value || undefined,
        reason_code: reason.value.trim() || undefined,
      }
    );
    if (version === generation) state.value = response.data.item;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) busy.value = false;
  }
};

watch(() => props.accountId, load, { immediate: true });
watch(state, value => emit('stateChange', value));
onBeforeUnmount(() => {
  generation += 1;
  clearInterval(clock);
});
</script>

<template>
  <section
    class="relative overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
  >
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-x-0 top-0 h-20 bg-gradient-to-r from-n-blue-2 via-n-iris-2/60 to-transparent"
    />
    <div
      class="relative flex flex-wrap items-start justify-between gap-4 p-4 sm:p-5"
    >
      <div class="flex min-w-0 items-start gap-3">
        <span
          class="grid size-11 shrink-0 place-content-center rounded-2xl bg-n-blue-3 text-n-blue-11 shadow-sm"
        >
          <Icon icon="i-lucide-headset" class="size-5" />
        </span>
        <div class="min-w-0">
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('JRC_CONTACT_CENTER.AGENT.TITLE') }}
          </h3>
          <p class="mt-1 text-xs leading-5 text-n-slate-10">
            {{
              compact
                ? t('JRC_CONTACT_CENTER.INBOX_360.PAUSE_HINT')
                : t('JRC_CONTACT_CENTER.AGENT.LOCAL_INTENT')
            }}
          </p>
        </div>
      </div>
      <VisualStatusBadge
        v-if="state"
        :label="labels[state.state]"
        :tone="stateTone"
        dot
      />
    </div>

    <div class="relative border-t border-n-weak p-4 sm:p-5">
      <p
        v-if="failed"
        role="alert"
        class="mb-4 rounded-xl border border-n-ruby-5 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
      >
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>

      <div
        v-if="state"
        class="grid gap-4 xl:grid-cols-[minmax(240px,.7fr)_minmax(0,1.3fr)]"
      >
        <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
          <div class="flex items-center justify-between gap-3">
            <p
              class="text-xs font-semibold uppercase tracking-[0.14em] text-n-slate-9"
            >
              {{ t('JRC_CONTACT_CENTER.COMMON.STATUS') }}
            </p>
            <span
              class="grid size-8 place-content-center rounded-lg bg-n-solid-2 text-n-blue-11 shadow-sm"
            >
              <Icon icon="i-lucide-radio" class="size-4" />
            </span>
          </div>
          <p class="mt-3 text-lg font-bold text-n-slate-12">
            {{ labels[state.state] }}
          </p>
          <p
            v-if="state.state === 'paused'"
            class="mt-2 text-sm font-medium text-n-amber-11"
            role="timer"
          >
            {{
              t('JRC_CONTACT_CENTER.COMMON.CODE_DETAIL', {
                code: pauseReasons.find(item => item.code === state.reason_code)
                  ?.label,
                detail: pauseElapsed,
              })
            }}
          </p>
          <p class="mt-1 text-xs leading-5 text-n-slate-10">
            {{
              state.eligible
                ? t('JRC_CONTACT_CENTER.AGENT.ELIGIBLE')
                : t('JRC_CONTACT_CENTER.AGENT.NOT_ELIGIBLE')
            }}
          </p>
          <div
            class="mt-4 flex items-center gap-2 rounded-xl border p-3 text-xs"
            :class="
              state.provider_confirmed
                ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                : 'border-n-amber-5 bg-n-amber-2 text-n-amber-11'
            "
          >
            <Icon
              :icon="
                state.provider_confirmed
                  ? 'i-lucide-badge-check'
                  : 'i-lucide-clock-3'
              "
              class="size-4 shrink-0"
            />
            <span>
              {{
                state.provider_confirmed
                  ? t('JRC_CONTACT_CENTER.STATUS.READY')
                  : compact
                    ? t('JRC_CONTACT_CENTER.INBOX_360.PHONE_CONFIRMATION')
                    : t('JRC_CONTACT_CENTER.STATUS.PENDING_CONTRACT')
              }}
            </span>
          </div>
        </div>

        <div v-if="canOperate" class="space-y-3">
          <div class="grid gap-3 sm:grid-cols-2">
            <label class="space-y-1.5">
              <span class="text-xs font-semibold text-n-slate-10">
                {{ t('JRC_CONTACT_CENTER.CARDS.QUEUES') }}
              </span>
              <select
                v-model="queueId"
                :disabled="busy"
                :aria-label="t('JRC_CONTACT_CENTER.CARDS.QUEUES')"
                class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-12 outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
              >
                <option value="">
                  {{ t('JRC_CONTACT_CENTER.AGENT.SELECT_QUEUE') }}
                </option>
                <option
                  v-for="queue in state.queues"
                  :key="queue.id"
                  :value="queue.id"
                >
                  {{ queue.name }}
                </option>
              </select>
            </label>
            <label class="space-y-1.5">
              <span class="text-xs font-semibold text-n-slate-10">
                {{ t('JRC_CONTACT_CENTER.AGENT.REASON') }}
              </span>
              <select
                v-model="reason"
                :disabled="busy"
                :aria-label="t('JRC_CONTACT_CENTER.AGENT.REASON')"
                class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-12 outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
              >
                <option value="">
                  {{ t('JRC_CONTACT_CENTER.AGENT.PAUSE_PLACEHOLDER') }}
                </option>
                <option
                  v-for="pauseReason in pauseReasons"
                  :key="pauseReason.code"
                  :value="pauseReason.code"
                >
                  {{ pauseReason.label }}
                </option>
              </select>
            </label>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="item in transitions"
              :key="item.state"
              type="button"
              :disabled="
                busy || (item.state === 'paused' && !hasValidPauseReason)
              "
              class="inline-flex items-center gap-2 rounded-xl border px-4 py-2.5 text-sm font-semibold shadow-sm transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-50"
              :class="item.className"
              @click="transition(item.state)"
            >
              <Icon :icon="item.icon" class="size-4" />
              {{
                item.state === 'available' && state.state === 'paused'
                  ? t('JRC_CONTACT_CENTER.INBOX_360.RESUME')
                  : labels[item.state]
              }}
            </button>
          </div>
        </div>
      </div>

      <div
        v-else-if="busy"
        class="h-24 animate-pulse rounded-2xl bg-n-alpha-2"
      />
    </div>
  </section>
</template>
