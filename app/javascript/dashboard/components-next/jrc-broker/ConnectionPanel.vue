<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  isPairingActionUsable,
  pairingImage,
  visibleConnectionActions,
} from './pairingState';

const props = defineProps({
  accountId: { type: Number, required: true },
  inboxId: { type: Number, required: true },
  connectionName: { type: String, default: '' },
  presentation: {
    type: String,
    default: 'all',
    validator: value =>
      ['all', 'overview', 'configuration', 'pairing'].includes(value),
  },
});
const emit = defineEmits(['health', 'healthError', 'reconnected', 'renamed']);
const { t } = useI18n();
const store = useStore();
const health = ref(null);
const action = ref(null);
const error = ref('');
const busy = ref(false);
const expired = ref(false);
const clock = ref(Date.now());
const remainingSeconds = computed(() =>
  action.value
    ? Math.max(
        0,
        Math.ceil((Date.parse(action.value.expiresAt) - clock.value) / 1000)
      )
    : 0
);
let countdownTimer;
const pairingProgress = ref('');
const checkedUnknown = ref(false);
const confirm = ref('');
const approved = ref(false);
const name = ref(props.connectionName);
const actions = computed(() =>
  visibleConnectionActions(health.value?.allowedActions)
);
const image = computed(() => pairingImage(action.value));
const identityState = computed(() => {
  if (
    health.value?.identityApproved === true &&
    health.value?.identityStatus === 'CONFIRMED'
  )
    return 'APPROVED';
  return health.value?.identityStatus === 'CONFIRMATION_REQUIRED'
    ? 'CONFIRMATION_REQUIRED'
    : 'UNVERIFIED';
});
const progressMessage = computed(() => {
  if (pairingProgress.value === 'PENDING')
    return t('JRC_BROKER.PAIR_PROGRESS.PENDING');
  if (pairingProgress.value === 'SUCCEEDED')
    return t('JRC_BROKER.PAIR_PROGRESS.SUCCEEDED');
  if (pairingProgress.value === 'FAILED')
    return t('JRC_BROKER.PAIR_PROGRESS.FAILED');
  if (pairingProgress.value === 'UNKNOWN')
    return t('JRC_BROKER.PAIR_PROGRESS.UNKNOWN');
  return '';
});
let api;
let controller;
let generation = 0;
let timer;
let expiryTimer;
let stopped = false;
let failures = 0;
let latestPoll = 0;
let pollInFlight;
let confirmationRevision;
let pendingPair;
let lastPairOperationId;
let verifyRequested = false;
let awaitingReconnection = false;

const clearCode = () => {
  pendingPair = null;
  lastPairOperationId = null;
  checkedUnknown.value = false;
  clearTimeout(expiryTimer);
  clearInterval(countdownTimer);
  action.value = null;
};

const acceptPair = result => {
  checkedUnknown.value = false;
  if (isPairingActionUsable(result.action, Date.now())) {
    pendingPair = null;
    pairingProgress.value = '';
    clearInterval(countdownTimer);
    action.value = result.action;
    clock.value = Date.now();
    countdownTimer = setInterval(() => {
      clock.value = Date.now();
    }, 1000);
    expiryTimer = setTimeout(
      () => {
        clearCode();
        expired.value = true;
      },
      Date.parse(result.action.expiresAt) - Date.now()
    );
  } else if (result.action?.reason === 'CONNECTION_PENDING') {
    if (result.operationId) {
      lastPairOperationId = result.operationId;
      pendingPair = {
        operationId: result.operationId,
        expiresAt: Date.now() + 60000,
      };
      pairingProgress.value = 'PENDING';
    } else {
      pairingProgress.value = 'UNKNOWN';
    }
  } else {
    pendingPair = null;
    pairingProgress.value = '';
  }
};

