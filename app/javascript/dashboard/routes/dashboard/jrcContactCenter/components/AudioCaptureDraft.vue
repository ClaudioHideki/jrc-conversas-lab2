<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { useInstitutionalAudioCapture } from '../composables/useInstitutionalAudioCapture';

const props = defineProps({
  contextKey: { type: String, required: true },
  disabled: { type: Boolean, required: true },
  maxBytes: { type: Number, required: true },
});
const emit = defineEmits(['selected', 'busy', 'discard']);
const { t } = useI18n();
const labels = computed(() => ({
  LIMITS: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.LIMITS'),
  START: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.START'),
  STOP: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.STOP'),
  DISCARD: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.DISCARD'),
  USE: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.USE'),
  LOCAL_PREVIEW: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.LOCAL_PREVIEW'),
  REQUESTING: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.REQUESTING'),
  RECORDING: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.RECORDING'),
  PROCESSING: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.PROCESSING'),
  CAPTURE_DENIED: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.CAPTURE_DENIED'),
  CAPTURE_UNSUPPORTED: t(
    'JRC_CONTACT_CENTER.AUDIO_CAPTURE.CAPTURE_UNSUPPORTED'
  ),
  CAPTURE_ERROR: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.CAPTURE_ERROR'),
  INVALID_CAPTURE: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.INVALID_CAPTURE'),
  BYTES: t('JRC_CONTACT_CENTER.AUDIO_FILES.BYTES'),
}));
const label = key => labels.value[key];
const capture = useInstitutionalAudioCapture({
  contextKey: computed(() => props.contextKey),
  canCapture: computed(() => !props.disabled),
  maxBytes: computed(() => props.maxBytes),
});
const { phase, error, file, byteSize } = capture;
const active = computed(() =>
  ['requesting', 'recording', 'processing'].includes(phase.value)
);
const url = ref('');
const player = ref(null);
const { uid } = getCurrentInstance();
useEmitter('pause_playing_audio', current => {
  if (current !== uid) player.value?.pause();
});
const startedPlaying = () => emitter.emit('pause_playing_audio', uid);
const clearPreview = () => {
  player.value?.pause();
  if (url.value) URL.revokeObjectURL(url.value);
  url.value = '';
};
watch(
  [file, () => props.disabled],
  ([value, disabled]) => {
    clearPreview();
    if (value && !disabled) url.value = URL.createObjectURL(value);
  },
  { flush: 'sync' }
);
watch(active, value => emit('busy', value));
const start = () => {
  emit('discard');
  startedPlaying();
  capture.start();
};
const discard = () => {
  clearPreview();
  capture.reset();
  emit('discard');
};
onBeforeUnmount(clearPreview);
</script>

<template>
  <section
    data-institutional-capture
    class="min-w-0 space-y-3 rounded-xl border border-n-weak p-3"
  >
    <p class="break-words text-n-slate-11">{{ label('LIMITS') }}</p>
    <p v-if="error" role="alert" class="break-words text-n-ruby-11">
      {{ label(error) }}
    </p>
    <p v-if="active" role="status" class="break-words text-n-blue-11">
      {{ label(phase.toUpperCase()) }}
    </p>
    <p
      v-if="active"
      data-institutional-captured-bytes
      :data-bytes="byteSize"
      class="break-words text-n-slate-11"
    >
      {{ byteSize }} {{ label('BYTES') }}
    </p>
    <div class="flex min-w-0 flex-wrap gap-2">
      <button
        type="button"
        :disabled="disabled || active"
        data-start-institutional-capture
        class="rounded-lg bg-n-blue-9 px-3 py-2 text-white disabled:opacity-40"
        @click="start"
      >
        {{ label('START') }}
      </button>
      <button
        v-if="phase === 'recording'"
        type="button"
        data-stop-institutional-capture
        class="rounded-lg border border-n-ruby-6 px-3 py-2 text-n-ruby-11"
        @click="capture.stop"
      >
        {{ label('STOP') }}
      </button>
      <button
        v-if="phase !== 'idle'"
        type="button"
        :disabled="disabled"
        data-discard-institutional-capture
        class="rounded-lg border border-n-weak px-3 py-2 text-n-slate-12 disabled:opacity-40"
        @click="discard"
      >
        {{ label('DISCARD') }}
      </button>
    </div>
    <template v-if="file && url">
      <p class="break-words text-n-slate-12">{{ label('LOCAL_PREVIEW') }}</p>
      <audio
        ref="player"
        :src="url"
        controls
        preload="metadata"
        :aria-label="label('LOCAL_PREVIEW')"
        data-institutional-capture-preview
        class="w-full min-w-0 max-w-full [color-scheme:light] dark:[color-scheme:dark]"
        @play="startedPlaying"
      />
      <button
        type="button"
        :disabled="disabled || active"
        data-use-institutional-capture
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11 disabled:opacity-40"
        @click="emit('selected', file)"
      >
        {{ label('USE') }}
      </button>
    </template>
  </section>
</template>
