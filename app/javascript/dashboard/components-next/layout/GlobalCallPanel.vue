<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import WebphonePage from 'dashboard/routes/dashboard/webphone/WebphonePage.vue';
import { useCallsStore } from 'dashboard/stores/calls';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';

defineProps({
  allowSoftphone: { type: Boolean, required: true },
  allowConference: { type: Boolean, default: false },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const { isFull: nicoOpen } = useJrcCopilot();
const calls = useCallsStore();
const { isInitiating } = useWhatsappCallSession();
const closeButton = ref(null);
const otherCallBusy = computed(
  () => calls.hasActiveCall || calls.hasIncomingCall || isInitiating.value
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
      <div class="min-h-0 overflow-y-auto">
        <WebphonePage
          v-if="allowSoftphone"
          compact
          :external-busy="otherCallBusy"
          :allow-conference="allowConference"
        />
      </div>
    </section>
  </Teleport>
</template>
