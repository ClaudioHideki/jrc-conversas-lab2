<script setup>
import { computed, getCurrentInstance, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { useAudioBytes } from '../composables/useAudioBytes';
import AudioWaveform from './AudioWaveform.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  assetId: { type: String, required: true },
  version: { type: Object, required: true },
  inspectionId: { type: String, required: true },
  metadata: { type: Object, required: true },
  canManage: { type: Boolean, required: true },
  openOnMount: { type: Boolean, default: false },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const labels = computed(() => ({
  LIMITS: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.LIMITS'),
  OPEN: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.OPEN'),
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.LOADING'),
  PLAYER: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.PLAYER'),
  DOWNLOAD: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.DOWNLOAD'),
  CLOSE: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.CLOSE'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.ERROR'),
  NOT_READY: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.NOT_READY'),
  PLAYBACK_ERROR: t('JRC_CONTACT_CENTER.AUDIO_PREVIEW.PLAYBACK_ERROR'),
}));
const label = key => labels.value[key];
const player = ref(null);
const { uid } = getCurrentInstance();
useEmitter('pause_playing_audio', current => {
  if (current !== uid) player.value?.pause();
});
const startedPlaying = () => emitter.emit('pause_playing_audio', uid);
const { url, loading, error, open, clear, playbackFailed, download } =
  useAudioBytes({
    accountId: computed(() => props.accountId),
    assetId: computed(() => props.assetId),
    version: computed(() => props.version),
    inspectionId: computed(() => props.inspectionId),
    canManage: computed(() => props.canManage),
    onDenied: () => emit('denied'),
  });
watch(url, () => player.value?.pause(), { flush: 'sync' });
onMounted(() => {
  if (props.openOnMount) open();
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 p-3"
    data-audio-version-preview
  >
    <p class="break-words text-n-slate-11">{{ label('LIMITS') }}</p>
    <button
      type="button"
      :disabled="!canManage || loading"
      data-open-audio-bytes
      class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
      @click="open"
    >
      {{ label(loading ? 'LOADING' : 'OPEN') }}
    </button>
    <p v-if="error" role="alert" class="break-words text-n-ruby-11">
      {{ label(error) }}
    </p>
    <div v-if="url" class="min-w-0 space-y-3">
      <audio
        v-if="error !== 'PLAYBACK_ERROR'"
        ref="player"
        :src="url"
        controls
        preload="metadata"
        :aria-label="label('PLAYER')"
        class="block w-full min-w-0 max-w-full [color-scheme:light] dark:[color-scheme:dark]"
        data-audio-verified-player
        @error="playbackFailed"
        @play="startedPlaying"
      />
      <AudioWaveform
        v-if="error !== 'PLAYBACK_ERROR'"
        :url="url"
        :media="player"
        :metadata="metadata"
        :byte-size="version.byte_size"
      />
      <div class="flex flex-wrap gap-3">
        <button
          type="button"
          :disabled="loading || !canManage"
          data-download-audio-bytes
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
          @click="download"
        >
          {{ label('DOWNLOAD') }}
        </button>
        <button
          type="button"
          class="rounded-lg px-3 py-2 text-n-blue-11"
          data-close-audio-bytes
          @click="clear"
        >
          {{ label('CLOSE') }}
        </button>
      </div>
    </div>
  </section>
</template>
