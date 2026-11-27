<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/jrcContactCenter';
import { destinationHistoryRoute } from '../../inbox/endingDestinationHistoryContract';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  authorityKey: { type: String, required: true },
});
const { t } = useI18n();
const actor = useMapGetter('getCurrentUserID');
const rows = ref([]);
const meta = ref(null);
const loading = ref(false);
const error = ref('');
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([
    props.accountId,
    props.recordingId,
    props.callSessionId,
    props.callId,
    props.authorityKey,
    actor.value,
  ])
);
const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
const validate = (body, page) => {
  const validRow = row =>
    identifier(row.id) &&
    row.number === row.id &&
    typeof row.title === 'string' &&
    typeof row.status?.name === 'string' &&
    ['open', 'waiting', 'resolved', 'closed', 'cancelled'].includes(
      row.status_phase
    );
  return (
    body?.contract_version === 1 &&
    body.account_id === String(props.accountId) &&
    body.user_id === String(actor.value) &&
    body.recording_id === String(props.recordingId) &&
    body.call_session_id === String(props.callSessionId) &&
    body.call_id === props.callId &&
    Array.isArray(body.items) &&
    body.items.length <= 20 &&
    body.items.every(validRow) &&
    new Set(body.items.map(row => row.id)).size === body.items.length &&
    body.meta?.page === page &&
    body.meta.per_page === 20 &&
    Number.isSafeInteger(body.meta.total) &&
    body.meta.total >= 0 &&
    body.meta.pages === Math.ceil(body.meta.total / 20) &&
    body.items.length ===
      Math.min(20, Math.max(0, body.meta.total - (page - 1) * 20))
  );
};
const load = async (page = 1) => {
  generation += 1;
  const current = generation;
  controller?.abort();
  rows.value = [];
  meta.value = null;
  error.value = '';
  loading.value = true;
  const request = new AbortController();
  controller = request;
  const original = identity.value;
  try {
    const { data } = await API.recordingTickets(
      props.accountId,
      props.recordingId,
      page,
      { signal: request.signal }
    );
    if (
      request.signal.aborted ||
      current !== generation ||
      original !== identity.value
    )
      return;
    if (!validate(data, page))
      throw new TypeError('Invalid native recording Ticket page');
    rows.value = data.items;
    meta.value = data.meta;
  } catch (failure) {
    if (current === generation && !request.signal.aborted)
      error.value = [401, 403, 404].includes(failure.response?.status)
        ? 'DENIED'
        : 'ERROR';
  } finally {
    if (current === generation) loading.value = false;
  }
};
watch(identity, () => load(1), { immediate: true, flush: 'sync' });
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  rows.value = [];
  meta.value = null;
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 p-3 text-sm"
    data-recording-linked-tickets
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <h3 class="font-semibold text-n-slate-12">
        {{ t('JRC_CONTACT_CENTER.RECORDING_TICKET.LINKED_TITLE') }}
      </h3>
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2 text-n-blue-11"
        :disabled="loading"
        @click="load(1)"
      >
        {{ t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.REFRESH') }}
      </button>
    </div>
    <p v-if="loading" role="status" class="text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.RECORDING_TICKET.LOADING') }}
    </p>
    <p v-else-if="error" role="alert" class="text-n-ruby-11">
      {{
        error === 'DENIED'
          ? t('JRC_CONTACT_CENTER.RECORDING_TICKET.LINKED_DENIED')
          : t('JRC_CONTACT_CENTER.RECORDING_TICKET.LINKED_ERROR')
      }}
    </p>
    <template v-else-if="meta">
      <p v-if="!rows.length" class="text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.RECORDING_TICKET.LINKED_EMPTY') }}
      </p>
      <ul v-else class="space-y-2">
        <li
          v-for="row in rows"
          :key="row.id"
          class="flex min-w-0 flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak p-3"
        >
          <RouterLink
            :to="
              destinationHistoryRoute(
                { kind: 'service_desk_ticket', id: row.id },
                accountId
              )
            "
            class="min-w-0 break-words font-semibold text-n-blue-11"
          >
            {{
              t('JRC_CONTACT_CENTER.RECORDING_TICKET.LINKED_LABEL', {
                number: row.number,
                title: row.title,
              })
            }}
          </RouterLink>
          <span class="break-words text-n-slate-11">{{ row.status.name }}</span>
        </li>
      </ul>
      <nav
        v-if="meta.pages > 1"
        class="flex flex-wrap gap-2"
        :aria-label="t('JRC_CONTACT_CENTER.RECORDING_TICKET.LINKED_TITLE')"
      >
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 text-n-blue-11"
          :disabled="loading || meta.page <= 1"
          @click="load(meta.page - 1)"
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.PREVIOUS') }}
        </button>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 text-n-blue-11"
          :disabled="loading || meta.page >= meta.pages"
          @click="load(meta.page + 1)"
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.NEXT') }}
        </button>
      </nav>
    </template>
  </section>
</template>
