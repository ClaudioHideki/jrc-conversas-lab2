<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import DeferredPauseDialog from '../components/DeferredPauseDialog.vue';
import PauseApprovalStatus from '../components/PauseApprovalStatus.vue';
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
const queueId = ref('');
const legacyReasons = computed(() => pauseReasonLabels(t));
const pauseReasons = computed(() => {
  const catalog = state.value?.pause_catalog;
  const entries = (catalog?.entries || []).filter(
    entry =>
      !queueId.value ||
      entry.all_queues ||
      entry.scope_queue_ids.includes(queueId.value)
  );
  const available = new Map(
    catalog?.enforced === true ? [] : Object.entries(legacyReasons.value)
  );
  entries.forEach(entry => available.set(entry.code, entry.name));
  return [...available].map(([code, label]) => ({ code, label }));
});
const currentReasonLabel = computed(
  () =>
    state.value?.pause_definition?.name ||
    legacyReasons.value[state.value?.reason_code] ||
    state.value?.reason_code ||
    '—'
);
const deferredReasonLabel = computed(() => {
  const request = state.value?.deferred_pause_request;
  if (!request || request.private_details_available === false) return '';
  const definition = state.value.pause_catalog?.entries?.find(
    entry => entry.code === request.reason_code
  );
  return (
    definition?.name ||
    legacyReasons.value[request.reason_code] ||
    request.reason_label ||
    ''
  );
});
const pauseExceeded = computed(() => {
  const maximum = state.value?.pause_definition?.maximum_minutes;
  return (
    state.value?.state === 'paused' &&
    state.value?.pause_definition?.time_alert_enabled !== false &&
    Number.isInteger(maximum) &&
    maximum >= 0 &&
    now.value - new Date(state.value.started_at).getTime() > maximum * 60000
  );
});
const busy = ref(false);
const failed = ref(false);
const reason = ref('');
const justification = ref('');
const failureCode = ref('');
const pauseDialog = ref(null);
const operationalPollFailed = ref(false);
let polling = false;
const selectedDefinition = computed(() =>
  state.value?.pause_catalog?.entries?.find(
    entry =>
      entry.code === reason.value &&
      (!queueId.value ||
        entry.all_queues ||
        entry.scope_queue_ids?.includes(queueId.value))
  )
);
const approvalRequired = computed(
  () =>
    state.value?.pause_catalog?.enforced === true &&
    selectedDefinition.value?.approval_required === true
);
const justificationRequired = computed(
  () =>
    state.value?.pause_catalog?.enforced === true &&
    selectedDefinition.value?.justification_required === true
);
const hasValidJustification = computed(
  () =>
    justification.value.length <= 1000 &&
    (!justificationRequired.value || justification.value.trim().length > 0)
);
const failureLabel = computed(() => {
  const messages = {
    pause_justification_required: t(
      'JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_ERROR'
    ),
    invalid_pause_justification: t(
      'JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_ERROR'
    ),
    call_active: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CALL_ACTIVE'),
    tabulation_pending: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.ACW_PENDING'),
    pause_request_exists: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.EXISTS'),
    pause_context_changed: t(
      'JRC_CONTACT_CENTER.DEFERRED_PAUSE.CONTEXT_CHANGED'
    ),
    access_revoked: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.DENIED'),
  };
  return messages[failureCode.value] || t('JRC_CONTACT_CENTER.COMMON.ERROR');
});
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
  justification.value = '';
  failureCode.value = '';
  pauseDialog.value = null;
  operationalPollFailed.value = false;
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

const openPauseDialog = mode => {
  if (!props.canOperate || busy.value || !state.value) return;
  const request = state.value.deferred_pause_request;
  generation += 1;
  pauseDialog.value = {
    mode,
    generation,
    account: String(props.accountId),
    member: String(state.value.account_user_id),
    contextKey: `${props.accountId}:${state.value.account_user_id}:${generation}`,
    stateVersion: state.value.state_version,
    requestRevision: state.value.pause_request_revision,
    requestId: request?.request_id || '',
    approvalRequired: mode === 'request' && approvalRequired.value,
    reasonCode: reason.value,
    queueId: queueId.value,
    justification: mode === 'request' ? justification.value : '',
    reasonLabel:
      mode === 'cancel'
        ? deferredReasonLabel.value
        : pauseReasons.value.find(item => item.code === reason.value)?.label ||
          '',
  };
};

