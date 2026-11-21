<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WaveSurfer from 'wavesurfer.js';

const props = defineProps({
  url: { type: String, required: true },
  media: { type: Object, default: null },
  metadata: { type: Object, required: true },
  byteSize: { type: Number, required: true },
});
const { t } = useI18n();
const messages = computed(() => ({
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_WAVEFORM.LOADING'),
  LIMIT: t('JRC_CONTACT_CENTER.AUDIO_WAVEFORM.LIMIT'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_WAVEFORM.ERROR'),
}));
const container = ref(null);
const progress = ref(null);
const state = ref('');
const samples = ref(0);
let waveform;
let generation = 0;

// Optional visualization bounds, not upload or playback limits. Longer media keeps its native player.
const withinBounds = () =>
  Number.isSafeInteger(props.byteSize) &&
  props.byteSize > 0 &&
  props.byteSize <= 20 * 1024 * 1024 &&
  Number.isSafeInteger(props.metadata.duration_ms) &&
  props.metadata.duration_ms > 0 &&
  props.metadata.duration_ms <= 600000 &&
  [1, 2].includes(props.metadata.channels);

const clear = () => {
  generation += 1;
  waveform?.destroy();
  waveform = null;
  samples.value = 0;
  state.value = '';
};
const start = () => {
  clear();
  if (!container.value || !props.media || !props.url.startsWith('blob:'))
    return;
  if (!withinBounds()) {
    state.value = 'LIMIT';
    return;
  }
  const current = generation;
  state.value = 'LOADING';
  try {
    const surface = WaveSurfer.create({
      container: container.value,
      media: props.media,
      url: props.url,
      height: 64,
      waveColor: getComputedStyle(container.value).color,
      progressColor: getComputedStyle(progress.value).color,
      cursorColor: getComputedStyle(progress.value).color,
      autoplay: false,
      interact: false,
      hideScrollbar: true,
      sampleRate: 8000,
    });
    waveform = surface;
    surface.on('redrawcomplete', () => {
      if (current !== generation) return;
      const decoded = surface.getDecodedData();
      if (
        !decoded?.length ||
        decoded.duration > 600 ||
        decoded.numberOfChannels > 2
      ) {
        state.value = 'ERROR';
        return;
      }
      samples.value = decoded.length;
      state.value = 'READY';
    });
    surface.on('error', () => {
      if (current === generation) state.value = 'ERROR';
    });
  } catch {
    state.value = 'ERROR';
  }
};
watch(
  [
    container,
    () => props.media,
    () => props.url,
    () => props.metadata,
    () => props.byteSize,
  ],
  start,
  { flush: 'post' }
);
onBeforeUnmount(clear);
</script>

<template>
  <div
    class="min-w-0 space-y-2"
    :data-audio-waveform="state"
    :data-decoded-samples="samples"
  >
    <span ref="progress" class="hidden text-n-blue-12" aria-hidden="true" />
    <div
      v-show="state === 'LOADING' || state === 'READY'"
      ref="container"
      role="img"
      :aria-label="t('JRC_CONTACT_CENTER.AUDIO_WAVEFORM.LABEL')"
      :aria-busy="state === 'LOADING'"
      class="min-w-0 max-w-full overflow-hidden rounded-lg bg-n-slate-2 text-n-blue-10"
    />
    <p
      v-if="state && state !== 'READY'"
      role="status"
      class="break-words text-n-slate-11"
    >
      {{ messages[state] }}
    </p>
  </div>
</template>
