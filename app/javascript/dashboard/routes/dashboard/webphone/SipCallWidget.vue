<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useSipWebphone } from './useSipWebphone';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';

const { isFull: nicoOpen } = useJrcCopilot();

const TEXT = Object.freeze({
  incoming: 'Chamada recebida',
  origin: 'Origem:',
  remote: 'Número remoto:',
  answer: 'Atender',
  reject: 'Recusar',
  hangup: 'Desligar',
});

const RINGTONE_URL = '/audio/dashboard/ringtone.mp3';

const route = useRoute();
const router = useRouter();
// Route only on account entry/change. SPA navigation preserves the shared SIP renderer.
watch(
  () => route.params?.accountId,
  accountId => {
    if (
      window.jrcSoftphoneDesktop &&
      accountId &&
      route.name !== 'ramal_index'
    ) {
      router
        .replace({ name: 'ramal_index', params: { accountId } })
        .catch(() => {});
    }
  },
  { immediate: true }
);
const {
  status,
  incoming,
  established,
  remoteNumber,
  remoteStream,
  errorMessage,
  answer,
  reject,
  hangup,
} = useSipWebphone();

const remoteAudio = ref(null);
const ringtone = new Audio(RINGTONE_URL);
const visible = computed(
  () => incoming.value || (established.value && route.name !== 'ramal_index')
);

ringtone.loop = true;
ringtone.volume = 1;

const stopRingtone = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
};

watch(
  [remoteStream, remoteAudio],
  ([stream, audio]) => {
    if (!audio) return;
    audio.srcObject = stream;
    if (stream) audio.play().catch(() => {});
  },
  { flush: 'post', immediate: true }
);

watch(
  () => visible.value && incoming.value && route.name !== 'ramal_index',
  shouldRing => {
    if (shouldRing) {
      ringtone.play().catch(() => {});
    } else {
      stopRingtone();
    }
  },
  { immediate: true }
);

onBeforeUnmount(stopRingtone);
</script>

<template>
  <div class="contents">
    <aside
      v-if="visible"
      class="fixed z-50 w-[min(24rem,calc(100vw-2rem))] rounded-2xl border border-n-strong bg-n-solid-2 p-5 shadow-2xl"
      :class="
        nicoOpen
          ? 'top-20 right-5 lg:top-auto lg:bottom-5 lg:right-[416px] min-[1920px]:right-[436px]'
          : 'bottom-5 right-5'
      "
    >
      <div class="flex items-start gap-3">
        <span
          class="grid size-11 flex-shrink-0 place-items-center rounded-full"
          :class="
            incoming
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-teal-3 text-n-teal-11'
          "
        >
          <span
            class="size-5"
            :class="
              incoming ? 'i-lucide-phone-incoming' : 'i-lucide-phone-call'
            "
          />
        </span>
        <div class="min-w-0 flex-1">
          <p class="text-base font-semibold text-n-slate-12">
            {{ incoming ? TEXT.incoming : status }}
          </p>
          <p class="mt-1 truncate text-sm text-n-slate-11">
            {{ incoming ? TEXT.origin : TEXT.remote }} {{ remoteNumber }}
          </p>
        </div>
      </div>

      <p
        v-if="errorMessage"
        class="mt-4 rounded-lg bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{ errorMessage }}
      </p>

      <div v-if="incoming" class="mt-5 grid grid-cols-2 gap-3">
        <button
          type="button"
          class="min-h-11 rounded-xl border border-n-teal-7 bg-n-teal-3 px-4 font-semibold text-n-teal-11 shadow-sm hover:brightness-95"
          @click="answer"
        >
          {{ TEXT.answer }}
        </button>
        <button
          type="button"
          class="min-h-11 rounded-xl border border-n-ruby-7 bg-n-ruby-3 px-4 font-semibold text-n-ruby-11 shadow-sm hover:brightness-95"
          @click="reject"
        >
          {{ TEXT.reject }}
        </button>
      </div>
      <button
        v-else
        type="button"
        class="mt-5 min-h-11 w-full rounded-xl bg-n-ruby-9 px-4 font-semibold text-white shadow-sm hover:brightness-110"
        @click="hangup"
      >
        {{ TEXT.hangup }}
      </button>
      <audio ref="remoteAudio" autoplay />
    </aside>
  </div>
</template>
