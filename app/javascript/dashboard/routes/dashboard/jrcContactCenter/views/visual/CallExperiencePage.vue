<script setup>
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import InboxVoicePanel from '../../../inbox/InboxVoicePanel.vue';
import { callStateLabels } from '../../../inbox/inboxPresentation';
import { useSipWebphone } from '../../../webphone/useSipWebphone';
import CallWorkspace from '../CallWorkspace.vue';

const { t } = useI18n();

const route = useRoute();
const sip = useSipWebphone();
const context = ref(null);
const failed = ref(false);
const selectedCall = ref(null);
const accountId = computed(() => route.params.accountId);
const callId = computed(() =>
  Number(route.params.callId || route.query.callId)
);
const hasCall = computed(
  () => Number.isInteger(callId.value) && callId.value > 0
);
const canOperate = computed(
  () => context.value?.capabilities?.operate === true
);
const matchesSelectedCall = computed(
  () =>
    selectedCall.value?.id === callId.value &&
    selectedCall.value.provider === 'sip' &&
    selectedCall.value.external_session_id === sip.callId.value
);
const showControls = computed(
  () =>
    canOperate.value &&
    Number(sip.accountId.value) === Number(accountId.value) &&
    sip.hasCall.value &&
    !sip.incoming.value &&
    Boolean(sip.callId.value) &&
    (!hasCall.value || matchesSelectedCall.value)
);
const browserCapabilities = computed(() => ({
  ...context.value?.provider?.capabilities,
  // The browser is already connected to this exact SIP dialog.
  sip_webrtc: 'available',
}));
const updateCall = value => {
  selectedCall.value = value?.call || null;
};
const browserCallStatus = computed(() => {
  const labels = callStateLabels(t);
  if (sip.held.value) return labels.held;
  return sip.established.value ? labels.connected : labels.created;
});

let generation = 0;
watch(
  accountId,
  async id => {
    generation += 1;
    const version = generation;
    context.value = null;
    failed.value = false;
    try {
      const { data } = await JrcContactCenterAPI.context(id);
      if (version === generation) context.value = data;
    } catch {
      if (version === generation) failed.value = true;
    }
  },
  { immediate: true }
);
watch([accountId, callId], () => updateCall(null), { flush: 'sync' });
</script>

<template>
  <div class="space-y-4 p-4 sm:p-6">
    <section
      class="space-y-4 rounded-2xl bg-gradient-to-br from-teal-900 to-cyan-700 p-5 text-white shadow-sm sm:p-6"
      aria-labelledby="contact-center-call-title"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h1 id="contact-center-call-title" class="m-0 text-xl font-bold">
          {{
            showControls
              ? browserCallStatus
              : hasCall
                ? t('JRC_CONTACT_CENTER.CALL.TITLE')
                : t('JRC_CONTACT_CENTER.CALL.NO_BROWSER_CALL')
          }}
        </h1>
        <span v-if="showControls" class="rounded-lg bg-teal-950/50 px-3 py-1">
          {{ [sip.remoteNumber.value, sip.duration.value].join(' · ') }}
        </span>
      </div>
      <InboxVoicePanel
        v-if="showControls"
        :account-id="Number(accountId)"
        :allowed="canOperate"
        :capabilities="browserCapabilities"
        :native-call-id="hasCall ? callId : null"
        :call-record="hasCall ? selectedCall : null"
        :keyboard-shortcuts="false"
        controls-only
        session-view
      />
      <p v-else-if="failed" role="alert" class="m-0 text-sm">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>
      <p v-else-if="context && hasCall" class="m-0 text-sm">
        {{ t('JRC_CONTACT_CENTER.CALL.CONTROLS_ON_ORIGIN') }}
      </p>
    </section>
    <section v-if="hasCall">
      <CallWorkspace
        :key="`${accountId}-${callId}`"
        :account-id="accountId"
        :call-id="callId"
        :context="context"
        @loaded="updateCall"
      />
    </section>
  </div>
</template>
