import { ref, watch, onScopeDispose, computed } from 'vue';
import { useNicoVoice } from './useNicoVoice';

export const NICO_VOICE_CONVERSATION_MS = 300000;
export const NICO_VOICE_CONVERSATION_TURNS = 12;

export const useNicoVoiceConversation = options => {
  const continuousActive = ref(false);
  const continuousTurns = ref(0);
  const submitting = ref(false);
  let voice;
  let idleTimer;
  let deadline;
  let previousSpeaking = false;
  let generation = 0;
  const halt = () => {
    const wasActive = continuousActive.value;
    continuousActive.value = false;
    generation += 1;
    clearTimeout(idleTimer);
    clearTimeout(deadline);
    const error = voice?.error.value;
    voice?.stop();
    voice?.stopSpeaking();
    if (wasActive && error) voice.error.value = error;
    if (wasActive) voice.setSpeakingEnabled(previousSpeaking);
  };
  const observeCapture = ({ stream, finish }) => {
    if (!continuousActive.value) return undefined;
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    const audio = new AudioContext();
    const source = audio.createMediaStreamSource(stream);
    const analyser = audio.createAnalyser();
    analyser.fftSize = 1024;
    source.connect(analyser);
    const samples = new Uint8Array(analyser.fftSize);
    let heard = false;
    let lastSound = Date.now();
    let finished = false;
    const poll = setInterval(() => {
      analyser.getByteTimeDomainData(samples);
      const energy = Math.sqrt(
        samples.reduce((sum, value) => sum + ((value - 128) / 128) ** 2, 0) /
          samples.length
      );
      if (energy > 0.02) {
        heard = true;
        lastSound = Date.now();
      }
      if (heard && !finished && Date.now() - lastSound >= 1500) {
        finished = true;
        finish();
      }
    }, 100);
    if (audio.state === 'suspended')
      audio.resume().catch(() => {
        voice.error.value = 'unavailable';
      });
    return () => {
      clearInterval(poll);
      source.disconnect();
      Promise.resolve(audio.close()).catch(() => {});
    };
  };
  voice = useNicoVoice({
    ...options,
    captureObserver: observeCapture,
    onSubmit: async text => {
      const current = generation;
      const automatic = continuousActive.value;
      submitting.value = true;
      if (automatic) {
        continuousTurns.value += 1;
        if (continuousTurns.value >= NICO_VOICE_CONVERSATION_TURNS) halt();
      }
      try {
        const accepted = await options.onSubmit?.(text);
        if (automatic && current === generation && accepted !== true) {
          voice.error.value = 'submission_unconfirmed';
          halt();
        }
      } catch {
        if (current === generation) {
          voice.error.value = 'submission_unconfirmed';
          halt();
        }
      } finally {
        submitting.value = false;
      }
    },
  });
  const continuousSupported =
    voice.supported &&
    Boolean(window.AudioContext || window.webkitAudioContext) &&
    Boolean(window.speechSynthesis?.speak);
  const continuousCanStart = computed(
    () =>
      continuousSupported &&
      !continuousActive.value &&
      !options.inCall.value &&
      !options.pendingApproval?.value &&
      options.active?.value !== false &&
      options.canSubmit?.value !== false &&
      !voice.requesting.value &&
      !voice.listening.value &&
      !voice.transcribing.value &&
      !voice.reviewing.value
  );
  const ready = () =>
    continuousActive.value &&
    !submitting.value &&
    !voice.requesting.value &&
    !voice.listening.value &&
    !voice.transcribing.value &&
    !voice.reviewing.value &&
    !voice.speaking.value &&
    !options.inCall.value &&
    (!options.canSubmit || options.canSubmit.value) &&
    (!options.active || options.active.value) &&
    !options.pendingApproval?.value;
  const schedule = () => {
    clearTimeout(idleTimer);
    if (ready())
      idleTimer = setTimeout(() => {
        if (ready()) voice.start().catch(halt);
      }, 500);
  };
  watch(
    () => [
      continuousActive.value,
      submitting.value,
      voice.requesting.value,
      voice.listening.value,
      voice.transcribing.value,
      voice.reviewing.value,
      voice.speaking.value,
      options.canSubmit?.value,
    ],
    schedule,
    { flush: 'sync' }
  );
  watch(
    () => [
      options.inCall.value,
      options.pendingApproval?.value,
      options.active?.value,
      options.context?.value,
    ],
    (next, previous) => {
      if (next[0] || next[1] || next[2] === false || next[3] !== previous[3])
        halt();
    },
    { flush: 'sync' }
  );
  watch(
    voice.error,
    value => {
      if (value && continuousActive.value) halt();
    },
    { flush: 'sync' }
  );
  const onVisibility = () => {
    if (typeof document !== 'undefined' && document.hidden) halt();
  };
  if (typeof document !== 'undefined')
    document.addEventListener('visibilitychange', onVisibility);
  onScopeDispose(() => {
    halt();
    if (typeof document !== 'undefined')
      document.removeEventListener('visibilitychange', onVisibility);
  });
  return {
    ...voice,
    continuousActive,
    continuousTurns,
    continuousSupported,
    continuousCanStart,
    startConversation: async () => {
      if (!continuousCanStart.value) return;
      previousSpeaking = voice.speakingEnabled.value;
      generation += 1;
      continuousTurns.value = 0;
      continuousActive.value = true;
      voice.setSpeakingEnabled(true);
      deadline = setTimeout(halt, NICO_VOICE_CONVERSATION_MS);
      await voice.start();
    },
    stopConversation: halt,
    suspendCapture: voice.stop,
    start: async () => {
      if (continuousActive.value && !voice.listening.value) halt();
      await voice.start();
    },
    stop: halt,
    cancelReview: () => {
      if (continuousActive.value) halt();
      voice.cancelReview();
    },
    stopSpeaking: () => {
      if (continuousActive.value) halt();
      voice.stopSpeaking();
    },
    setSpeakingEnabled: value => {
      if (continuousActive.value) halt();
      voice.setSpeakingEnabled(value);
    },
  };
};