const transition = async nextState => {
  if (!props.canOperate || busy.value || !state.value) return;
  if (
    nextState === 'paused' &&
    (!hasValidPauseReason.value || !hasValidJustification.value)
  )
    return;
  if (
    nextState === 'paused' &&
    (state.value.can_defer_pause || approvalRequired.value)
  ) {
    openPauseDialog('request');
    return;
  }
  const version = generation;
  busy.value = true;
  failed.value = false;
  failureCode.value = '';
  try {
    const response = await JrcContactCenterAPI.updateAgentState(
      props.accountId,
      {
        state: nextState,
        command_id: crypto.randomUUID(),
        expected_state_version: state.value.state_version,
        queue_id: queueId.value || undefined,
        reason_code: reason.value.trim() || undefined,
        ...(nextState === 'paused' &&
        selectedDefinition.value &&
        justification.value.trim()
          ? { justification: justification.value.trim() }
          : {}),
      }
    );
    if (version === generation) {
      state.value = response.data.item;
      justification.value = '';
    }
  } catch (error) {
    if (version === generation) {
      failed.value = true;
      failureCode.value = error.response?.data?.error || '';
    }
  } finally {
    if (version === generation) busy.value = false;
  }
};

const isDeferredContext = token => {
  const context = pauseDialog.value;
  return Boolean(
    context &&
      context.contextKey === token &&
      context.generation === generation &&
      context.account === String(props.accountId) &&
      props.canOperate
  );
};
const closeDeferredDialog = token => {
  if (pauseDialog.value?.contextKey === token) pauseDialog.value = null;
};
const applyDeferredState = (value, token) => {
  const context = pauseDialog.value;
  if (!isDeferredContext(token) || context.member !== value.account_user_id)
    return;
  state.value = value;
  failed.value = false;
  failureCode.value = '';
  operationalPollFailed.value = false;
  justification.value = '';
};
const clearOperatingData = () => {
  generation += 1;
  state.value = null;
  pauseDialog.value = null;
  reason.value = '';
  queueId.value = '';
  justification.value = '';
  failed.value = true;
  busy.value = false;
  operationalPollFailed.value = true;
  failureCode.value = 'access_revoked';
};
const clearDeferredAccess = token => {
  if (isDeferredContext(token)) clearOperatingData();
};
const refreshDeferredState = async token => {
  if (!isDeferredContext(token)) return;
  const context = {
    account: String(props.accountId),
    member: state.value?.account_user_id,
    reason: reason.value,
    queue: String(queueId.value),
    justification: justification.value,
  };
  await load();
  if (
    context.account !== String(props.accountId) ||
    context.member !== state.value?.account_user_id ||
    !props.canOperate
  )
    return;
  const revision = generation;
  const sameContext = () =>
    revision === generation &&
    context.account === String(props.accountId) &&
    context.member === state.value?.account_user_id &&
    props.canOperate;
  if (
    context.queue &&
    !state.value.queues.some(item => String(item.id) === context.queue)
  ) {
    failed.value = true;
    failureCode.value = 'pause_context_changed';
    return;
  }
  queueId.value = context.queue;
  await nextTick();
  if (!sameContext()) return;
  if (!pauseReasons.value.some(item => item.code === context.reason)) return;
  reason.value = context.reason;
  await nextTick();
  if (sameContext() && selectedDefinition.value)
    justification.value = context.justification;
};

const pollDeferredState = async () => {
  const waiting =
    state.value?.deferred_pause_request ||
    state.value?.can_defer_pause ||
    state.value?.pending_qualifications?.length;
  if (
    !props.canOperate ||
    !waiting ||
    busy.value ||
    polling ||
    pauseDialog.value ||
    operationalPollFailed.value
  )
    return;
  const version = generation;
  const account = String(props.accountId);
  const member = String(state.value.account_user_id);
  polling = true;
  try {
    const response = await JrcContactCenterAPI.agentState(props.accountId);
    if (
      version !== generation ||
      account !== String(props.accountId) ||
      !props.canOperate ||
      pauseDialog.value
    )
      return;
    const value = response.data.item;
    if (
      String(response.data.account_id) !== account ||
      String(value?.account_user_id) !== member
    ) {
      clearOperatingData();
      failureCode.value = 'pause_context_changed';
      return;
    }
    if (value.pause_catalog === null) {
      clearOperatingData();
      return;
    }
    state.value = value;
    const queueAllowed =
      !queueId.value ||
      value.queues.some(item => String(item.id) === String(queueId.value));
    if (!queueAllowed || (reason.value && !hasValidPauseReason.value)) {
      queueId.value = '';
      reason.value = '';
      justification.value = '';
      failed.value = true;
      failureCode.value = 'pause_context_changed';
    }
  } catch (error) {
    if (version !== generation || account !== String(props.accountId)) return;
    if ([401, 403].includes(error.response?.status)) clearOperatingData();
    else {
      operationalPollFailed.value = true;
      failed.value = true;
    }
  } finally {
    polling = false;
  }
};
const pausePoll = setInterval(pollDeferredState, 5000);

