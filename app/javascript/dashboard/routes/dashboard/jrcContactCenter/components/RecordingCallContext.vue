<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import LinkedContactMaster from './LinkedContactMaster.vue';
import RecordingTicketAction from './RecordingTicketAction.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  recordingId: { type: [String, Number], default: null },
  operationalContextAllowed: { type: Boolean, default: false },
});
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.TITLE'),
  SOURCE: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.SOURCE'),
  LOADING: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.LOADING'),
  RESTRICTED: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.RESTRICTED'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.ERROR'),
  RETRY: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.RETRY'),
  QUEUE: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.QUEUE'),
  CONTACT: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.CONTACT'),
  COMPANY: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.COMPANY'),
  UNKNOWN: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.UNKNOWN'),
  AMBIGUOUS: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.AMBIGUOUS'),
  UNLINKED: t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.UNLINKED'),
  NATIVE_MASTER_LIMIT: t(
    'JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.NATIVE_MASTER_LIMIT'
  ),
}));
const text = key => labels.value[key];
const call = ref(null);
const loading = ref(false);
const error = ref('');
let generation = 0;
const customer = computed(() => call.value?.customer);
const linked = computed(() => {
  const value = customer.value;
  return (
    props.operationalContextAllowed &&
    call.value?.contact_id &&
    value?.status === 'identified' &&
    value.ambiguous === false &&
    value.contacts?.length === 1 &&
    String(value.contacts[0].id) === String(call.value.contact_id)
  );
});
const contact = computed(() =>
  linked.value ? customer.value.contacts[0] : null
);
const state = computed(() => {
  if (customer.value?.status === 'restricted') return 'RESTRICTED';
  if (customer.value?.ambiguous) return 'AMBIGUOUS';
  return 'UNLINKED';
});
async function load() {
  generation += 1;
  const own = generation;
  const account = String(props.accountId);
  const session = String(props.callSessionId);
  const external = props.callId;
  call.value = null;
  error.value = '';
  loading.value = false;
  if (!props.operationalContextAllowed) {
    error.value = 'RESTRICTED';
    return;
  }
  loading.value = true;
  try {
    const { data } = await API.call(account, session);
    if (own !== generation) return;
    if (
      String(data.account_id) !== account ||
      String(data.item?.id) !== session ||
      data.item?.external_session_id !== external
    )
      throw new Error('native_call_context_identity_mismatch');
    call.value = data.item;
  } catch (failure) {
    if (own !== generation) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? 'RESTRICTED'
      : 'ERROR';
  } finally {
    if (own === generation) loading.value = false;
  }
}
watch(
  () => [
    props.accountId,
    props.callSessionId,
    props.callId,
    props.operationalContextAllowed,
  ],
  load,
  { immediate: true, flush: 'pre' }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 p-3 text-n-slate-12"
    data-recording-call-context
  >
    <h3 class="font-semibold">{{ text('TITLE') }}</h3>
    <p class="text-xs text-n-slate-11">{{ text('SOURCE') }}</p>
    <p v-if="loading" role="status">{{ text('LOADING') }}</p>
    <div v-else-if="error" class="space-y-2">
      <p role="alert" class="text-n-ruby-11">{{ text(error) }}</p>
      <button
        v-if="operationalContextAllowed"
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2"
        data-recording-context-retry
        @click="load"
      >
        {{ text('RETRY') }}
      </button>
    </div>
    <template v-else-if="call">
      <dl class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2">
        <div class="min-w-0">
          <dt class="text-xs text-n-slate-11">{{ text('QUEUE') }}</dt>
          <dd class="break-words">{{ call.queue?.name || text('UNKNOWN') }}</dd>
        </div>
        <div class="min-w-0">
          <dt class="text-xs text-n-slate-11">{{ text('CONTACT') }}</dt>
          <dd class="break-words" data-recording-context-contact>
            {{ contact?.name || text('UNKNOWN') }}
          </dd>
        </div>
        <div class="min-w-0">
          <dt class="text-xs text-n-slate-11">{{ text('COMPANY') }}</dt>
          <dd class="break-words" data-recording-context-company>
            {{ contact?.company?.name || text('UNKNOWN') }}
          </dd>
        </div>
      </dl>
      <p v-if="!linked" role="status" data-recording-context-identity>
        {{ text(state) }}
      </p>
      <LinkedContactMaster
        v-if="linked"
        :key="`${accountId}-${callSessionId}`"
        :account-id="accountId"
        :call="call"
        :customer="customer"
        :enabled="operationalContextAllowed"
        show-history
        @updated="load"
      />
      <RecordingTicketAction
        v-if="linked && recordingId"
        :key="`${accountId}-${recordingId}-${callSessionId}`"
        :account-id="accountId"
        :recording-id="recordingId"
        :call-session-id="callSessionId"
        :call-id="callId"
        :contact-id="call.contact_id"
        :enabled="operationalContextAllowed"
      />
      <p class="text-xs text-n-slate-11">{{ text('NATIVE_MASTER_LIMIT') }}</p>
    </template>
  </section>
</template>
