import { onBeforeUnmount, ref, shallowRef, watch } from 'vue';
import { remuxWebmToOgg } from 'dashboard/components/widgets/WootWriter/utils/webmOpusToOgg';

// Capture is only a local draft. Saving still requires native upload, inspection and authority.
export const useInstitutionalAudioCapture = ({
  contextKey,
  canCapture,
  maxBytes,
}) => {
  const phase = ref('idle');
  const error = ref('');
  const file = shallowRef(null);
  const byteSize = ref(0);
  let generation = 0;
  let stream = null;
  let recorder = null;
  let chunks = [];
  let size = 0;
  const stopTracks = value => value?.getTracks().forEach(track => track.stop());
  const release = () => {
    stopTracks(stream);
    stream = null;
    const previous = recorder;
    recorder = null;
    if (!previous) return;
    previous.ondataavailable = null;
    previous.onstop = null;
    previous.onerror = null;
    if (previous.state !== 'inactive') {
      try {
        previous.stop();
      } catch {
        // Owned tracks are already stopped; a concurrently ended recorder has no more work.
      }
    }
  };
  const reset = () => {
    generation += 1;
    release();
    chunks = [];
    size = 0;
    file.value = null;
    byteSize.value = 0;
    error.value = '';
    phase.value = 'idle';
  };
  const fail = code => {
    reset();
    error.value = code;
    phase.value = 'error';
  };
  const active = current => current === generation && canCapture.value;
  const finish = async (current, mime) => {
    if (!active(current)) return;
    release();
    phase.value = 'processing';
    const received = new Blob(chunks, { type: mime });
    chunks = [];
    size = 0;
    if (!received.size) {
      fail('INVALID_CAPTURE');
      return;
    }
    try {
      const result = mime.startsWith('audio/webm')
        ? await remuxWebmToOgg(received)
        : received;
      if (!active(current)) return;
      if (!result.size || result.size > maxBytes.value) {
        fail('INVALID_CAPTURE');
        return;
      }
      const type = result.type.split(';')[0];
      const extension = { 'audio/ogg': 'ogg', 'audio/mp4': 'm4a' }[type];
      if (!extension)
        throw new Error('Unsupported institutional capture output');
      file.value = new File([result], `gravacao-institucional.${extension}`, {
        type,
      });
      phase.value = 'ready';
      byteSize.value = result.size;
    } catch {
      if (active(current)) fail('CAPTURE_ERROR');
    }
  };
  const start = async () => {
    if (
      !canCapture.value ||
      !maxBytes.value ||
      ['requesting', 'recording', 'processing'].includes(phase.value)
    )
      return;
    reset();
    const current = generation;
    const Recorder = window.MediaRecorder;
    const mime = [
      'audio/webm;codecs=opus',
      'audio/ogg;codecs=opus',
      'audio/mp4',
    ].find(type => Recorder?.isTypeSupported?.(type));
    if (!mime || !window.navigator?.mediaDevices?.getUserMedia) {
      fail('CAPTURE_UNSUPPORTED');
      return;
    }
    phase.value = 'requesting';
    try {
      const requested = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: false,
      });
      if (!active(current)) {
        stopTracks(requested);
        return;
      }
      stream = requested;
      const recording = new Recorder(stream, { mimeType: mime });
      recorder = recording;
      recording.onerror = () => {
        if (active(current)) fail('CAPTURE_ERROR');
      };
      recording.ondataavailable = event => {
        if (!active(current) || !event.data?.size) return;
        size += event.data.size;
        if (size > maxBytes.value) {
          fail('INVALID_CAPTURE');
          return;
        }
        chunks.push(event.data);
        byteSize.value = size;
      };
      recording.onstop = () => finish(current, recording.mimeType || mime);
      recording.start(250);
      phase.value = 'recording';
    } catch (failure) {
      if (active(current))
        fail(
          failure?.name === 'NotAllowedError'
            ? 'CAPTURE_DENIED'
            : 'CAPTURE_ERROR'
        );
    }
  };
  const stop = () => {
    if (phase.value !== 'recording' || !recorder) return;
    phase.value = 'processing';
    try {
      recorder.stop();
    } catch {
      fail('CAPTURE_ERROR');
    }
  };
  watch([contextKey, canCapture, maxBytes], reset);
  onBeforeUnmount(reset);
  return { phase, error, file, byteSize, start, stop, reset };
};