watch(() => [props.accountId, props.canOperate], load, { immediate: true });
watch([reason, queueId], () => {
  justification.value = '';
});
watch(state, value => emit('stateChange', value));
onBeforeUnmount(() => {
  generation += 1;
  clearInterval(clock);
  clearInterval(pausePoll);
});
</script>

<template>
  <section
    class="relative overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
    :data-agent-state="state?.state"
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
      <div
        v-if="failed"
        class="mb-4 rounded-xl border border-n-ruby-5 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
      >
        <p role="alert">{{ failureLabel }}</p>
        <button
          type="button"
          :disabled="busy"
          class="mt-2 underline"
          data-agent-state-refresh
          @click="load"
        >
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </div>

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
                code: currentReasonLabel,
                detail: pauseElapsed,
              })
            }}
          </p>
          <p
            v-if="canOperate && state.pause_definition?.justification"
            class="mt-2 whitespace-pre-wrap break-words text-sm text-n-slate-12"
            data-own-pause-justification
          >
            {{
              t('JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_DETAIL', {
                text: state.pause_definition.justification,
              })
            }}
          </p>
          <p
            v-if="pauseExceeded"
            role="status"
            class="mt-2 text-sm text-n-amber-11"
            data-pause-exceeded
          >
            {{ t('JRC_CONTACT_CENTER.PAUSE_CATALOG.EXCEEDED') }}
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
          <div
            v-if="state.deferred_pause_request"
            role="status"
            class="min-w-0 space-y-2 rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
            data-deferred-pause-pending
          >
            <p>
              {{
                state.deferred_pause_request.state === 'blocked'
                  ? t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.BLOCKED')
                  : t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.PENDING')
              }}
            </p>
            <PauseApprovalStatus
              v-if="state.deferred_pause_request.approval?.required"
              :account-id="accountId"
              :approval="state.deferred_pause_request.approval"
              :busy="busy || operationalPollFailed"
              @apply="openPauseDialog('apply')"
            />
            <p v-if="deferredReasonLabel" class="break-words">
              {{ deferredReasonLabel }}
            </p>
            <button
              type="button"
              :disabled="busy || operationalPollFailed"
              class="rounded-lg border border-n-amber-6 px-3 py-2 font-medium"
              data-deferred-pause-cancel
              @click="openPauseDialog('cancel')"
            >
              {{ t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CANCEL') }}
            </button>
          </div>
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
          <label
            v-if="selectedDefinition"
            class="block min-w-0 space-y-1.5 text-sm text-n-slate-12"
          >
            <span>{{
              t('JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION')
            }}</span>
            <textarea
              v-model="justification"
              :disabled="busy"
              :required="justificationRequired"
              maxlength="1000"
              :aria-label="t('JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION')"
              :aria-invalid="!hasValidJustification || undefined"
              class="w-full min-w-0 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
            />
            <span class="block text-xs text-n-slate-10">
              {{ t('JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_PRIVATE') }}
            </span>
          </label>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="item in transitions"
              :key="item.state"
              type="button"
              :disabled="
                busy ||
                Boolean(state.deferred_pause_request) ||
                (item.state === 'paused' &&
                  (!hasValidPauseReason || !hasValidJustification))
              "
              class="inline-flex items-center gap-2 rounded-xl border px-4 py-2.5 text-sm font-semibold shadow-sm transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-50"
              :class="item.className"
              @click="transition(item.state)"
            >
              <Icon :icon="item.icon" class="size-4" />
              {{
                item.state === 'available' && state.state === 'paused'
                  ? t('JRC_CONTACT_CENTER.INBOX_360.RESUME')
                  : item.state === 'paused' &&
                      (state.can_defer_pause || approvalRequired)
                    ? t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.REQUEST_BUTTON')
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
    <DeferredPauseDialog
      v-if="pauseDialog && canOperate && state"
      :key="pauseDialog.contextKey"
      :account-id="accountId"
      :member-id="pauseDialog.member"
      :context-key="pauseDialog.contextKey"
      :mode="pauseDialog.mode"
      :state-version="pauseDialog.stateVersion"
      :request-revision="pauseDialog.requestRevision"
      :reason-code="pauseDialog.reasonCode"
      :reason-label="pauseDialog.reasonLabel"
      :queue-id="pauseDialog.queueId"
      :justification="pauseDialog.justification"
      :request-id="pauseDialog.requestId"
      :approval-required="pauseDialog.approvalRequired"
      @updated="applyDeferredState"
      @close="closeDeferredDialog"
      @refresh="refreshDeferredState"
      @denied="clearDeferredAccess"
    />
  </section>
</template>