const stop = () => {
  generation += 1;
  stopped = true;
  verifyRequested = false;
  clearTimeout(timer);
  clearCode();
  pairingProgress.value = '';
  controller?.abort();
  health.value = null;
  busy.value = false;
  confirm.value = '';
  approved.value = false;
  awaitingReconnection = false;
};
const fail = failure => {
  const denied = [401, 403, 404].includes(failure?.response?.status);
  if (denied) {
    stop();
  } else {
    clearTimeout(expiryTimer);
    action.value = null;
    clearInterval(countdownTimer);
  }
  if (denied) error.value = 'DENIED';
  else if (failure?.response?.status === 409) error.value = 'CONFLICT';
  else error.value = 'UNAVAILABLE';
  emit('healthError', { accountId: props.accountId, inboxId: props.inboxId });
};
const poll = async () => {
  clearTimeout(timer);
  if (stopped || document.hidden || pollInFlight === generation) return;
  const manuallyChecking = verifyRequested;
  verifyRequested = false;
  const current = generation;
  pollInFlight = current;
  latestPoll += 1;
  const pollVersion = latestPoll;
  try {
    const result = await api.status(props.inboxId, controller.signal);
    if (current !== generation || pollVersion !== latestPoll) return;
    if (
      confirm.value === 'confirmIdentity' &&
      result.identityRevision !== confirmationRevision
    ) {
      confirm.value = '';
      approved.value = false;
    }
    health.value = result;
    const update = {
      accountId: props.accountId,
      inboxId: props.inboxId,
      health: result,
    };
    emit('health', update);
    if (
      awaitingReconnection &&
      result.instanceStatus === 'CONNECTED' &&
      result.integrationStatus === 'READY' &&
      result.identityApproved === true &&
      result.identityStatus === 'CONFIRMED'
    ) {
      awaitingReconnection = false;
      emit('reconnected', update);
    }
    failures = 0;
    error.value = '';
    if (
      result.instanceStatus === 'CONNECTED' ||
      !actions.value.includes('pair')
    ) {
      clearCode();
      pairingProgress.value = '';
    }
    if (manuallyChecking && lastPairOperationId && !pendingPair) {
      pendingPair = {
        operationId: lastPairOperationId,
        expiresAt: Date.now() + 60000,
      };
    }
    if (pendingPair && Date.now() >= pendingPair.expiresAt) {
      pendingPair = null;
      pairingProgress.value = 'UNKNOWN';
      checkedUnknown.value = false;
    }
    if (pendingPair && !busy.value) {
      const operationId = pendingPair.operationId;
      const progress = await api.pairOperation(
        props.inboxId,
        operationId,
        controller.signal
      );
      if (current !== generation || pollVersion !== latestPoll) return;
      if (progress.action) {
        acceptPair(progress);
      } else {
        if (progress.state !== 'PENDING') pendingPair = null;
        const uncertain =
          progress.state === 'UNKNOWN' || progress.reconciliationRequired;
        pairingProgress.value = uncertain ? 'UNKNOWN' : progress.state;
        checkedUnknown.value =
          manuallyChecking && uncertain && progress.state !== 'PENDING';
      }
    }
  } catch (failure) {
    if (current !== generation || pollVersion !== latestPoll) return;
    failures += 1;
    fail(failure);
  } finally {
    if (pollInFlight === current) pollInFlight = null;
    if (
      current === generation &&
      pollVersion === latestPoll &&
      !stopped &&
      !document.hidden
    )
      timer = setTimeout(poll, Math.min(15000, 3000 * (failures + 1)));
  }
};
const verifyPairOperation = () => {
  if (
    stopped ||
    busy.value ||
    pendingPair ||
    !lastPairOperationId ||
    !actions.value.includes('pair')
  )
    return;
  pendingPair = {
    operationId: lastPairOperationId,
    expiresAt: Date.now() + 60000,
  };
  verifyRequested = true;
  checkedUnknown.value = false;
  pairingProgress.value = 'PENDING';
  poll();
};
const mutate = async kind => {
  if (
    busy.value ||
    stopped ||
    (kind === 'pair' &&
      (pairingProgress.value === 'PENDING' ||
        (pairingProgress.value === 'UNKNOWN' && !checkedUnknown.value))) ||
    !actions.value.includes(kind === 'confirmIdentity' ? 'manage' : kind)
  )
    return;
  if (kind !== 'pair' && !approved.value) return;
  if (
    kind === 'confirmIdentity' &&
    confirmationRevision !== health.value?.identityRevision
  )
    return;
  const current = generation;
  const checkedOperationId = lastPairOperationId;
  if (kind === 'pair' && health.value?.instanceStatus !== 'CONNECTED')
    awaitingReconnection = true;
  busy.value = true;
  error.value = '';
  expired.value = false;
  clearCode();
  pairingProgress.value = '';
  try {
    const key = crypto.randomUUID();
    const result =
      kind === 'confirmIdentity'
        ? await api.confirmIdentity(
            props.inboxId,
            confirmationRevision,
            key,
            controller.signal
          )
        : await api[kind](props.inboxId, key, controller.signal);
    if (current !== generation) return;
    if (kind === 'pair') acceptPair(result);
    confirm.value = '';
    approved.value = false;
    await poll();
  } catch (failure) {
    if (current === generation) {
      if (kind === 'pair' && failure?.response?.status === 409) {
        lastPairOperationId = checkedOperationId;
        pairingProgress.value = 'UNKNOWN';
      } else if (kind === 'pair' && !failure?.response) {
        pairingProgress.value = 'UNKNOWN';
      }
      fail(failure);
    }
  } finally {
    if (current === generation) busy.value = false;
  }
};
const rename = async () => {
  if (
    stopped ||
    busy.value ||
    !actions.value.includes('manage') ||
    !name.value.trim()
  )
    return;
  const current = generation;
  busy.value = true;
  try {
    const result = await api.renameConnection(
      props.inboxId,
      name.value.trim(),
      controller.signal
    );
    if (current === generation)
      emit('renamed', {
        accountId: props.accountId,
        inboxId: props.inboxId,
        name: result.name,
      });
  } catch (failure) {
    if (current === generation) fail(failure);
  } finally {
    if (current === generation) busy.value = false;
  }
};
watch(
  () => props.connectionName,
  value => {
    name.value = value;
  }
);
const restart = () => {
  stop();
  stopped = false;
  failures = 0;
  error.value = '';
  expired.value = false;
  controller = new AbortController();
  api = createJrcBrokerApi(props.accountId);
  poll();
};
const openConfirmation = kind => {
  confirmationRevision = health.value?.identityRevision;
  confirm.value = kind;
  approved.value = false;
};
const visibility = () => {
  clearTimeout(timer);
  if (!document.hidden && !stopped) poll();
};
watch(() => [props.accountId, props.inboxId], restart, { immediate: true });
const unsubscribe = store?.subscribe(mutation => {
  if (mutation.type === 'LOGOUT') stop();
});
onMounted(() => document.addEventListener('visibilitychange', visibility));
onBeforeUnmount(() => {
  stop();
  unsubscribe?.();
  document.removeEventListener('visibilitychange', visibility);
});
</script>

