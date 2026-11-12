<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  inboxId: { type: Number, required: true },
});
const { t } = useI18n();
const progress = ref(null);
const error = ref(false);
const busy = ref(false);
let generation = 0;
let controller;
let timer;
let pending = false;
const phaseLabel = computed(() => {
  const run = progress.value?.run;
  const state = ['PAUSED', 'CANCELED'].includes(run?.state)
    ? run.state
    : run?.capture;
  return {
    WAITING_IDENTITY: t('JRC_BROKER.HISTORY_SYNC.WAITING_IDENTITY'),
    CAPTURING: t('JRC_BROKER.HISTORY_SYNC.CAPTURING'),
    COMPLETE: t('JRC_BROKER.HISTORY_SYNC.COMPLETE'),
    PARTIAL: t('JRC_BROKER.HISTORY_SYNC.PARTIAL'),
    BLOCKED: t('JRC_BROKER.HISTORY_SYNC.BLOCKED'),
    PAUSED: t('JRC_BROKER.HISTORY_SYNC.PAUSED'),
    CANCELED: t('JRC_BROKER.HISTORY_SYNC.CANCELED'),
  }[state];
});
const stop = () => {
  generation += 1;
  controller?.abort();
  clearInterval(timer);
  progress.value = null;
  pending = false;
};
const valid = value => {
  if (
    value?.schemaVersion !== 2 ||
    value.accountId !== Number(props.accountId) ||
    value.inboxId !== props.inboxId
  )
    return false;
  if (value.run === null) return true;
  const run = value.run;
  return (
    run &&
    typeof run.sourceTotalKnown === 'boolean' &&
    [
      'WAITING_IDENTITY',
      'CAPTURING',
      'COMPLETE',
      'PARTIAL',
      'BLOCKED',
    ].includes(run.capture) &&
    [
      'RUNNING',
      'PAUSED',
      'CANCELED',
      'COMPLETED',
      'PARTIAL',
      'BLOCKED',
    ].includes(run.state) &&
    [
      'chats',
      'capturedMessages',
      'persistedMessages',
      'duplicateMessages',
      'projectedMessages',
      'pendingMedia',
      'verifiedMedia',
      'unavailableMedia',
      'blockedRecords',
    ].every(
      field =>
        Number.isSafeInteger(run.counts?.[field]) && run.counts[field] >= 0
    )
  );
};
const load = async () => {
  if (pending || controller?.signal.aborted) return;
  const current = generation;
  pending = true;
  busy.value = true;
  try {
    const value = await createJrcBrokerApi(props.accountId).historySync(
      props.inboxId,
      controller.signal
    );
    if (current !== generation) return;
    if (!valid(value)) throw new Error('HISTORY_PROGRESS_SCOPE');
    progress.value = value;
    error.value = false;
  } catch {
    if (current === generation) {
      progress.value = null;
      error.value = true;
    }
  } finally {
    if (current === generation) {
      pending = false;
      busy.value = false;
    }
  }
};
watch(
  () => [props.accountId, props.inboxId],
  () => {
    stop();
    controller = new AbortController();
    error.value = false;
    load();
    timer = setInterval(() => {
      if (document.visibilityState !== 'hidden') load();
    }, 5000);
  },
  { immediate: true }
);
onBeforeUnmount(stop);
</script>

<template>
  <section
    class="mb-5 rounded-xl border border-n-weak bg-n-solid-1 p-5"
    :aria-label="t('JRC_BROKER.HISTORY_SYNC.TITLE')"
  >
    <div class="mb-3 flex flex-wrap items-center justify-between gap-3">
      <h3 class="text-sm font-semibold">
        {{ t('JRC_BROKER.HISTORY_SYNC.TITLE') }}
      </h3>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-blue-text disabled:opacity-50"
        :disabled="busy"
        @click="load"
      >
        {{ t('JRC_BROKER.HISTORY_SYNC.REFRESH') }}
      </button>
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_BROKER.HISTORY_SYNC.ERROR') }}
    </p>
    <p v-else-if="!progress" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.HISTORY_SYNC.LOADING') }}
    </p>
    <p v-else-if="!progress.run" class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.HISTORY_SYNC.EMPTY') }}
    </p>
    <div v-else aria-live="polite" class="space-y-3 text-sm">
      <p class="font-medium">{{ phaseLabel }}</p>
      <p v-if="!progress.run.sourceTotalKnown" class="text-n-slate-11">
        {{ t('JRC_BROKER.HISTORY_SYNC.UNKNOWN_TOTAL') }}
      </p>
      <dl class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <div>
          <dt class="font-medium">
            {{ t('JRC_BROKER.HISTORY_SYNC.CAPTURE') }}
          </dt>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.CHATS', {
                count: progress.run.counts.chats,
              })
            }}
          </dd>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.CAPTURED', {
                count: progress.run.counts.capturedMessages,
              })
            }}
          </dd>
        </div>
        <div>
          <dt class="font-medium">{{ t('JRC_BROKER.HISTORY_SYNC.BROKER') }}</dt>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.PERSISTED', {
                count: progress.run.counts.persistedMessages,
              })
            }}
          </dd>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.DUPLICATES', {
                count: progress.run.counts.duplicateMessages,
              })
            }}
          </dd>
        </div>
        <div>
          <dt class="font-medium">
            {{ t('JRC_BROKER.HISTORY_SYNC.CENTRAL') }}
          </dt>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.PROJECTED', {
                count: progress.run.counts.projectedMessages,
                total: progress.run.counts.persistedMessages,
              })
            }}
          </dd>
        </div>
        <div>
          <dt class="font-medium">{{ t('JRC_BROKER.HISTORY_SYNC.MEDIA') }}</dt>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.PENDING_MEDIA', {
                count: progress.run.counts.pendingMedia,
              })
            }}
          </dd>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.VERIFIED_MEDIA', {
                count: progress.run.counts.verifiedMedia,
              })
            }}
          </dd>
          <dd>
            {{
              t('JRC_BROKER.HISTORY_SYNC.UNAVAILABLE_MEDIA', {
                count: progress.run.counts.unavailableMedia,
              })
            }}
          </dd>
        </div>
      </dl>
      <p
        v-if="
          progress.run.counts.blockedRecords ||
          progress.run.counts.unavailableMedia ||
          progress.run.lastError
        "
        role="status"
      >
        {{ t('JRC_BROKER.HISTORY_SYNC.PENDING') }}
      </p>
      <p class="text-n-slate-11">
        {{ t('JRC_BROKER.HISTORY_SYNC.BACKGROUND') }}
      </p>
    </div>
  </section>
</template>
