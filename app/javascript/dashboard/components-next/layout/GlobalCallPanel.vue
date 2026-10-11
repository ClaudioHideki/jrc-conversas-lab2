<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSipWebphone } from 'dashboard/routes/dashboard/webphone/useSipWebphone';
import WebphonePage from 'dashboard/routes/dashboard/webphone/WebphonePage.vue';
import { useCallsStore } from 'dashboard/stores/calls';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';
import WhatsappCallingPanel from 'dashboard/routes/dashboard/conversation/components/WhatsappCallingPanel.vue';

const props = defineProps({
  allowSoftphone: { type: Boolean, required: true },
  allowWhatsapp: { type: Boolean, required: true },
  allowConference: { type: Boolean, default: false },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const { isFull: nicoOpen } = useJrcCopilot();
const calls = useCallsStore();
const { isInitiating } = useWhatsappCallSession();
const { hasCall } = useSipWebphone();
const mode = ref(props.allowWhatsapp ? 'whatsapp' : 'softphone');
const closeButton = ref(null);
const startingSipCall = ref(false);
const otherCallBusy = computed(
  () => calls.hasActiveCall || calls.hasIncomingCall || isInitiating.value
);
watch(
  () => [props.allowWhatsapp, props.allowSoftphone],
  () => {
    if (mode.value === 'whatsapp' && !props.allowWhatsapp)
      mode.value = 'softphone';
    if (mode.value === 'softphone' && !props.allowSoftphone)
      mode.value = 'whatsapp';
  }
);
onMounted(() => closeButton.value?.focus({ preventScroll: true }));
</script>

<template>
  <Teleport to="body">
    <section
      data-global-call-panel
      role="dialog"
      :aria-label="t('JRC_HOME.ACTIONS.CALL')"
      aria-modal="false"
      class="fixed right-4 top-20 z-50 flex max-h-[calc(100dvh-6rem)] w-[min(23rem,calc(100vw-2rem))] flex-col overflow-hidden rounded-2xl border border-n-strong bg-n-solid-2 text-n-slate-12 shadow-2xl"
      :class="
        nicoOpen
          ? 'lg:right-[480px] xl:right-[512px] min-[1920px]:right-[532px]'
          : 'lg:right-20 xl:right-28'
      "
      @keydown.esc.stop="emit('close')"
    >
      <header
        class="flex shrink-0 items-center justify-between gap-3 border-b border-n-weak bg-n-teal-2 px-4 py-3"
      >
        <div class="flex items-center gap-2 font-semibold">
          <span
            class="i-lucide-phone-call size-5 text-n-teal-11"
            aria-hidden="true"
          />
          {{ t('JRC_HOME.ACTIONS.CALL') }}
        </div>
        <button
          ref="closeButton"
          type="button"
          :aria-label="t('SOFTPHONE.MINIMIZE')"
          :title="t('SOFTPHONE.MINIMIZE')"
          class="grid size-9 place-content-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('close')"
        >
          <span class="i-lucide-minus size-5" aria-hidden="true" />
        </button>
      </header>
      <div class="grid shrink-0 grid-cols-2 gap-2 p-3">
        <button
          v-if="allowWhatsapp"
          type="button"
          :aria-pressed="mode === 'whatsapp'"
          class="flex min-h-11 items-center justify-center gap-2 rounded-xl border text-sm font-semibold"
          :class="
            mode === 'whatsapp'
              ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-11'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="mode = 'whatsapp'"
        >
          <span class="i-ri-whatsapp-fill size-5" aria-hidden="true" />
          {{ t('SOFTPHONE.WHATSAPP') }}
        </button>
        <button
          v-if="allowSoftphone"
          type="button"
          :aria-pressed="mode === 'softphone'"
          class="flex min-h-11 items-center justify-center gap-2 rounded-xl border text-sm font-semibold"
          :class="
            mode === 'softphone'
              ? 'border-n-blue-7 bg-n-blue-3 text-n-blue-11'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="mode = 'softphone'"
        >
          <span class="i-lucide-headset size-5" aria-hidden="true" />
          {{ t('SOFTPHONE.TITLE') }}
        </button>
      </div>
      <div class="min-h-0 overflow-y-auto">
        <WhatsappCallingPanel
          v-if="allowWhatsapp"
          v-show="mode === 'whatsapp'"
          :external-busy="hasCall || startingSipCall"
        />
        <WebphonePage
          v-if="allowSoftphone"
          v-show="mode === 'softphone'"
          compact
          :external-busy="otherCallBusy"
          :allow-conference="allowConference"
          @dialing="startingSipCall = $event"
        />
      </div>
    </section>
  </Teleport>
</template>