<template>
  <section
    class="flex flex-col gap-4 p-5 border border-n-weak rounded-xl bg-n-solid-1"
    :class="presentation === 'pairing' ? 'md:grid md:grid-cols-2' : ''"
    :aria-label="t('JRC_BROKER.DETAILS.PANEL_TITLE')"
  >
    <h3 class="text-lg font-semibold text-n-slate-12 md:col-span-2">
      {{
        t(
          presentation === 'pairing'
            ? 'JRC_BROKER.WORKSPACE.PAIR_TITLE'
            : 'JRC_BROKER.DETAILS.PANEL_TITLE'
        )
      }}
    </h3>
    <div
      v-if="presentation === 'pairing'"
      data-testid="pairing-instructions"
      class="rounded-xl border border-n-weak bg-n-alpha-1 p-5 md:col-start-2 md:row-start-2 md:row-span-4"
    >
      <p class="text-sm leading-6 text-n-slate-11">
        {{ t('JRC_BROKER.WORKSPACE.PAIR_HELP') }}
      </p>
      <ol class="mt-4 flex flex-col gap-4 text-sm">
        <li v-for="step in [1, 2, 3]" :key="step" class="flex gap-3">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full bg-n-brand text-xs text-white"
            >{{ step }}</span
          >{{ t(`JRC_BROKER.WORKSPACE.PAIR_STEP_${step}`) }}
        </li>
      </ol>
    </div>
    <p v-if="error" role="alert">{{ t(`JRC_BROKER.ERROR.${error}`) }}</p>
    <dl
      v-if="
        health && presentation !== 'configuration' && presentation !== 'pairing'
      "
      data-testid="connection-health"
      class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm"
    >
      <div>
        <dt>{{ t('JRC_BROKER.DETAILS.SESSION') }}</dt>
        <dd>{{ t(`JRC_BROKER.STATUS.${health.instanceStatus}`) }}</dd>
      </div>
      <div>
        <dt>{{ t('JRC_BROKER.DETAILS.IDENTITY') }}</dt>
        <dd>{{ t(`JRC_BROKER.DETAILS.IDENTITY_STATES.${identityState}`) }}</dd>
      </div>
      <div>
        <dt>{{ t('JRC_BROKER.DETAILS.LINK') }}</dt>
        <dd>{{ t(`JRC_BROKER.STATUS.${health.integrationStatus}`) }}</dd>
      </div>
      <div>
        <dt>{{ t('JRC_BROKER.DETAILS.DELIVERY') }}</dt>
        <dd>{{ t(`JRC_BROKER.STATUS.${health.transportStatus}`) }}</dd>
      </div>
    </dl>
    <p
      v-if="presentation !== 'configuration' && presentation !== 'pairing'"
      class="text-sm text-n-slate-11"
    >
      {{ t('JRC_BROKER.DETAILS.HEALTH_HELP') }}
    </p>
    <template v-if="presentation !== 'overview'">
      <form
        v-if="presentation !== 'pairing' && actions.includes('manage')"
        data-testid="connection-name-form"
        class="flex flex-col gap-3"
        @submit.prevent="rename"
      >
        <label class="flex flex-col gap-2 text-sm">
          {{ t('JRC_BROKER.INSTANCE_NAME') }}
          <input
            v-model="name"
            data-testid="connection-name-input"
            type="text"
            maxlength="255"
            required
            :disabled="busy"
          />
        </label>
        <Button
          type="submit"
          :disabled="busy || !name.trim()"
          :label="t('JRC_BROKER.CONNECTIONS.SAVE_NAME')"
        />
      </form>
      <p v-if="presentation !== 'pairing'" class="text-sm text-n-slate-11">
        {{ t('JRC_BROKER.DETAILS.CONFIGURATION_HELP') }}
      </p>
      <img
        v-if="image"
        :src="image"
        :alt="t('JRC_BROKER.QR_ALT')"
        class="w-64 h-64 max-w-full self-center bg-white p-2 md:col-start-1 md:row-start-2"
      />
      <output
        v-else-if="action?.type === 'PAIRING_CODE'"
        class="text-2xl font-mono text-center md:col-start-1 md:row-start-2"
      >
        <span>{{ action.code }}</span>
      </output>
      <p
        v-if="action"
        data-testid="pairing-countdown"
        role="status"
        aria-live="off"
        class="text-center text-sm text-n-slate-11"
      >
        {{
          t('JRC_BROKER.WORKSPACE.EXPIRES_IN', { seconds: remainingSeconds })
        }}
      </p>
      <p v-if="expired" role="status">{{ t('JRC_BROKER.EXPIRED') }}</p>
      <p v-if="progressMessage" role="status">{{ progressMessage }}</p>
      <div class="flex flex-wrap gap-3 md:col-span-2">
        <Button
          v-if="actions.includes('pair')"
          data-testid="pair"
          :disabled="
            busy ||
            pairingProgress === 'PENDING' ||
            (pairingProgress === 'UNKNOWN' && !checkedUnknown)
          "
          :label="t('JRC_BROKER.PAIR')"
          @click="mutate('pair')"
        />
        <Button
          v-if="
            pairingProgress === 'UNKNOWN' &&
            lastPairOperationId &&
            actions.includes('pair')
          "
          data-testid="verify-pair-operation"
          :disabled="busy"
          variant="outline"
          :label="t('JRC_BROKER.PAIR_PROGRESS.VERIFY')"
          @click="verifyPairOperation"
        />
        <Button
          v-if="actions.includes('disconnect')"
          :disabled="busy"
          variant="outline"
          :label="t('JRC_BROKER.DISCONNECT')"
          @click="openConfirmation('disconnect')"
        />
        <Button
          v-if="
            actions.includes('manage') &&
            health?.identityStatus === 'CONFIRMATION_REQUIRED'
          "
          :disabled="busy"
          variant="outline"
          :label="t('JRC_BROKER.CONFIRM_IDENTITY')"
          @click="openConfirmation('confirmIdentity')"
        />
      </div>
      <div
        v-if="confirm"
        class="p-4 border border-n-weak rounded-lg flex flex-col gap-3"
      >
        <p>
          {{
            confirm === 'disconnect'
              ? t('JRC_BROKER.DISCONNECT_WARNING')
              : t('JRC_BROKER.IDENTITY_WARNING', {
                  suffix: health?.observedNumberSuffix || '—',
                })
          }}
        </p>
        <label class="flex gap-2 items-center">
          <input v-model="approved" type="checkbox" />
          <span>{{ t('JRC_BROKER.UNDERSTAND') }}</span>
        </label>
        <div class="flex gap-3">
          <Button
            :disabled="busy || !approved"
            :label="t('JRC_BROKER.CONFIRM')"
            @click="mutate(confirm)"
          />
          <Button
            variant="outline"
            :label="t('JRC_BROKER.CANCEL')"
            @click="
              confirm = '';
              approved = false;
            "
          />
        </div>
      </div>
    </template>
  </section>
</template>
