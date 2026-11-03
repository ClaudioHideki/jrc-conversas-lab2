<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  inboxId: { type: Number, required: true },
});
const { t } = useI18n();
const entries = ref([]);
const cursor = ref(null);
const filter = ref('');
const busy = ref(false);
const error = ref('');
const types = [
  'CONNECT_REQUESTED',
  'RECONNECT_REQUESTED',
  'CONNECTED',
  'RECONNECTED',
  'DISCONNECT_REQUESTED',
  'DISCONNECTED',
  'QR_EXPIRED',
  'NUMBER_MISMATCH',
  'IDENTITY_CONFIRMED',
  'SESSION_FAILED',
  'DISTRIBUTION_FALLBACK',
  'CONFIGURATION_CHANGED',
  'PERMISSIONS_CHANGED',
];
const labels = computed(() => ({
  CONNECT_REQUESTED: t('JRC_BROKER.HISTORY.EVENTS.CONNECT_REQUESTED'),
  RECONNECT_REQUESTED: t('JRC_BROKER.HISTORY.EVENTS.RECONNECT_REQUESTED'),
  CONNECTED: t('JRC_BROKER.HISTORY.EVENTS.CONNECTED'),
  RECONNECTED: t('JRC_BROKER.HISTORY.EVENTS.RECONNECTED'),
  DISCONNECT_REQUESTED: t('JRC_BROKER.HISTORY.EVENTS.DISCONNECT_REQUESTED'),
  DISCONNECTED: t('JRC_BROKER.HISTORY.EVENTS.DISCONNECTED'),
  QR_EXPIRED: t('JRC_BROKER.HISTORY.EVENTS.QR_EXPIRED'),
  NUMBER_MISMATCH: t('JRC_BROKER.HISTORY.EVENTS.NUMBER_MISMATCH'),
  IDENTITY_CONFIRMED: t('JRC_BROKER.HISTORY.EVENTS.IDENTITY_CONFIRMED'),
  SESSION_FAILED: t('JRC_BROKER.HISTORY.EVENTS.SESSION_FAILED'),
  DISTRIBUTION_FALLBACK: t('JRC_BROKER.HISTORY.EVENTS.DISTRIBUTION_FALLBACK'),
  CONFIGURATION_CHANGED: t('JRC_BROKER.HISTORY.EVENTS.CONFIGURATION_CHANGED'),
  PERMISSIONS_CHANGED: t('JRC_BROKER.HISTORY.EVENTS.PERMISSIONS_CHANGED'),
}));
let controller;
let generation = 0;
const validTime = value =>
  typeof value === 'string' && Number.isFinite(Date.parse(value));
const load = async (more = false) => {
  if (more && busy.value) return;
  generation += 1;
  const current = generation;
  controller?.abort();
  controller = new AbortController();
  if (!more) {
    entries.value = [];
    cursor.value = null;
  }
  busy.value = true;
  error.value = '';
  try {
    const result = await createJrcBrokerApi(props.accountId).connectionHistory(
      props.inboxId,
      { before: more ? cursor.value : null, event_type: filter.value },
      controller.signal
    );
    if (current !== generation) return;
    entries.value = [...entries.value, ...result.data];
    cursor.value = result.next_cursor;
  } catch (failure) {
    if (current !== generation) return;
    const denied = [401, 403, 404].includes(failure?.response?.status);
    if (denied) entries.value = [];
    cursor.value = null;
    error.value = denied ? 'DENIED' : 'UNAVAILABLE';
  } finally {
    if (current === generation) busy.value = false;
  }
};
watch(
  () => [props.accountId, props.inboxId, filter.value],
  () => load(),
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section
    class="flex flex-col gap-4 rounded-xl border border-n-weak p-5"
    data-testid="connection-history"
  >
    <h3 class="text-lg font-semibold">{{ t('JRC_BROKER.HISTORY.TITLE') }}</h3>
    <p class="text-sm text-n-slate-11">{{ t('JRC_BROKER.HISTORY.HELP') }}</p>
    <label class="flex flex-col gap-2 text-sm">
      {{ t('JRC_BROKER.HISTORY.FILTER') }}
      <select v-model="filter">
        <option value="">{{ t('JRC_BROKER.HISTORY.ALL') }}</option>
        <option v-for="type in types" :key="type" :value="type">
          {{ labels[type] }}
        </option>
      </select>
    </label>
    <p v-if="error" role="alert">
      {{
        error === 'DENIED'
          ? t('JRC_BROKER.ERROR.DENIED')
          : t('JRC_BROKER.ERROR.UNAVAILABLE')
      }}
    </p>
    <p v-else-if="!busy && !entries.length">
      {{ t('JRC_BROKER.HISTORY.EMPTY') }}
    </p>
    <ol class="flex flex-col gap-3">
      <li
        v-for="entry in entries"
        :key="entry.id"
        class="rounded-lg border border-n-weak p-3 text-sm"
      >
        <p class="font-medium">
          {{ labels[entry.event_type] }}
        </p>
        <time v-if="validTime(entry.occurred_at)" :datetime="entry.occurred_at">
          {{ new Date(entry.occurred_at).toLocaleString() }}
        </time>
        <p>
          {{
            entry.user_id
              ? t('JRC_BROKER.DISTRIBUTION.ACTOR', { id: entry.user_id })
              : t('JRC_BROKER.DISTRIBUTION.ACTOR_SYSTEM')
          }}
        </p>
        <p v-if="entry.status_before || entry.status_after">
          {{
            t('JRC_BROKER.HISTORY.TRANSITION', {
              before: entry.status_before || '—',
              after: entry.status_after || '—',
            })
          }}
        </p>
        <p v-if="entry.metadata?.error_code">{{ entry.metadata.error_code }}</p>
        <p v-if="entry.correlation_id" class="break-all text-n-slate-11">
          {{ t('JRC_BROKER.HISTORY.REFERENCE', { id: entry.correlation_id }) }}
        </p>
      </li>
    </ol>
    <p v-if="busy" role="status">
      {{ t('JRC_BROKER.DISTRIBUTION.HISTORY_LOADING') }}
    </p>
    <Button
      v-if="cursor"
      data-testid="history-more"
      variant="outline"
      :disabled="busy"
      :label="t('JRC_BROKER.HISTORY.MORE')"
      @click="load(true)"
    />
  </section>
</template>
