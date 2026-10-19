import { ref, onScopeDispose, watch } from 'vue';

export const NICO_VOICE_REVIEW_MS = 1500;
const MAX_AUDIO_BYTES = 4194304;

export const useNicoVoice = ({
  onTranscript,
  onSubmit,
  transcribe,
  inCall,
  context,
  canSubmit,
  captureObserver,
}) => {
  const supported = Boolean(
    navigator.mediaDevices?.getUserMedia && window.MediaRecorder
  );
  const requesting = ref(false);
  const listening = ref(false);
  const transcribing = ref(false);
  const reviewing = ref(false);
  const error = ref('');
  const speakingEnabled = ref(false);
  const speaking = ref(false);
  let recorder;
  let stream;
  let timer;
  let reviewTimer;
  let request;
  let generation = 0;
  let speechGeneration = 0;
  let captureCleanup;

  const cancelReview = () => {
    clearTimeout(reviewTimer);
    reviewing.value = false;
  };
  const release = () => {
    clearTimeout(timer);
    captureCleanup?.();
    captureCleanup = undefined;
    stream?.getTracks().forEach(track => track.stop());
    stream = undefined;
  };
  const stopSpeaking = () => {
    speechGeneration += 1;
    speaking.value = false;
    window.speechSynthesis?.cancel();
  };
  // Cancellation invalidates capture, permission requests, upload and the review timer.
  const stop = () => {
    generation += 1;
    error.value = '';
    cancelReview();
    request?.abort();
    if (recorder?.state === 'recording') recorder.stop();
    release();
    requesting.value = false;
    listening.value = false;
    transcribing.value = false;
  };
  const reviewTranscript = (text, current) => {
    onTranscript(text);
    if (!onSubmit) return;
    reviewing.value = true;
    reviewTimer = setTimeout(() => {
      if (
        current !== generation ||
        !reviewing.value ||
        inCall.value ||
        (canSubmit && !canSubmit.value)
      ) {
        cancelReview();
        return;
      }
      // Consume the review before calling ask; manual submit cannot reuse this timer.
      cancelReview();
      onSubmit(text);
    }, NICO_VOICE_REVIEW_MS);
  };
  const start = async () => {
    error.value = '';
    if (
      !supported ||
      inCall.value ||
      transcribing.value ||
      requesting.value ||
      (canSubmit && !canSubmit.value)
    )
      return;
    if (listening.value) {
      recorder?.stop();
      return;
    }
    stop();
    stopSpeaking();
    const current = generation;
    requesting.value = true;
    try {
      const acquired = await navigator.mediaDevices.getUserMedia({
        audio: true,
      });
      if (current !== generation || inCall.value) {
        acquired.getTracks().forEach(track => track.stop());
        return;
      }
      stream = acquired;
      const mimeType = ['audio/webm', 'audio/mp4', 'audio/ogg'].find(type =>
        MediaRecorder.isTypeSupported(type)
      );
      if (!mimeType) throw new Error('unsupported_format');
      recorder = new MediaRecorder(stream, {
        mimeType,
        audioBitsPerSecond: 64000,
      });
      const chunks = [];
      let size = 0;
      let uploaded = false;
      recorder.ondataavailable = event => {
        if (current !== generation) return;
        size += event.data.size;
        if (size > MAX_AUDIO_BYTES) {
          stop();
          error.value = 'too_large';
        } else chunks.push(event.data);
      };
      recorder.onerror = () => {
        if (current !== generation) return;
        stop();
        error.value = 'recording_failed';
      };
      recorder.onstop = async () => {
        if (current !== generation || uploaded) return;
        uploaded = true;
        release();
        listening.value = false;
        transcribing.value = true;
        request = new AbortController();
        try {
          const { data } = await transcribe(
            new Blob(chunks, { type: mimeType }),
            request.signal
          );
          if (current !== generation || inCall.value) return;
          const text = String(data.text || '').trim();
          if (!text) {
            error.value = 'empty_transcript';
            return;
          }
          reviewTranscript(text, current);
        } catch (e) {
          if (current === generation && e.code !== 'ERR_CANCELED')
            error.value = 'transcription_failed';
        } finally {
          if (current === generation) transcribing.value = false;
        }
      };
      recorder.start(1000);
      listening.value = true;
      requesting.value = false;
      captureCleanup = captureObserver?.({
        stream,
        finish: () => {
          if (current === generation && recorder?.state === 'recording')
            recorder.stop();
        },
      });
      timer = setTimeout(
        () => recorder?.state === 'recording' && recorder.stop(),
        60000
      );
    } catch {
      if (current !== generation) return;
      stop();
      error.value = 'unavailable';
    }
  };
  const speak = text => {
    if (
      !speakingEnabled.value ||
      inCall.value ||
      !window.speechSynthesis ||
      !text
    )
      return;
    stop();
    stopSpeaking();
    const current = speechGeneration;
    const utterance = new SpeechSynthesisUtterance(text.slice(0, 1000));
    utterance.lang = 'pt-BR';
    utterance.onstart = () => {
      if (current === speechGeneration && !inCall.value) speaking.value = true;
    };
    const finish = () => {
      if (current === speechGeneration) speaking.value = false;
    };
    utterance.onend = finish;
    utterance.onerror = finish;
    speaking.value = true;
    try {
      window.speechSynthesis.speak(utterance);
    } catch {
      finish();
      error.value = 'speech_unavailable';
    }
  };
  watch(speakingEnabled, value => {
    if (!value) stopSpeaking();
  });
  watch(
    inCall,
    value => {
      if (value) {
        stop();
        stopSpeaking();
      }
    },
    { flush: 'sync' }
  );
  if (context)
    watch(
      context,
      () => {
        stop();
        stopSpeaking();
      },
      { flush: 'sync' }
    );
  onScopeDispose(() => {
    stop();
    stopSpeaking();
  });
  return {
    supported,
    requesting,
    listening,
    transcribing,
    reviewing,
    error,
    speakingEnabled,
    speaking,
    start,
    stop,
    speak,
    cancelReview,
    stopSpeaking,
    setSpeakingEnabled: value => {
      speakingEnabled.value = value;
    },
  };
};
